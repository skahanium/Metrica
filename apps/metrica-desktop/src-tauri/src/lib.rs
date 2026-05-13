use std::io::Read;
use std::path::PathBuf;
use std::process::{Child, Command};
use std::os::unix::net::{UnixListener, UnixStream};
use std::thread;
use tao::event_loop::{ControlFlow, EventLoop};
use tao::window::Icon;
use wry::{http::Response, WebViewBuilder};

const LOCK_SOCKET_PATH: &str = "/tmp/metrica-desktop.lock";

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

fn json_response(status: u16, body: serde_json::Value) -> Response<std::borrow::Cow<'static, [u8]>> {
    Response::builder()
        .status(status)
        .header("Content-Type", "application/json; charset=utf-8")
        .header("Access-Control-Allow-Origin", "*")
        .body(body.to_string().into_bytes().into())
        .unwrap()
}

#[cfg(target_os = "macos")]
fn pick_csv_path() -> Result<Option<String>, String> {
    use objc::{class, msg_send, sel, sel_impl};
    use std::ffi::CStr;
    use std::os::raw::c_char;

    const NS_MODAL_RESPONSE_OK: i64 = 1;
    const YES: i8 = 1;
    const NO: i8 = 0;

    unsafe {
        let panel: *mut objc::runtime::Object = msg_send![class!(NSOpenPanel), openPanel];
        let _: () = msg_send![panel, setCanChooseFiles:YES];
        let _: () = msg_send![panel, setCanChooseDirectories:NO];
        let _: () = msg_send![panel, setAllowsMultipleSelection:NO];

        let response: i64 = msg_send![panel, runModal];
        if response != NS_MODAL_RESPONSE_OK {
            return Ok(None);
        }

        let url: *mut objc::runtime::Object = msg_send![panel, URL];
        if url.is_null() {
            return Ok(None);
        }

        let path: *mut objc::runtime::Object = msg_send![url, path];
        if path.is_null() {
            return Ok(None);
        }

        let c_path: *const c_char = msg_send![path, UTF8String];
        if c_path.is_null() {
            return Err("无法读取所选文件路径。".to_string());
        }

        let path = CStr::from_ptr(c_path)
            .to_str()
            .map_err(|_| "所选文件路径包含无法解析的字符。".to_string())?
            .to_string();

        Ok(Some(path))
    }
}

#[cfg(not(target_os = "macos"))]
fn pick_csv_path() -> Result<Option<String>, String> {
    Err("当前宿主不支持选择本地 CSV 文件".to_string())
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

/// 在 macOS 上设置 NSApplication 图标（Dock 栏 + 应用切换器）。
/// tao 的 with_window_icon 在 macOS 上是空操作。
/// 通过 NSApplication API 直接设置 Dock 图标和应用身份。
#[cfg(target_os = "macos")]
fn macos_set_app_icon() {
    use objc::{class, msg_send, sel, sel_impl};
    use std::ffi::CString;

    let icon_path = app_dir().join("dist/assets/icons/metrica-icon-128x128.png");
    let cstr = match CString::new(icon_path.to_str().unwrap_or("")) {
        Ok(c) => c,
        Err(_) => { eprintln!("[icon] CString failed"); return; }
    };

    unsafe {
        let app: *mut objc::runtime::Object = msg_send![class!(NSApplication), sharedApplication];

        // 设置为 Regular 应用（独立 Dock 图标 + 菜单栏）
        // NSApplicationActivationPolicyRegular = 0
        let _: () = msg_send![app, setActivationPolicy:0usize];

        // 加载图标
        let nsstr: *mut objc::runtime::Object = msg_send![class!(NSString), stringWithUTF8String:cstr.as_ptr()];
        if nsstr.is_null() {
            eprintln!("[icon] NSString failed");
            return;
        }

        let image: *mut objc::runtime::Object = msg_send![class!(NSImage), alloc];
        let image: *mut objc::runtime::Object = msg_send![image, initWithContentsOfFile:nsstr];
        if image.is_null() {
            eprintln!("[icon] NSImage initWithContentsOfFile failed");
            return;
        }

        let size: NSSize = msg_send![image, size];
        eprintln!("[icon] NSImage size: {}x{}", size.width, size.height);

        let _: () = msg_send![app, setApplicationIconImage:image];

        eprintln!("[icon] macOS app icon set + activationPolicy=Regular");
    }
}

#[repr(C)]
#[derive(Debug)]
struct NSSize {
    width: f64,
    height: f64,
}

/// 在 macOS 上安装最小但标准的应用菜单。
/// 重点是补齐 Edit 菜单，让 WebView 内文本编辑能走 responder chain，
/// 从而恢复 Command+C / Command+V / Command+X / Command+A 等快捷键。
#[cfg(target_os = "macos")]
fn macos_install_app_menu() {
    use objc::{class, msg_send, sel, sel_impl};
    use objc::runtime::{Object, Sel};
    use std::ffi::CString;

    const NS_COMMAND_KEY_MASK: usize = 1 << 20;
    const NS_SHIFT_KEY_MASK: usize = 1 << 17;

    fn nsstring(value: &str) -> *mut Object {
        let cstr = CString::new(value).expect("菜单标题不能包含 NUL");
        unsafe { msg_send![class!(NSString), stringWithUTF8String: cstr.as_ptr()] }
    }

    fn menu_item(title: &str, action: Sel, key: &str, modifiers: usize) -> *mut Object {
        unsafe {
            let item: *mut Object = msg_send![class!(NSMenuItem), alloc];
            let item: *mut Object = msg_send![
                item,
                initWithTitle: nsstring(title)
                action: action
                keyEquivalent: nsstring(key)
            ];
            let _: () = msg_send![item, setKeyEquivalentModifierMask: modifiers];
            item
        }
    }

    unsafe {
        let app: *mut Object = msg_send![class!(NSApplication), sharedApplication];
        let main_menu: *mut Object = msg_send![class!(NSMenu), new];

        let null_sel: Sel = std::mem::zeroed();

        // 应用菜单：至少提供 About 和 Quit，保证菜单栏结构完整。
        let app_root: *mut Object = msg_send![class!(NSMenuItem), new];
        let _: () = msg_send![main_menu, addItem: app_root];
        let app_menu: *mut Object = msg_send![class!(NSMenu), new];
        let about_item = menu_item("About Metrica", sel!(orderFrontStandardAboutPanel:), "", 0);
        let _: () = msg_send![app_menu, addItem: about_item];
        let separator: *mut Object = msg_send![class!(NSMenuItem), separatorItem];
        let _: () = msg_send![app_menu, addItem: separator];
        let quit_item = menu_item("Quit Metrica", sel!(terminate:), "q", NS_COMMAND_KEY_MASK);
        let _: () = msg_send![app_menu, addItem: quit_item];
        let _: () = msg_send![app_root, setSubmenu: app_menu];

        // Edit 菜单：把标准编辑 selector 接回 first responder chain。
        let edit_root = menu_item("Edit", null_sel, "", 0);
        let _: () = msg_send![main_menu, addItem: edit_root];
        let edit_menu: *mut Object = msg_send![class!(NSMenu), new];
        let undo_item = menu_item("Undo", sel!(undo:), "z", NS_COMMAND_KEY_MASK);
        let redo_item = menu_item("Redo", sel!(redo:), "Z", NS_COMMAND_KEY_MASK | NS_SHIFT_KEY_MASK);
        let cut_item = menu_item("Cut", sel!(cut:), "x", NS_COMMAND_KEY_MASK);
        let copy_item = menu_item("Copy", sel!(copy:), "c", NS_COMMAND_KEY_MASK);
        let paste_item = menu_item("Paste", sel!(paste:), "v", NS_COMMAND_KEY_MASK);
        let select_all_item = menu_item("Select All", sel!(selectAll:), "a", NS_COMMAND_KEY_MASK);
        let separator: *mut Object = msg_send![class!(NSMenuItem), separatorItem];
        let _: () = msg_send![edit_menu, addItem: undo_item];
        let _: () = msg_send![edit_menu, addItem: redo_item];
        let _: () = msg_send![edit_menu, addItem: separator];
        let _: () = msg_send![edit_menu, addItem: cut_item];
        let _: () = msg_send![edit_menu, addItem: copy_item];
        let _: () = msg_send![edit_menu, addItem: paste_item];
        let _: () = msg_send![edit_menu, addItem: select_all_item];
        let _: () = msg_send![edit_root, setSubmenu: edit_menu];

        let _: () = msg_send![app, setMainMenu: main_menu];
    }
}

#[cfg(not(target_os = "macos"))]
fn macos_install_app_menu() {}

#[cfg(not(target_os = "macos"))]
fn macos_set_app_icon() {
    // 非 macOS 平台不做额外处理，tao 的 with_window_icon 已足够。
}

/// 通知已有实例激活窗口，返回 true 表示成功通知（应退出当前进程）。
fn notify_existing_instance() -> bool {
    if let Ok(mut stream) = UnixStream::connect(LOCK_SOCKET_PATH) {
        // 尝试发送激活消息并等待短暂响应，以确认对方确实存活
        stream.set_read_timeout(Some(std::time::Duration::from_millis(200))).ok();
        if std::io::Write::write_all(&mut stream, b"activate").is_ok() {
            // 尝试读取 ACK 确认
            let mut buf = [0u8; 4];
            if stream.read_exact(&mut buf).is_ok() && &buf == b"ack!" {
                return true;
            }
            // 对方无响应 — 视为陈旧锁
        }
    }
    false
}

/// 尝试获取单实例锁。返回 Some(listener) 表示是首个实例，
/// 返回 None 表示已有实例在运行。
fn try_acquire_lock() -> Option<UnixListener> {
    // 先尝试通知已有实例（含活性检测）
    if notify_existing_instance() {
        eprintln!("Metrica 已在运行，将已运行的实例前置。");
        return None;
    }
    // 清理残留的 socket 文件（陈旧锁或首次启动）
    let _ = std::fs::remove_file(LOCK_SOCKET_PATH);
    // 尝试绑定
    UnixListener::bind(LOCK_SOCKET_PATH).ok()
}

pub fn run() {
    let lock = match try_acquire_lock() {
        Some(l) => l,
        None => {
            eprintln!("Metrica 已在运行，将已运行的实例前置。");
            // 等待一下确保消息送达
            thread::sleep(std::time::Duration::from_millis(100));
            std::process::exit(0);
        }
    };

    let event_loop = EventLoop::new();
    let mut window_builder = tao::window::WindowBuilder::new()
        .with_title("Metrica Alpha — 真实 OLS 链路")
        .with_inner_size(tao::dpi::LogicalSize::new(1200.0, 800.0));

    if let Some(icon) = load_icon() {
        window_builder = window_builder.with_window_icon(Some(icon));
    }

    // macOS 需要通过 NSApp 设置 Dock 图标
    macos_set_app_icon();
    // macOS 需要原生菜单才能让标准编辑快捷键进入 responder chain。
    macos_install_app_menu();

    // 禁用 macOS 自动终止，防止系统在窗口不可见时杀掉进程
    #[cfg(target_os = "macos")]
    {
        use objc::{class, msg_send, sel, sel_impl};
        unsafe {
            let process_info: *mut objc::runtime::Object = msg_send![class!(NSProcessInfo), processInfo];
            let reason: *mut objc::runtime::Object = msg_send![class!(NSString), stringWithUTF8String: std::ffi::CString::new("user-facing desktop app").unwrap().as_ptr()];
            let _: () = msg_send![process_info, disableAutomaticTermination: reason];
        }
    }

    let window = window_builder.build(&event_loop).expect("创建窗口失败");

    // 后台线程：监听激活请求（第二个实例启动时发送），回复 ACK 证明存活
    let event_loop_proxy = event_loop.create_proxy();
    thread::spawn(move || {
        let listener = lock;
        for mut stream in listener.incoming().flatten() {
            let mut buf = [0u8; 16];
            if matches!(stream.read(&mut buf), Ok(n) if n > 0) {
                // 发送 ACK 确认存活，防止启动方误判陈旧锁
                let _ = std::io::Write::write_all(&mut stream, b"ack!");
                let _ = event_loop_proxy.send_event(());
            }
        }
    });

    let _runtime = spawn_runtime().ok().map(|child| RuntimeGuard(Some(child)));
    if _runtime.is_none() {
        eprintln!("Runtime 启动失败，请手动启动后刷新。");
    }

    let _webview = WebViewBuilder::new()
        .with_custom_protocol("metrica".into(), move |_id, request| {
            let uri = request.uri();
            let path = uri.path();
            if path == "/__native__/pick_csv" {
                return match pick_csv_path() {
                    Ok(Some(path)) => json_response(200, serde_json::json!({
                        "path": path,
                        "cancelled": false,
                    })),
                    Ok(None) => json_response(200, serde_json::json!({
                        "path": serde_json::Value::Null,
                        "cancelled": true,
                    })),
                    Err(err) => json_response(501, serde_json::json!({
                        "error": err,
                    })),
                };
            }
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
        match event {
            tao::event::Event::WindowEvent {
                event: tao::event::WindowEvent::CloseRequested,
                ..
            } => {
                let _ = std::fs::remove_file(LOCK_SOCKET_PATH);
                *control_flow = ControlFlow::Exit;
            }
            tao::event::Event::UserEvent(()) => {
                // 第二个实例启动时收到激活请求
                window.set_focus();
                #[cfg(target_os = "macos")]
                {
                    use objc::{class, msg_send, sel, sel_impl};
                    unsafe {
                        let app: *mut objc::runtime::Object = msg_send![class!(NSApplication), sharedApplication];
                        let _: () = msg_send![app, activateIgnoringOtherApps: true];
                    }
                }
            }
            _ => {}
        }
    });
}
