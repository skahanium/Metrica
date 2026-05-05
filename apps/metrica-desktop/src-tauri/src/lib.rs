use std::path::PathBuf;
use std::process::{Child, Command};
use tao::event_loop::{ControlFlow, EventLoop};
use tao::window::Icon;
use wry::{http::Response, WebViewBuilder};

/// 持有 Runtime 子进程句柄，退出时自动清理。
struct RuntimeGuard(Option<Child>);

impl Drop for RuntimeGuard {
    fn drop(&mut self) {
        if let Some(ref mut child) = self.0 {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

/// 定位 metrica-runtime 二进制。
fn find_runtime_bin() -> Result<PathBuf, String> {
    if let Ok(path) = std::env::var("METRICA_RUNTIME_BIN") {
        let p = PathBuf::from(&path);
        if p.is_file() {
            return Ok(p);
        }
        return Err(format!("METRICA_RUNTIME_BIN 指定的路径不存在：{path}"));
    }

    // CARGO_MANIFEST_DIR = apps/metrica-desktop/src-tauri，向上 3 层到仓库根。
    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent() // src-tauri
        .and_then(|p| p.parent()) // metrica-desktop
        .and_then(|p| p.parent()) // apps
        .map(|p| p.to_path_buf())
        .unwrap_or_default();

    for profile in &["debug", "release"] {
        let bin = repo_root.join(format!(
            "runtime/metrica-runtime/target/{profile}/metrica-runtime"
        ));
        if bin.is_file() {
            return Ok(bin);
        }
    }

    Err("找不到 metrica-runtime 二进制。请先构建 Runtime（cargo build --manifest-path runtime/metrica-runtime/Cargo.toml），或通过 METRICA_RUNTIME_BIN 环境变量指定路径。".to_string())
}

/// 启动 metrica-runtime 子进程，绑定默认地址。
fn spawn_runtime() -> Result<Child, String> {
    let bin = find_runtime_bin()?;
    Command::new(&bin)
        .arg("serve")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|err| format!("启动 Runtime 失败（{}）：{err}", bin.display()))
}

/// 获取前端资源目录的绝对路径。
fn app_dir() -> PathBuf {
    // CARGO_MANIFEST_DIR = apps/metrica-desktop/src-tauri，向上 1 层即前端目录。
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."))
}

/// 读取前端文件内容，返回 bytes 与 MIME 类型。
fn read_frontend_file(path: &str) -> Option<(Vec<u8>, String)> {
    let safe = path.trim_start_matches('/');
    let file_path = app_dir().join("dist").join(safe);
    let mime = match file_path.extension().and_then(|e| e.to_str()) {
        Some("html") => "text/html; charset=utf-8",
        Some("js") => "application/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        _ => "application/octet-stream",
    };
    std::fs::read(&file_path).ok().map(|data| (data, mime.to_string()))
}

/// 加载应用图标。
fn load_icon() -> Option<Icon> {
    let icon_path = app_dir().join("dist/assets/icons/metrica-icon-128x128.png");
    let data = std::fs::read(&icon_path).ok()?;
    let decoder = png::Decoder::new(std::io::Cursor::new(&data));
    let mut reader = decoder.read_info().ok()?;
    let mut buf = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf).ok()?;
    let rgba = buf[..info.buffer_size()].to_vec();
    Icon::from_rgba(rgba, info.width, info.height).ok()
}

pub fn run() {
    let event_loop = EventLoop::new();
    let mut window_builder = tao::window::WindowBuilder::new()
        .with_title("Metrica Alpha — 真实 OLS 链路")
        .with_inner_size(tao::dpi::LogicalSize::new(1200.0, 800.0));

    if let Some(icon) = load_icon() {
        window_builder = window_builder.with_window_icon(Some(icon));
    }

    let window = window_builder.build(&event_loop).expect("创建窗口失败");

    let _runtime = spawn_runtime().ok().map(|child| RuntimeGuard(Some(child)));
    if _runtime.is_none() {
        eprintln!("Runtime 启动失败，请手动启动后刷新。");
    }

    let _webview = WebViewBuilder::new()
        .with_custom_protocol("metrica".into(), move |_id, request| {
            let uri = request.uri();
            let path = uri.path();
            let path = if path.is_empty() || path == "/" {
                "index.html"
            } else {
                path
            };

            if let Some((data, mime)) = read_frontend_file(path) {
                Response::builder()
                    .status(200)
                    .header("Content-Type", &mime)
                    .header("Access-Control-Allow-Origin", "*")
                    .body(data.into())
                    .unwrap()
            } else {
                Response::builder()
                    .status(404)
                    .body(b"not found".to_vec().into())
                    .unwrap()
            }
        })
        .with_url("metrica://localhost/index.html")
        .build(&window)
        .expect("创建 WebView 失败");

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;
        if let tao::event::Event::WindowEvent {
            event: tao::event::WindowEvent::CloseRequested,
            ..
        } = event
        {
            *control_flow = ControlFlow::Exit;
        }
    });
}
