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
use crate::{
    health_summary, repo_root, Message, TaskRequest, TaskResponse, TransformTaskRequest,
};

const DEFAULT_BIND_ADDR: &str = "127.0.0.1:47821";

pub fn default_bind_addr() -> &'static str {
    DEFAULT_BIND_ADDR
}

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
        .route("/transform", post(transform_handler))
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
        "supported_actions": ["inspect_dataset", "fit_model", "transform"],
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

/// POST /transform — 接受数据操作链，转发到 Julia MetricaData 执行。
async fn transform_handler(
    State(session): State<SharedSession>,
    body: String,
) -> impl IntoResponse {
    let request: TransformTaskRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(e) => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                "unknown".to_string(),
                "RUNTIME_INVALID_JSON",
                format!("请求 JSON 解析失败: {e}"),
                Some("请确认 /transform 请求符合 runtime-protocol。".to_string()),
            );
        }
    };

    if request.action != "transform" {
        return json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id,
            "RUNTIME_UNSUPPORTED_ACTION",
            format!("端点 transform 不支持动作 `{}`。", request.action),
            Some("请将 action 设为 `transform`。".to_string()),
        );
    }

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let dataset_path = resolve_dataset_path(&request.dataset_ref.path, &working_dir);
    let output_path = if request.options.persist_output {
        match ensure_transform_output_path(&working_dir, &request.task_id) {
            Ok(path) => Some(path),
            Err(err) => {
                return json_error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    request.task_id,
                    "RUNTIME_TRANSFORM_OUTPUT_PATH_FAILED",
                    err,
                    Some("请检查项目目录是否可写。".to_string()),
                );
            }
        }
    } else {
        None
    };

    let operations_json = match serde_json::to_string(&request.operations) {
        Ok(json) => json,
        Err(e) => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                request.task_id,
                "RUNTIME_TRANSFORM_SERIALIZE_FAILED",
                format!("数据操作序列化失败: {e}"),
                Some("请检查 operations 是否为结构化数组。".to_string()),
            );
        }
    };

    let params = json!({
        "dataset_path": dataset_path,
        "operations": operations_json,
        "preview_rows": request.options.preview_rows,
        "persist_output": request.options.persist_output,
        "output_path": output_path,
    });

    let result = {
        let session = session.clone();
        tokio::task::spawn_blocking(move || {
            let mut s = session.lock().unwrap();
            s.send_request("transform", params)
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
                status,
                messages,
                artifacts: None,
                result_payload,
            };

            (StatusCode::OK, Json(task_response)).into_response()
        }
        Ok(Err(err)) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            request.task_id,
            "RUNTIME_JULIA_EXECUTION_FAILED",
            err,
            Some("请检查 Julia 环境、依赖安装与数据操作参数。".to_string()),
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
            format!("端点 {} 不支持动作 `{}`。", expected_action, request.action),
            Some("请使用正确的端点。".to_string()),
        );
    }

    if request.action == "fit_model" {
        if let Some(response) = validate_fit_model_request(&request) {
            return response;
        }
    }

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let dataset_path = resolve_dataset_path(&request.dataset_ref.path, &working_dir);

    let vcov = request
        .model_spec
        .vcov
        .as_ref()
        .map(|spec| spec.kind.as_str())
        .unwrap_or("classical");

    let mut params = json!({
        "dataset_path": dataset_path,
        "formula": request.model_spec.formula,
        "model_type": request.model_spec.model_type,
        "vcov": vcov,
        "weights": request.model_spec.weights,
        "return_augment": request.options.return_augment,
    });

    if let Some(ref col) = request.model_spec.cluster_column {
        params["cluster_column"] = json!(col);
    }
    if let Some(ref panel_id) = request.model_spec.panel_id {
        params["panel_id"] = json!(panel_id);
    }
    if let Some(ref panel_time) = request.model_spec.panel_time {
        params["panel_time"] = json!(panel_time);
    }
    if let Some(ref panel_method) = request.model_spec.panel_method {
        params["panel_method"] = json!(panel_method);
    }

    if let Some(ref instruments) = request.model_spec.instruments {
        params["instruments"] = json!(instruments);
    }
    if let Some(ref endog_columns) = request.model_spec.endog_columns {
        params["endog_columns"] = json!(endog_columns);
    }
    if let Some(ref omega_spec) = request.model_spec.omega_spec {
        params["omega_spec"] = json!(omega_spec);
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
    working_dir.join(dataset_path).to_string_lossy().to_string()
}

fn ensure_transform_output_path(
    working_dir: &std::path::Path,
    task_id: &str,
) -> Result<String, String> {
    let safe_task_id = task_id
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' { ch } else { '_' })
        .collect::<String>();
    let derived_dir = working_dir.join(".metrica").join("derived");
    std::fs::create_dir_all(&derived_dir)
        .map_err(|err| format!("创建派生数据目录失败（{}）：{err}", derived_dir.display()))?;
    Ok(derived_dir
        .join(format!("{safe_task_id}.csv"))
        .to_string_lossy()
        .to_string())
}

fn validate_fit_model_request(request: &TaskRequest) -> Option<axum::response::Response> {
    match request.model_spec.model_type.as_str() {
        "ols" => None,
        "panel" => validate_panel_request(request),
        "iv" => validate_iv_request(request),
        "gls" => None,
        model_type => Some(json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id.clone(),
            "RUNTIME_UNSUPPORTED_MODEL_TYPE",
            format!("runtime 当前支持 `ols`、`panel`、`iv` 与 `gls`，收到 `{model_type}`。"),
            Some("请将 model_type 设为 `ols`、`panel`、`iv` 或 `gls`。".to_string()),
        )),
    }
}

fn validate_panel_request(request: &TaskRequest) -> Option<axum::response::Response> {
    let missing_fields = [
        ("panel_id", request.model_spec.panel_id.as_deref()),
        ("panel_time", request.model_spec.panel_time.as_deref()),
    ]
    .iter()
    .filter_map(|(field, value)| match value {
        Some(value) if !value.trim().is_empty() => None,
        _ => Some(*field),
    })
    .collect::<Vec<_>>();

    if missing_fields.is_empty() {
        return None;
    }

    Some(json_error_response(
        StatusCode::BAD_REQUEST,
        request.task_id.clone(),
        "RUNTIME_PANEL_INDEX_REQUIRED",
        format!("面板模型缺少必要索引字段：{}。", missing_fields.join(", ")),
        Some("请提供 panel_id 与 panel_time，以便 Runtime 将请求转发给面板估计器。".to_string()),
    ))
}

fn validate_iv_request(request: &TaskRequest) -> Option<axum::response::Response> {
    let missing = [
        ("instruments", request.model_spec.instruments.as_ref().map(|v| v.is_empty()).unwrap_or(true)),
        ("endog_columns", request.model_spec.endog_columns.as_ref().map(|v| v.is_empty()).unwrap_or(true)),
    ]
    .iter()
    .filter_map(|(f, empty)| if *empty { Some(*f) } else { None })
    .collect::<Vec<_>>();

    if missing.is_empty() { return None; }

    Some(json_error_response(
        StatusCode::BAD_REQUEST, request.task_id.clone(), "RUNTIME_IV_FIELDS_REQUIRED",
        format!("IV 模型缺少必要字段：{}。", missing.join(", ")),
        Some("请提供 instruments 和 endog_columns。".to_string()),
    ))
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

    (status, [("Content-Type", "application/json")], body).into_response()
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
            (status_code, [("Content-Type", "application/json")], body).into_response()
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

    eprintln!(
        "metrica-runtime HTTP server listening on http://{bind_addr} (axum, oneshot fallback)"
    );

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .map_err(|err| format!("HTTP 服务错误: {err}"))?;

    Ok(())
}
