use std::sync::{Arc, Mutex};

use axum::{
    extract::State,
    http::{header, Method, StatusCode},
    response::{IntoResponse, Json},
    routing::{get, post},
    Router,
};
use serde_json::json;
use tower_http::cors::{Any, CorsLayer};

use crate::julia_bridge::execute_fit_model;
use crate::julia_session::JuliaSession;
use crate::{health_summary, repo_root, Message, TaskRequest, TaskResponse};

pub type SharedSession = Arc<Mutex<JuliaSession>>;

/// 构建含所有路由和 CORS 中间件的 axum Router。
pub fn build_router(session: SharedSession) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE]);

    Router::new()
        .route("/health", get(health_handler))
        .route("/fit_model", post(fit_model_handler))
        .route("/inspect_dataset", post(inspect_dataset_handler))
        .layer(cors)
        .with_state(session)
}

/// GET /health — 返回服务状态与 Julia 守护进程健康信息。
async fn health_handler(State(session): State<SharedSession>) -> impl IntoResponse {
    let (julia_healthy, restart_count) = {
        let s = session.lock().unwrap();
        (s.is_healthy(), s.restart_count())
    };

    Json(json!({
        "service": "metrica-runtime",
        "status": if julia_healthy { "ready" } else { "degraded" },
        "julia_healthy": julia_healthy,
        "restart_count": restart_count,
        "supported_actions": ["inspect_dataset", "fit_model"],
    }))
}

/// POST /fit_model — 解析 TaskRequest，解析路径，转发到 Julia 守护进程。
async fn fit_model_handler(
    State(session): State<SharedSession>,
    body: String,
) -> impl IntoResponse {
    handle_model_request(session, body, "fit_model").await
}

/// POST /inspect_dataset — 解析 TaskRequest，解析路径，转发到 Julia 守护进程。
async fn inspect_dataset_handler(
    State(session): State<SharedSession>,
    body: String,
) -> impl IntoResponse {
    handle_model_request(session, body, "inspect_dataset").await
}

/// 共享请求处理逻辑：解析 JSON → 校验 → 解析路径 → 转发 Julia → 返回响应。
async fn handle_model_request(
    session: SharedSession,
    body: String,
    expected_action: &str,
) -> axum::response::Response {
    let request: TaskRequest = match serde_json::from_str(&body) {
        Ok(req) => req,
        Err(err) => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                "unknown".to_string(),
                "RUNTIME_INVALID_JSON",
                format!("请求 JSON 解析失败: {err}"),
                Some("请确认请求体符合 runtime-protocol。".to_string()),
            );
        }
    };

    if request.action != expected_action {
        return json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id,
            "RUNTIME_UNSUPPORTED_ACTION",
            format!(
                "端点 {} 不支持动作 `{}`。",
                expected_action, request.action
            ),
            Some("请使用正确的端点。".to_string()),
        );
    }

    if request.action == "fit_model" && request.model_spec.model_type != "ols" {
        return json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id,
            "RUNTIME_UNSUPPORTED_MODEL_TYPE",
            format!(
                "runtime 当前仅支持 `ols`，收到 `{}`。",
                request.model_spec.model_type
            ),
            Some("请将 model_type 设为 `ols`。".to_string()),
        );
    }

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let dataset_path = resolve_dataset_path(&request.dataset_ref.path, &working_dir);

    let mut params = json!({
        "dataset_path": dataset_path,
        "formula": request.model_spec.formula,
        "model_type": request.model_spec.model_type,
        "vcov": request.model_spec.vcov.kind,
        "weights": request.model_spec.weights,
    });

    if let Some(ref col) = request.model_spec.cluster_column {
        params["cluster_column"] = json!(col);
    }

    let action = expected_action.to_string();
    let result = {
        let session = session.clone();
        tokio::task::spawn_blocking(move || {
            let mut s = session.lock().unwrap();
            s.send_request(&action, params)
        })
        .await
    };

    match result {
        Ok(Ok(julia_response)) => {
            let status = julia_response
                .get("status")
                .and_then(|v| v.as_str())
                .unwrap_or("error")
                .to_string();

            let messages: Vec<Message> = julia_response
                .get("messages")
                .and_then(|v| serde_json::from_value(v.clone()).ok())
                .unwrap_or_default();

            let result_payload = julia_response.get("result_payload").cloned();

            let task_response = TaskResponse {
                task_id: request.task_id,
                status: status.clone(),
                messages,
                artifacts: if status == "success" {
                    Some(vec![])
                } else {
                    None
                },
                result_payload,
            };

            let status_code = if status == "success" {
                StatusCode::OK
            } else {
                StatusCode::OK // 模型级错误仍返回 200，由 status 字段区分
            };

            (
                status_code,
                [("Content-Type", "application/json")],
                serde_json::to_string(&task_response).unwrap_or_default(),
            )
                .into_response()
        }
        Ok(Err(err)) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            request.task_id,
            "RUNTIME_JULIA_EXECUTION_FAILED",
            err,
            Some("请检查 Julia 环境、依赖安装与请求参数。".to_string()),
        ),
        Err(join_err) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            request.task_id,
            "RUNTIME_INTERNAL_ERROR",
            format!("内部运行时错误: {join_err}"),
            Some("请重试或联系管理员。".to_string()),
        ),
    }
}

/// 启动 axum 服务器，带优雅关闭信号。
pub async fn serve(bind_addr: &str, session: JuliaSession) -> Result<(), String> {
    let shared: SharedSession = Arc::new(Mutex::new(session));
    let app = build_router(shared);

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

// === 路径解析（复用现有逻辑） ===================================================

fn resolve_working_dir(raw_working_dir: &str) -> std::path::PathBuf {
    let working_dir = std::path::PathBuf::from(raw_working_dir);
    if working_dir.is_absolute() {
        return working_dir;
    }
    repo_root().join(working_dir)
}

fn resolve_dataset_path(raw_path: &str, working_dir: &std::path::PathBuf) -> String {
    let dataset_path = std::path::PathBuf::from(raw_path);
    if dataset_path.is_absolute() {
        return dataset_path.to_string_lossy().to_string();
    }
    working_dir
        .join(dataset_path)
        .to_string_lossy()
        .to_string()
}

// === 错误响应 ==================================================================

fn json_error_response(
    status: StatusCode,
    task_id: String,
    code: &str,
    text: String,
    hint: Option<String>,
) -> axum::response::Response {
    let response = TaskResponse {
        task_id,
        status: "error".to_string(),
        messages: vec![Message {
            level: "error".to_string(),
            code: code.to_string(),
            text,
            hint,
        }],
        artifacts: None,
        result_payload: None,
    };

    let body = serde_json::to_string(&response).unwrap_or_default();

    (
        status,
        [("Content-Type", "application/json")],
        body,
    )
        .into_response()
}

// === Oneshot 回退模式（每请求 Julia 子进程） =====================================

/// 构建使用每请求 Julia 子进程的 axum Router（`--oneshot` 回退模式）。
pub fn build_oneshot_router() -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE]);

    Router::new()
        .route("/health", get(oneshot_health_handler))
        .route("/fit_model", post(oneshot_fit_model_handler))
        .route("/inspect_dataset", post(oneshot_inspect_handler))
        .layer(cors)
}

async fn oneshot_health_handler() -> impl IntoResponse {
    Json(health_summary())
}

async fn oneshot_fit_model_handler(body: String) -> impl IntoResponse {
    oneshot_handle(body).await
}

async fn oneshot_inspect_handler(body: String) -> impl IntoResponse {
    oneshot_handle(body).await
}

async fn oneshot_handle(body: String) -> axum::response::Response {
    let request: TaskRequest = match serde_json::from_str(&body) {
        Ok(req) => req,
        Err(err) => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                "unknown".to_string(),
                "RUNTIME_INVALID_JSON",
                format!("请求 JSON 解析失败: {err}"),
                Some("请确认请求体符合 runtime-protocol。".to_string()),
            );
        }
    };

    match execute_fit_model(&request) {
        Ok(response) => {
            let status_code = if response.status == "success" {
                StatusCode::OK
            } else {
                StatusCode::OK
            };
            let body = serde_json::to_string(&response).unwrap_or_default();
            (
                status_code,
                [("Content-Type", "application/json")],
                body,
            )
                .into_response()
        }
        Err(err) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            request.task_id,
            "RUNTIME_INTERNAL_ERROR",
            err,
            Some("请重试或联系管理员。".to_string()),
        ),
    }
}

/// 启动 axum 服务器，使用每请求 Julia 子进程模式（oneshot 回退）。
pub async fn serve_oneshot(bind_addr: &str) -> Result<(), String> {
    let app = build_oneshot_router();

    let listener = tokio::net::TcpListener::bind(bind_addr)
        .await
        .map_err(|err| format!("绑定 {bind_addr} 失败: {err}"))?;

    eprintln!("metrica-runtime HTTP server listening on http://{bind_addr} (axum, oneshot fallback)");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .map_err(|err| format!("HTTP 服务错误: {err}"))?;

    Ok(())
}
