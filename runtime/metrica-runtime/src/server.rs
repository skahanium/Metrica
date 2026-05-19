use std::sync::atomic::AtomicBool;

use axum::{
    http::{header, Method},
    routing::{get, post},
    Router,
};
use tokio::sync::mpsc;
use tower_http::cors::CorsLayer;

use crate::julia_actor::spawn_julia_actor;
use crate::julia_session::JuliaSession;
use crate::types::JuliaCommand;

const DEFAULT_BIND_ADDR: &str = "127.0.0.1:47821";

pub fn default_bind_addr() -> &'static str {
    DEFAULT_BIND_ADDR
}

/// 应用共享状态：Julia 命令发送端 + 健康标志。
#[derive(Clone)]
pub struct AppState {
    pub cmd_tx: mpsc::Sender<JuliaCommand>,
    pub julia_healthy: std::sync::Arc<AtomicBool>,
}

impl AppState {
    /// 从 JuliaSession 创建 AppState：启动 actor 线程并返回可共享的应用状态。
    pub fn from_session(session: JuliaSession) -> Self {
        let (cmd_tx, julia_healthy) = spawn_julia_actor(session);
        Self { cmd_tx, julia_healthy }
    }
}

/// 构建含所有路由和 CORS 中间件的 axum Router。
pub fn build_router(state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE]);

    Router::new()
        .route("/health", get(crate::handlers::health_handler))
        .route("/fit_model", post(crate::handlers::fit_model_handler))
        .route("/inspect_dataset", post(crate::handlers::inspect_dataset_handler))
        .route("/query_dataset", post(crate::handlers::query_dataset_handler))
        .route("/transform", post(crate::handlers::transform_handler))
        .route("/run_diagnostic", post(crate::handlers::run_diagnostic_handler))
        .route("/save_project", post(crate::handlers::save_project_handler))
        .route("/load_project", post(crate::handlers::load_project_handler))
        .route("/list_runs", post(crate::handlers::list_runs_handler))
        .route("/rerun_task", post(crate::handlers::rerun_task_handler))
        .route("/export_report", post(crate::handlers::export_report_handler))
        .layer(cors)
        .with_state(state)
}

/// 构建使用每请求 Julia 子进程的 axum Router（`--oneshot` 回退模式）。
///
/// S3 项目系统端点（save_project / load_project / list_runs）为纯文件 I/O，
/// 不依赖 Julia 会话，因此在 oneshot 模式下同样可用。
/// rerun_task 需要持久化 Julia 会话，在 oneshot 模式下不可用。
pub fn build_oneshot_router() -> Router {
    let cors = CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE]);

    Router::new()
        .route("/health", get(crate::handlers::oneshot_health_handler))
        .route("/fit_model", post(crate::handlers::oneshot_fit_model_handler))
        .route("/inspect_dataset", post(crate::handlers::oneshot_inspect_handler))
        .route("/query_dataset", post(crate::handlers::oneshot_query_dataset_handler))
        .route("/save_project", post(crate::handlers::save_project_handler))
        .route("/load_project", post(crate::handlers::load_project_handler))
        .route("/list_runs", post(crate::handlers::list_runs_handler))
        .layer(cors)
}

/// 启动 axum 服务器，带优雅关闭信号。
pub async fn serve(bind_addr: &str, session: JuliaSession) -> Result<(), String> {
    let (cmd_tx, julia_healthy) = spawn_julia_actor(session);
    let state = AppState { cmd_tx, julia_healthy };
    let app = build_router(state);

    let listener = tokio::net::TcpListener::bind(bind_addr)
        .await
        .map_err(|err| format!("绑定 {bind_addr} 失败: {err}"))?;

    eprintln!("metrica-runtime HTTP server listening on http://{bind_addr} (axum)");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .map_err(|err| format!("HTTP 服务错误: {err}"))?;

    Ok(())
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c().await.ok();
}

/// 启动 axum 服务器，使用每请求 Julia 子进程模式（oneshot 回退）。
pub async fn serve_oneshot(bind_addr: &str) -> Result<(), String> {
    let app = build_oneshot_router();

    let listener = tokio::net::TcpListener::bind(bind_addr)
        .await
        .map_err(|err| format!("绑定 {bind_addr} 失败: {err}"))?;

    eprintln!(
        "metrica-runtime HTTP server listening on http://{bind_addr} (axum, oneshot fallback)"
    );

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .map_err(|err| format!("HTTP 服务错误: {err}"))?;

    Ok(())
}
