use std::sync::atomic::{AtomicBool, Ordering};

use serde_json::Value;
use tokio::sync::{mpsc, oneshot};

use crate::julia_session::JuliaSession;
use crate::types::JuliaCommand;

/// 通过命令通道向 Julia 派发请求，返回结果。
pub async fn dispatch_via_channel(
    cmd_tx: &mpsc::Sender<JuliaCommand>,
    action: &str,
    params: Value,
) -> Result<Result<Value, String>, String> {
    let (reply_tx, reply_rx) = oneshot::channel();
    cmd_tx
        .send((action.to_string(), params, reply_tx))
        .await
        .map_err(|_| "Julia 命令通道已关闭。".to_string())?;
    reply_rx
        .await
        .map_err(|_| "Julia 响应通道已关闭。".to_string())
}

/// 通过命令通道向 Julia 发送导出请求并提取 content 字段。
pub async fn dispatch_export_via_channel(
    cmd_tx: &mpsc::Sender<JuliaCommand>,
    task_id: &str,
    params: Value,
) -> Result<String, axum::response::Response> {
    use crate::types::JuliaResponse;

    let result = dispatch_via_channel(cmd_tx, crate::types::actions::EXPORT_REPORT, params).await;

    match result {
        Ok(Ok(resp)) => {
            let status = resp
                .get("status")
                .and_then(|value| value.as_str())
                .unwrap_or("error");
            if status != "success" {
                use crate::types::Message;
                let messages: Vec<Message> = resp
                    .get("messages")
                    .and_then(|value| serde_json::from_value(value.clone()).ok())
                    .unwrap_or_default();
                let text = messages
                    .first()
                    .map(|m| m.text.clone())
                    .unwrap_or_else(|| "Julia 导出返回错误状态。".to_string());
                return Err(crate::handlers::json_error_response(
                    axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                    task_id.to_string(),
                    "RUNTIME_EXPORT_FAILED",
                    text,
                    None,
                ));
            }
            let content = resp
                .pointer("/result_payload/content")
                .and_then(|value| value.as_str())
                .map(|s| s.to_string())
                .or_else(|| {
                    serde_json::from_value::<JuliaResponse>(resp.clone())
                        .ok()
                        .map(|jr| jr.content().to_string())
                })
                .unwrap_or_default();
            Ok(content)
        }
        Ok(Err(err)) => Err(crate::handlers::json_error_response(
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            task_id.to_string(),
            "RUNTIME_EXPORT_FAILED",
            format!("Julia 导出失败: {err}"),
            None,
        )),
        Err(send_err) => Err(crate::handlers::json_error_response(
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            task_id.to_string(),
            "RUNTIME_INTERNAL_ERROR",
            send_err,
            None,
        )),
    }
}

/// 启动 Julia actor 并返回命令发送端和健康标志。
///
/// Actor 在独立 OS 线程中串行处理 Julia 请求，
/// HTTP handler 通过 channel 发送命令，不持有任何 Mutex。
pub fn spawn_julia_actor(session: JuliaSession) -> (mpsc::Sender<JuliaCommand>, std::sync::Arc<AtomicBool>) {
    let julia_healthy = std::sync::Arc::new(AtomicBool::new(session.is_healthy()));
    let healthy_flag = julia_healthy.clone();
    let (cmd_tx, mut cmd_rx) = mpsc::channel::<JuliaCommand>(64);

    std::thread::spawn(move || {
        let mut session = session;
        loop {
            match cmd_rx.blocking_recv() {
                Some((action, params, reply_tx)) => {
                    let result = session.send_request(&action, params);
                    healthy_flag.store(result.is_ok(), Ordering::Release);
                    let _ = reply_tx.send(result);
                }
                None => break,
            }
        }
    });

    (cmd_tx, julia_healthy)
}
