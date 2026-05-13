use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::time::Duration;

use serde_json::{json, Value};

// use crate::repo_root; — 当前未使用（路径由调用方传入）

const JULIA_DAEMON_SCRIPT: &str = include_str!("../../../scripts/julia_daemon.jl");
const MAX_RESTARTS: u32 = 3;
const READY_TIMEOUT_SECS: u64 = 30;
const REQUEST_TIMEOUT_SECS: u64 = 60;
const SHUTDOWN_TIMEOUT_SECS: u64 = 5;

/// 持久化 Julia 守护进程会话。
///
/// 通过 stdin/stdout JSON lines 通信。所有 I/O 方法是同步的，
/// 调用方应通过 `tokio::task::spawn_blocking` 包裹以避免阻塞 async 运行时。
///
/// stdout 读取通过独立线程 + mpsc channel 实现，避免 `read_line` 阻塞
/// 导致超时判断失效。
pub struct JuliaSession {
    child: Option<Child>,
    stdin: Option<ChildStdin>,
    stdout_rx: Option<mpsc::Receiver<Result<String, String>>>,
    reader_handle: Option<std::thread::JoinHandle<()>>,
    request_counter: u64,
    healthy: AtomicBool,
    restart_count: AtomicU32,
    repo_root: String,
    project_path: String,
}

impl JuliaSession {
    /// 启动 Julia 守护进程，等待 `{"type":"ready"}` 就绪信号。
    ///
    /// 启动一个独立的 reader 线程从 stdout 逐行读取，通过 mpsc channel
    /// 发送给主线程，从而让 `recv_timeout` 能正确实现超时。
    pub fn start(repo_root: &str, project_path: &str) -> Result<Self, String> {
        let julia_bin = std::env::var("JULIA_BIN").unwrap_or_else(|_| "julia".to_string());
        let mut child = Command::new(&julia_bin)
            .arg(format!("--project={project_path}"))
            .arg("--startup-file=no")
            .arg("--color=no")
            .arg("-e")
            .arg(JULIA_DAEMON_SCRIPT)
            .env("METRICA_REPO_ROOT", repo_root)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|err| format!("启动 Julia 守护进程失败: {err}"))?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| "无法获取 Julia stdin 管道。".to_string())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "无法获取 Julia stdout 管道。".to_string())?;

        let reader = BufReader::new(stdout);
        let (tx, rx) = mpsc::channel();

        // 独立线程：逐行读取 stdout 并通过 channel 发送
        let reader_handle = std::thread::spawn(move || {
            let mut reader = reader;
            loop {
                let mut line = String::new();
                match reader.read_line(&mut line) {
                    Ok(0) => {
                        let _ = tx.send(Err("EOF".into()));
                        break;
                    }
                    Ok(_) => {
                        if tx.send(Ok(line)).is_err() {
                            break;
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Err(e.to_string()));
                        break;
                    }
                }
            }
        });

        // 等待就绪信号：通过 recv_timeout 实现真实超时
        loop {
            match rx.recv_timeout(Duration::from_secs(READY_TIMEOUT_SECS)) {
                Ok(Ok(line)) => {
                    let trimmed = line.trim();
                    if let Ok(parsed) = serde_json::from_str::<Value>(trimmed) {
                        if parsed.get("type").and_then(|v| v.as_str()) == Some("ready") {
                            break;
                        }
                    }
                    // 非 ready 行，继续等待
                }
                Ok(Err(e)) => {
                    // EOF 或读取错误
                    let _ = child.kill();
                    let _ = child.wait();
                    if e == "EOF" {
                        return Err(format!(
                            "Julia 守护进程在就绪前退出（EOF）。"
                        ));
                    }
                    return Err(format!("读取 Julia 就绪信号失败: {e}"));
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(format!(
                        "Julia 守护进程在 {READY_TIMEOUT_SECS} 秒内未发送就绪信号。"
                    ));
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err("Julia stdout 读取线程意外终止。".to_string());
                }
            }
        }

        Ok(Self {
            child: Some(child),
            stdin: Some(stdin),
            stdout_rx: Some(rx),
            reader_handle: Some(reader_handle),
            request_counter: 0,
            healthy: AtomicBool::new(true),
            restart_count: AtomicU32::new(0),
            repo_root: repo_root.to_string(),
            project_path: project_path.to_string(),
        })
    }

    /// 检查 Julia 守护进程是否健康。
    pub fn is_healthy(&self) -> bool {
        self.healthy.load(Ordering::Acquire)
    }

    /// 获取当前已重启次数。
    pub fn restart_count(&self) -> u32 {
        self.restart_count.load(Ordering::Acquire)
    }

    /// 发送请求到 Julia 守护进程，返回响应载荷。
    ///
    /// 此方法执行阻塞 I/O，应由 `tokio::task::spawn_blocking` 包裹调用。
    pub fn send_request(&mut self, action: &str, params: Value) -> Result<Value, String> {
        if !self.check_alive() {
            self.try_restart()?;
        }

        self.request_counter += 1;
        let request_id = format!("req-{}", self.request_counter);

        let request = json!({
            "id": request_id,
            "action": action,
            "params": params,
        });

        let request_line = serde_json::to_string(&request)
            .map_err(|err| format!("序列化 Julia 请求失败: {err}"))?;

        {
            let stdin = self
                .stdin
                .as_mut()
                .ok_or_else(|| "Julia stdin 管道不可用。".to_string())?;
            writeln!(stdin, "{request_line}")
                .map_err(|err| format!("写入 Julia stdin 失败: {err}"))?;
            stdin
                .flush()
                .map_err(|err| format!("刷新 Julia stdin 失败: {err}"))?;
        }

        let rx = self
            .stdout_rx
            .as_ref()
            .ok_or_else(|| "Julia stdout channel 不可用。".to_string())?;

        loop {
            match rx.recv_timeout(Duration::from_secs(REQUEST_TIMEOUT_SECS)) {
                Ok(Ok(line)) => {
                    let trimmed = line.trim();
                    if let Ok(parsed) = serde_json::from_str::<Value>(trimmed) {
                        if parsed.get("id").and_then(|v| v.as_str()) == Some(&request_id) {
                            return Ok(parsed);
                        }
                        // 跳过不匹配的响应（可能是上一次的残留或错误通知）
                    }
                }
                Ok(Err(e)) => {
                    // EOF 或读取错误
                    self.mark_unhealthy();
                    if e == "EOF" {
                        self.try_restart()?;
                        return Err("Julia 进程意外退出。已尝试重启，请重试请求。".to_string());
                    }
                    return Err(format!("读取 Julia stdout 失败: {e}"));
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    self.mark_unhealthy();
                    return Err(format!(
                        "Julia 请求 {request_id} 在 {REQUEST_TIMEOUT_SECS} 秒内未响应。"
                    ));
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    self.mark_unhealthy();
                    return Err("Julia stdout 读取线程意外终止。".to_string());
                }
            }
        }
    }

    /// 关闭 Julia 守护进程。
    ///
    /// 发送 shutdown 动作并等待进程退出；超时后强制终止。
    pub fn shutdown(&mut self) -> Result<(), String> {
        if let Some(ref mut stdin) = self.stdin {
            let _ = writeln!(stdin, r#"{{"action":"shutdown"}}"#);
            let _ = stdin.flush();
        }

        if let Some(ref mut child) = self.child {
            // 等待优雅退出
            let start = std::time::Instant::now();
            loop {
                match child.try_wait() {
                    Ok(Some(_)) => break,
                    Ok(None) => {
                        if start.elapsed() > Duration::from_secs(SHUTDOWN_TIMEOUT_SECS) {
                            let _ = child.kill();
                            let _ = child.wait();
                            break;
                        }
                        std::thread::sleep(Duration::from_millis(100));
                    }
                    Err(_) => {
                        let _ = child.kill();
                        break;
                    }
                }
            }
        }

        self.stdin = None;
        self.stdout_rx = None;
        // reader_handle 线程会在 channel 关闭后自行退出（tx 被 drop），
        // 不阻塞等待它，避免 shutdown 期间死锁。
        self.reader_handle = None;
        self.child = None;
        self.healthy.store(false, Ordering::Release);

        Ok(())
    }

    // === 内部方法 ===

    fn check_alive(&mut self) -> bool {
        if let Some(ref mut child) = self.child {
            match child.try_wait() {
                Ok(None) => true,
                _ => {
                    self.mark_unhealthy();
                    false
                }
            }
        } else {
            false
        }
    }

    fn mark_unhealthy(&self) {
        self.healthy.store(false, Ordering::Release);
    }

    fn try_restart(&mut self) -> Result<(), String> {
        let current = self.restart_count.load(Ordering::Acquire);
        if current >= MAX_RESTARTS {
            return Err(format!(
                "Julia 守护进程已崩溃 {MAX_RESTARTS} 次，已达最大重启次数。请手动检查 Julia 环境。"
            ));
        }

        // 清理旧进程
        if let Some(ref mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
        self.stdin = None;
        self.stdout_rx = None;
        self.reader_handle = None;

        self.restart_count.store(current + 1, Ordering::Release);

        // 重新启动（使用 ManuallyDrop 避免 Drop 冲突）
        let mut fresh = std::mem::ManuallyDrop::new(
            Self::start(&self.repo_root, &self.project_path)?
        );
        self.child = fresh.child.take();
        self.stdin = fresh.stdin.take();
        self.stdout_rx = fresh.stdout_rx.take();
        self.reader_handle = fresh.reader_handle.take();
        self.healthy.store(true, Ordering::Release);

        Ok(())
    }
}

impl Drop for JuliaSession {
    fn drop(&mut self) {
        let _ = self.shutdown();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 构造一个 mock shell 脚本，模拟 Julia 守护进程的 stdin/stdout 协议。
    /// 不需要真实 Julia 安装。
    fn mock_daemon_command(behavior: &str) -> Command {
        let script = match behavior {
            "ready_then_echo" => {
                r#"
                echo '{"type":"ready"}'
                while IFS= read -r line; do
                    action=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('action',''))" 2>/dev/null || true)
                    if [ "$action" = "shutdown" ]; then break; fi
                    id=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
                    echo "{\"id\":\"$id\",\"status\":\"success\",\"payload\":{\"echo\":true}}"
                done
                "#
            }
            "crash_after_ready" => {
                r#"
                echo '{"type":"ready"}'
                exit 1
                "#
            }
            "no_ready" => {
                r#"sleep 60"#
            }
            _ => "echo '{}'",
        };

        let mut cmd = Command::new("sh");
        cmd.arg("-c").arg(script)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        cmd
    }

    /// 使用 mock shell 进程构造 JuliaSession（绕过真实 Julia 启动流程）。
    /// 仅用于测试内部 send_request/shutdown 逻辑。
    fn mock_session_from_command(mut cmd: Command) -> JuliaSession {
        let mut child = cmd.spawn().expect("spawn mock daemon");

        let stdin = child.stdin.take().expect("stdin");
        let stdout = child.stdout.take().expect("stdout");
        let reader = BufReader::new(stdout);
        let (tx, rx) = mpsc::channel();

        // 独立线程读取 mock 进程的 stdout
        let reader_handle = std::thread::spawn(move || {
            let mut reader = reader;
            loop {
                let mut line = String::new();
                match reader.read_line(&mut line) {
                    Ok(0) => {
                        let _ = tx.send(Err("EOF".into()));
                        break;
                    }
                    Ok(_) => {
                        if tx.send(Ok(line)).is_err() {
                            break;
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Err(e.to_string()));
                        break;
                    }
                }
            }
        });

        // 消费 ready 信号
        loop {
            match rx.recv_timeout(Duration::from_secs(5)) {
                Ok(Ok(line)) => {
                    if line.trim().contains("ready") {
                        break;
                    }
                }
                _ => break,
            }
        }

        JuliaSession {
            child: Some(child),
            stdin: Some(stdin),
            stdout_rx: Some(rx),
            reader_handle: Some(reader_handle),
            request_counter: 0,
            healthy: AtomicBool::new(true),
            // 预置为 MAX_RESTARTS 以避免 mock 测试触发真实 Julia 重启
            restart_count: AtomicU32::new(MAX_RESTARTS),
            repo_root: String::new(),
            project_path: String::new(),
        }
    }

    #[test]
    fn send_request_returns_matching_response() {
        let mut session =
            mock_session_from_command(mock_daemon_command("ready_then_echo"));
        let response = session
            .send_request("fit_model", json!({"test": true}))
            .expect("send_request");
        assert_eq!(response["status"], "success");
        assert_eq!(response["payload"]["echo"], true);
        let _ = session.shutdown();
    }

    #[test]
    fn multiple_requests_get_unique_ids() {
        let mut session =
            mock_session_from_command(mock_daemon_command("ready_then_echo"));
        let r1 = session
            .send_request("inspect_dataset", json!({"a": 1}))
            .expect("req 1");
        let r2 = session
            .send_request("fit_model", json!({"b": 2}))
            .expect("req 2");
        assert!(r1["id"] != r2["id"]);
        let _ = session.shutdown();
    }

    #[test]
    fn broken_pipe_marks_unhealthy() {
        let mut session =
            mock_session_from_command(mock_daemon_command("crash_after_ready"));
        // 第一次请求后进程崩溃
        let result = session.send_request("fit_model", json!({}));
        // 应该出错（管道断裂或 EOF）
        assert!(result.is_err() || !session.is_healthy());
        let _ = session.shutdown();
    }
}
