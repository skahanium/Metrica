use std::sync::atomic::{AtomicBool, Ordering};

use axum::{
    extract::State,
    http::{header, Method, StatusCode},
    response::{IntoResponse, Json},
    routing::{get, post},
    Router,
};
use serde_json::json;
use tokio::sync::{mpsc, oneshot};
use tower_http::cors::CorsLayer;

use crate::julia_bridge::execute_fit_model;
use crate::julia_session::JuliaSession;
use crate::{
    health_summary, ExportReportRequest, JuliaResponse, ListRunsRequest, LoadProjectRequest, Message,
    ProjectManifest, RerunTaskRequest, RunRecord, SaveProjectRequest, TaskRequest, TaskResponse,
    TransformTaskRequest, ValidationError,
    validate_model_request,
    resolve_working_dir, resolve_dataset_path,
    sanitize_id, safe_runs_path,
    actions,
};

const DEFAULT_BIND_ADDR: &str = "127.0.0.1:47821";

pub fn default_bind_addr() -> &'static str {
    DEFAULT_BIND_ADDR
}

/// Julia 命令通道消息类型：(action, params, reply_sender)。
pub type JuliaCommand = (String, serde_json::Value, oneshot::Sender<Result<serde_json::Value, String>>);

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
        .route("/health", get(health_handler))
        .route("/fit_model", post(fit_model_handler))
        .route("/inspect_dataset", post(inspect_dataset_handler))
        .route("/transform", post(transform_handler))
        .route("/save_project", post(save_project_handler))
        .route("/load_project", post(load_project_handler))
        .route("/list_runs", post(list_runs_handler))
        .route("/rerun_task", post(rerun_task_handler))
        .route("/export_report", post(export_report_handler))
        .layer(cors)
        .with_state(state)
}

/// GET /health — 返回服务状态与 Julia 守护进程健康信息。
///
/// 使用原子状态读取，不阻塞于 Julia 请求锁。
async fn health_handler(State(state): State<AppState>) -> impl IntoResponse {
    let julia_healthy = state.julia_healthy.load(Ordering::Acquire);

    Json(json!({
        "service": "metrica-runtime",
        "status": if julia_healthy { "ready" } else { "degraded" },
        "julia_healthy": julia_healthy,
        "supported_actions": ["inspect_dataset", "fit_model", "transform", "save_project", "load_project", "list_runs", "rerun_task", "export_report"],
    }))
}

/// POST /fit_model — 解析 TaskRequest，解析路径，转发到 Julia 守护进程。
async fn fit_model_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    handle_model_request(state, body, actions::FIT_MODEL).await
}

/// POST /inspect_dataset — 解析 TaskRequest，解析路径，转发到 Julia 守护进程。
async fn inspect_dataset_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    handle_model_request(state, body, actions::INSPECT_DATASET).await
}

// === Transform 辅助函数 =======================================================

/// 解析变换请求的输出路径（若启用 persist_output）。
fn resolve_transform_output_path(
    working_dir: &std::path::Path,
    task_id: &str,
    persist_output: bool,
) -> Result<Option<String>, axum::response::Response> {
    if !persist_output {
        return Ok(None);
    }
    match ensure_transform_output_path(working_dir, task_id) {
        Ok(path) => Ok(Some(path)),
        Err(err) => Err(json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            task_id.to_string(),
            "RUNTIME_TRANSFORM_OUTPUT_PATH_FAILED",
            err,
            Some("请检查项目目录是否可写。".to_string()),
        )),
    }
}

/// POST /transform — 接受数据操作链，转发到 Julia MetricaData 执行。
async fn transform_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    let started_at = current_timestamp_string();
    let request: TransformTaskRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(e) => {
            return json_error_response(
                StatusCode::BAD_REQUEST, "unknown".to_string(), "RUNTIME_INVALID_JSON",
                format!("请求 JSON 解析失败: {e}"),
                Some("请确认 /transform 请求符合 runtime-protocol。".to_string()),
            );
        }
    };

    if request.action != actions::TRANSFORM {
        return json_error_response(
            StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_UNSUPPORTED_ACTION",
            format!("端点 transform 不支持动作 `{}`。", request.action),
            Some("请将 action 设为 `transform`。".to_string()),
        );
    }

    if let Err(err) = sanitize_id(&request.task_id) {
        return json_error_response(
            StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_INVALID_TASK_ID", err, None,
        );
    }

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let dataset_path = resolve_dataset_path(&request.dataset_ref.path, &working_dir);
    let output_path = match resolve_transform_output_path(&working_dir, &request.task_id, request.options.persist_output) {
        Ok(p) => p,
        Err(response) => return response,
    };

    let operations_json = match serde_json::to_string(&request.operations) {
        Ok(json) => json,
        Err(e) => {
            return json_error_response(
                StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_TRANSFORM_SERIALIZE_FAILED",
                format!("数据操作序列化失败: {e}"),
                Some("请检查 operations 是否为结构化数组。".to_string()),
            );
        }
    };

    let params = json!({
        "dataset_path": dataset_path.clone(),
        "operations": operations_json,
        "preview_rows": request.options.preview_rows,
        "persist_output": request.options.persist_output,
        "output_path": output_path.clone(),
    });

    let result = dispatch_via_channel(&state.cmd_tx, actions::TRANSFORM, params).await;

    match result {
        Ok(Ok(julia_response)) => {
            let status = julia_response.get("status").and_then(|v| v.as_str()).unwrap_or("error").to_string();
            let messages: Vec<Message> = julia_response.get("messages").and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default();
            let result_payload = julia_response.get("result_payload").cloned();
            let artifacts = output_path.as_ref().map(|path| vec![path.clone()]).unwrap_or_default();
            let run_record = build_transform_run_record(&request, &dataset_path, &status, &messages, &artifacts, result_payload.as_ref(), &started_at);
            let _ = persist_run_record(&working_dir, &run_record);

            let task_response = TaskResponse {
                task_id: request.task_id, status, messages,
                artifacts: if artifacts.is_empty() { None } else { Some(artifacts.clone()) },
                run_record: serde_json::to_value(&run_record).ok(),
                result_payload,
            };
            (StatusCode::OK, Json(task_response)).into_response()
        }
        Ok(Err(err)) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR, request.task_id, "RUNTIME_JULIA_EXECUTION_FAILED", err,
            Some("请检查 Julia 环境、依赖安装与数据操作参数。".to_string()),
        ),
        Err(send_err) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR, request.task_id, "RUNTIME_INTERNAL_ERROR",
            send_err,
            Some("请重试或联系管理员。".to_string()),
        ),
    }
}

// === 模型请求辅助函数 ==========================================================

/// 从 TaskRequest 构建发送给 Julia 的 params JSON。
fn build_model_params(request: &TaskRequest) -> serde_json::Value {
    let vcov = request.model_spec.vcov.as_ref()
        .map(|spec| spec.kind.as_str())
        .unwrap_or("classical");

    let mut params = json!({
        "dataset_path": "",
        "formula": request.model_spec.formula,
        "model_type": request.model_spec.model_type,
        "vcov": vcov,
        "weights": request.model_spec.weights,
        "return_augment": request.options.return_augment,
        "preview_rows": request.options.preview_rows,
    });

    if let Some(ref col) = request.model_spec.cluster_column { params["cluster_column"] = json!(col); }
    if let Some(ref panel_id) = request.model_spec.panel_id { params["panel_id"] = json!(panel_id); }
    if let Some(ref panel_time) = request.model_spec.panel_time { params["panel_time"] = json!(panel_time); }
    if let Some(ref panel_method) = request.model_spec.panel_method { params["panel_method"] = json!(panel_method); }
    if let Some(ref instruments) = request.model_spec.instruments { params["instruments"] = json!(instruments); }
    if let Some(ref endog_columns) = request.model_spec.endog_columns { params["endog_columns"] = json!(endog_columns); }
    if let Some(ref omega_spec) = request.model_spec.omega_spec { params["omega_spec"] = json!(omega_spec); }

    // S4b: 因果推断字段
    if let Some(ref col) = request.model_spec.treatment_column { params["treatment_column"] = json!(col); }
    if let Some(ref col) = request.model_spec.treated_column { params["treated_column"] = json!(col); }
    if let Some(ref col) = request.model_spec.post_column { params["post_column"] = json!(col); }
    if let Some(ref col) = request.model_spec.event_time_column { params["event_time_column"] = json!(col); }
    if let Some(ref col) = request.model_spec.outcome_column { params["outcome_column"] = json!(col); }

    // S4c: 时间序列字段
    if let Some(ref col) = request.model_spec.time_column { params["time_column"] = json!(col); }
    if let Some(ref col) = request.model_spec.variable { params["variable"] = json!(col); }
    if let Some(ref cols) = request.model_spec.variables { params["variables"] = json!(cols); }
    if let Some(ref order) = request.model_spec.order { params["order"] = json!(order); }
    if let Some(ref order) = request.model_spec.seasonal_order { params["seasonal_order"] = json!(order); }
    if let Some(ref m) = request.model_spec.ts_method { params["ts_method"] = json!(m); }
    if let Some(lags) = request.model_spec.lags { params["lags"] = json!(lags); }
    if let Some(ref det) = request.model_spec.deterministic { params["deterministic"] = json!(det); }

    // S4d: 调查模型字段
    if let Some(ref col) = request.model_spec.weights_column { params["weights_column"] = json!(col); }
    if let Some(ref col) = request.model_spec.strata_column { params["strata_column"] = json!(col); }
    if let Some(ref col) = request.model_spec.psu_column { params["psu_column"] = json!(col); }
    if let Some(ref col) = request.model_spec.fpc_column { params["fpc_column"] = json!(col); }

    params
}

/// 通过命令通道向 Julia 派发请求，返回结果。
async fn dispatch_via_channel(
    cmd_tx: &mpsc::Sender<JuliaCommand>,
    action: &str,
    params: serde_json::Value,
) -> Result<Result<serde_json::Value, String>, String> {
    let (reply_tx, reply_rx) = oneshot::channel();
    cmd_tx
        .send((action.to_string(), params, reply_tx))
        .await
        .map_err(|_| "Julia 命令通道已关闭。".to_string())?;
    reply_rx
        .await
        .map_err(|_| "Julia 响应通道已关闭。".to_string())
}

/// 共享请求处理逻辑：解析 JSON → 校验 → 解析路径 → 转发 Julia → 返回响应。
async fn handle_model_request(
    state: AppState,
    body: String,
    expected_action: &str,
) -> axum::response::Response {
    let started_at = current_timestamp_string();
    let request: TaskRequest = match serde_json::from_str(&body) {
        Ok(req) => req,
        Err(err) => {
            return json_error_response(
                StatusCode::BAD_REQUEST, "unknown".to_string(), "RUNTIME_INVALID_JSON",
                format!("请求 JSON 解析失败: {err}"),
                Some("请确认请求体符合 runtime-protocol。".to_string()),
            );
        }
    };

    if request.action != expected_action {
        return json_error_response(
            StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_UNSUPPORTED_ACTION",
            format!("端点 {} 不支持动作 `{}`。", expected_action, request.action),
            Some("请使用正确的端点。".to_string()),
        );
    }

    if let Err(err) = sanitize_id(&request.task_id) {
        return json_error_response(
            StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_INVALID_TASK_ID", err, None,
        );
    }

    if request.action == actions::FIT_MODEL {
        if let Some(response) = validate_fit_model_request(&request) {
            return response;
        }
    }

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let dataset_path = resolve_dataset_path(&request.dataset_ref.path, &working_dir);

    let mut params = build_model_params(&request);
    params["dataset_path"] = json!(dataset_path.clone());

    let result = dispatch_via_channel(&state.cmd_tx, expected_action, params).await;

    match result {
        Ok(Ok(julia_response)) => {
            let status = julia_response.get("status").and_then(|v| v.as_str()).unwrap_or("error").to_string();
            let messages: Vec<Message> = julia_response.get("messages").and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default();
            let result_payload = julia_response.get("result_payload").cloned();

            let run_record = build_model_run_record(&request, &dataset_path, &status, &messages, &[], result_payload.as_ref(), &started_at);
            let _ = persist_run_record(&working_dir, &run_record);

            let task_response = TaskResponse {
                task_id: request.task_id, status: status.clone(), messages,
                artifacts: if status == "success" { Some(vec![]) } else { None },
                run_record: serde_json::to_value(&run_record).ok(),
                result_payload,
            };

            let status_code = if status == "success" { StatusCode::OK } else { StatusCode::OK };
            (status_code, [("Content-Type", "application/json")], serde_json::to_string(&task_response).unwrap_or_default()).into_response()
        }
        Ok(Err(err)) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR, request.task_id, "RUNTIME_JULIA_EXECUTION_FAILED", err,
            Some("请检查 Julia 环境、依赖安装与请求参数。".to_string()),
        ),
        Err(send_err) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR, request.task_id, "RUNTIME_INTERNAL_ERROR",
            send_err,
            Some("请重试或联系管理员。".to_string()),
        ),
    }
}

async fn save_project_handler(body: String) -> impl IntoResponse {
    let request: SaveProjectRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(err) => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                "unknown".to_string(),
                "RUNTIME_INVALID_JSON",
                format!("请求 JSON 解析失败: {err}"),
                Some("请确认 /save_project 请求符合协议。".to_string()),
            );
        }
    };

    // 校验 manifest 关键字段
    if request.manifest.project_id.trim().is_empty() {
        return json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id,
            "RUNTIME_MANIFEST_INVALID",
            "project_id 不能为空。".to_string(),
            Some("请提供有效的 project_id。".to_string()),
        );
    }
    if request.manifest.source_dataset.trim().is_empty() {
        return json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id,
            "RUNTIME_MANIFEST_INVALID",
            "source_dataset 不能为空。".to_string(),
            Some("请提供源数据集路径。".to_string()),
        );
    }
    if request.manifest.version < 1 {
        return json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id,
            "RUNTIME_MANIFEST_INVALID",
            "version 必须 >= 1。".to_string(),
            Some("请设置有效的版本号。".to_string()),
        );
    }

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let project_path = project_manifest_path(&working_dir);
    if let Err(err) = ensure_metrica_dir(&working_dir) {
        return json_error_response(StatusCode::INTERNAL_SERVER_ERROR, request.task_id, "RUNTIME_PROJECT_DIR_FAILED", err, None);
    }
    if let Err(err) = write_json_file(&project_path, &request.manifest) {
        return json_error_response(StatusCode::INTERNAL_SERVER_ERROR, request.task_id, "RUNTIME_SAVE_PROJECT_FAILED", err, None);
    }

    let response = TaskResponse {
        task_id: request.task_id,
        status: "success".to_string(),
        messages: vec![],
        artifacts: Some(vec![project_path.to_string_lossy().to_string()]),
        run_record: None,
        result_payload: Some(json!({
            "project_path": project_path.to_string_lossy().to_string(),
            "manifest": request.manifest,
        })),
    };

    (StatusCode::OK, Json(response)).into_response()
}

async fn load_project_handler(body: String) -> impl IntoResponse {
    let request: LoadProjectRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(err) => {
            return json_error_response(StatusCode::BAD_REQUEST, "unknown".to_string(), "RUNTIME_INVALID_JSON", format!("请求 JSON 解析失败: {err}"), None);
        }
    };
    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let project_path = project_manifest_path(&working_dir);
    let manifest: ProjectManifest = match read_json_file(&project_path) {
        Ok(v) => v,
        Err(err) => {
            return json_error_response(StatusCode::NOT_FOUND, request.task_id, "RUNTIME_PROJECT_NOT_FOUND", err, Some("请先保存项目。".to_string()));
        }
    };

    let response = TaskResponse {
        task_id: request.task_id,
        status: "success".to_string(),
        messages: vec![],
        artifacts: Some(vec![project_path.to_string_lossy().to_string()]),
        run_record: None,
        result_payload: Some(json!({
            "project_path": project_path.to_string_lossy().to_string(),
            "manifest": manifest,
        })),
    };
    (StatusCode::OK, Json(response)).into_response()
}

async fn list_runs_handler(body: String) -> impl IntoResponse {
    let request: ListRunsRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(err) => {
            return json_error_response(StatusCode::BAD_REQUEST, "unknown".to_string(), "RUNTIME_INVALID_JSON", format!("请求 JSON 解析失败: {err}"), None);
        }
    };
    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let mut runs = list_run_records(&working_dir).unwrap_or_default();

    // 按 action 过滤
    if let Some(ref action) = request.action_filter {
        runs.retain(|r| r.action == *action);
    }
    // 按 status 过滤
    if let Some(ref status) = request.status_filter {
        runs.retain(|r| r.status == *status);
    }

    let total = runs.len();
    let offset = request.offset.unwrap_or(0);
    let limit = request.limit.unwrap_or(total);
    let runs = runs.into_iter().skip(offset).take(limit).collect::<Vec<_>>();

    let response = TaskResponse {
        task_id: request.task_id,
        status: "success".to_string(),
        messages: vec![],
        artifacts: None,
        run_record: None,
        result_payload: Some(json!({ "runs": runs, "total": total })),
    };
    (StatusCode::OK, Json(response)).into_response()
}

async fn rerun_task_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    let request: RerunTaskRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(err) => {
            return json_error_response(StatusCode::BAD_REQUEST, "unknown".to_string(), "RUNTIME_INVALID_JSON", format!("请求 JSON 解析失败: {err}"), None);
        }
    };
    if let Err(err) = sanitize_id(&request.run_id) {
        return json_error_response(StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_INVALID_RUN_ID", err, None);
    }
    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let run_path = match safe_runs_path(&working_dir, &request.run_id) {
        Ok(p) => p,
        Err(err) => {
            return json_error_response(StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_INVALID_RUN_ID", err, None);
        }
    };
    let run_record: RunRecord = match read_json_file(&run_path) {
        Ok(v) => v,
        Err(err) => {
            return json_error_response(StatusCode::NOT_FOUND, request.task_id, "RUNTIME_RUN_NOT_FOUND", err, Some("请确认 run_id 是否存在。".to_string()));
        }
    };

    let dataset_path = resolve_dataset_path(&run_record.dataset_ref.path, &working_dir);
    if !std::path::Path::new(&dataset_path).exists() {
        return json_error_response(StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_RERUN_DATASET_MISSING", format!("重跑所需数据集不存在：{dataset_path}"), Some("请恢复数据文件后再重跑。".to_string()));
    }

    let new_run_id = format!("rerun-{}", current_timestamp_string());

    let action = run_record.action.clone();
    let payload = run_record.request_payload.clone();
    let response = if action == actions::TRANSFORM {
        let original_request: TransformTaskRequest = match serde_json::from_value(payload) {
            Ok(v) => v,
            Err(err) => {
                return json_error_response(StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_RERUN_REQUEST_INVALID", format!("历史请求载荷无法解析：{err}"), None);
            }
        };
        let body = match serde_json::to_string(&TransformTaskRequest { task_id: new_run_id, ..original_request }) {
            Ok(v) => v,
            Err(err) => {
                return json_error_response(StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_RERUN_REQUEST_INVALID", format!("历史请求重建失败：{err}"), None);
            }
        };
        transform_handler(State(state), body).await.into_response()
    } else {
        let original_request: TaskRequest = match serde_json::from_value(payload) {
            Ok(v) => v,
            Err(err) => {
                return json_error_response(StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_RERUN_REQUEST_INVALID", format!("历史请求载荷无法解析：{err}"), None);
            }
        };
        let body = match serde_json::to_string(&TaskRequest { task_id: new_run_id, ..original_request }) {
            Ok(v) => v,
            Err(err) => {
                return json_error_response(StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_RERUN_REQUEST_INVALID", format!("历史请求重建失败：{err}"), None);
            }
        };
        handle_model_request(state, body, &action).await
    };
    response
}

/// 通过命令通道向 Julia 发送导出请求并提取 content 字段。
async fn dispatch_export_via_channel(
    cmd_tx: &mpsc::Sender<JuliaCommand>,
    task_id: &str,
    params: serde_json::Value,
) -> Result<String, axum::response::Response> {
    let result = dispatch_via_channel(cmd_tx, actions::EXPORT_REPORT, params).await;

    match result {
        Ok(Ok(resp)) => {
            let jr: JuliaResponse = serde_json::from_value(resp).unwrap_or(JuliaResponse {
                status: "error".to_string(),
                messages: vec![],
                result_payload: None,
            });
            Ok(jr.content().to_string())
        }
        Ok(Err(err)) => Err(json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            task_id.to_string(),
            "RUNTIME_EXPORT_FAILED",
            format!("Julia 导出失败: {err}"),
            None,
        )),
        Err(send_err) => Err(json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            task_id.to_string(),
            "RUNTIME_INTERNAL_ERROR",
            send_err,
            None,
        )),
    }
}

async fn export_report_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    let request: ExportReportRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(err) => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                "unknown".to_string(),
                "RUNTIME_INVALID_JSON",
                format!("请求 JSON 解析失败: {err}"),
                None,
            );
        }
    };

    if let Err(err) = sanitize_id(&request.run_id) {
        return json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id,
            "RUNTIME_INVALID_RUN_ID",
            err,
            None,
        );
    }

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let run_path = match safe_runs_path(&working_dir, &request.run_id) {
        Ok(p) => p,
        Err(err) => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                request.task_id,
                "RUNTIME_INVALID_RUN_ID",
                err,
                None,
            );
        }
    };
    let run_record: RunRecord = match read_json_file(&run_path) {
        Ok(v) => v,
        Err(err) => {
            return json_error_response(
                StatusCode::NOT_FOUND,
                request.task_id,
                "RUNTIME_RUN_NOT_FOUND",
                err,
                Some("请确认 run_id 是否存在。".to_string()),
            );
        }
    };

    let result_summary = match run_record.result_summary {
        Some(ref v) => v.clone(),
        None => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                request.task_id,
                "RUNTIME_NO_RESULT_SUMMARY",
                "该运行记录没有结果摘要，无法导出报告。".to_string(),
                Some("请确保运行成功后再导出。".to_string()),
            );
        }
    };

    // 构建导出参数
    let params = match request.format.as_str() {
        "markdown" => {
            let run_record_dict = serde_json::to_value(&run_record)
                .and_then(|v| serde_json::from_value::<serde_json::Value>(v))
                .unwrap_or(serde_json::Value::Object(serde_json::Map::new()));
            json!({ "run_record": run_record_dict, "result": result_summary })
        }
        "csv_tidy" | "csv_glance" | "csv_diagnostics" => {
            json!({ "format": request.format, "result": result_summary })
        }
        _ => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                request.task_id,
                "RUNTIME_UNSUPPORTED_FORMAT",
                format!("不支持的导出格式: {}", request.format),
                Some("支持的格式: markdown, csv_tidy, csv_glance, csv_diagnostics".to_string()),
            );
        }
    };

    let content = match dispatch_export_via_channel(&state.cmd_tx, &request.task_id, params).await {
        Ok(c) => c,
        Err(response) => return response,
    };

    let response = TaskResponse {
        task_id: request.task_id,
        status: "success".to_string(),
        messages: vec![],
        artifacts: None,
        run_record: None,
        result_payload: Some(json!({
            "content": content,
            "format": request.format,
            "run_id": request.run_id,
        })),
    };

    (StatusCode::OK, Json(response)).into_response()
}

/// 启动 Julia actor 并返回命令发送端和健康标志。
///
/// Actor 在独立 OS 线程中串行处理 Julia 请求，
/// HTTP handler 通过 channel 发送命令，不持有任何 Mutex。
pub fn spawn_julia_actor(session: JuliaSession) -> (mpsc::Sender<JuliaCommand>, std::sync::Arc<AtomicBool>) {
    let julia_healthy = std::sync::Arc::new(AtomicBool::new(session.is_healthy()));
    let healthy_flag = julia_healthy.clone();
    let (cmd_tx, mut cmd_rx) = mpsc::channel::<JuliaCommand>(64);

    // 专用 OS 线程：持有 JuliaSession，串行处理请求。
    // send_request 是阻塞 I/O，在此线程执行不会阻塞 tokio 运行时。
    std::thread::spawn(move || {
        let mut session = session;
        loop {
            match cmd_rx.blocking_recv() {
                Some((action, params, reply_tx)) => {
                    let result = session.send_request(&action, params);
                    healthy_flag.store(result.is_ok(), Ordering::Release);
                    let _ = reply_tx.send(result);
                }
                None => break, // 所有 sender 已 drop，actor 退出
            }
        }
    });

    (cmd_tx, julia_healthy)
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

// === 路径解析 ================================================================

// resolve_working_dir 与 resolve_dataset_path 已由 lib.rs 提供（通过 crate import 引用）

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

fn current_timestamp_string() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis().to_string())
        .unwrap_or_else(|_| "0".to_string())
}

fn metrica_dir(working_dir: &std::path::Path) -> std::path::PathBuf {
    working_dir.join(".metrica")
}

fn runs_dir(working_dir: &std::path::Path) -> std::path::PathBuf {
    metrica_dir(working_dir).join("runs")
}

fn project_manifest_path(working_dir: &std::path::Path) -> std::path::PathBuf {
    metrica_dir(working_dir).join("project.json")
}

fn ensure_metrica_dir(working_dir: &std::path::Path) -> Result<(), String> {
    std::fs::create_dir_all(runs_dir(working_dir))
        .map_err(|err| format!("创建 .metrica 目录失败（{}）：{err}", metrica_dir(working_dir).display()))
}

fn write_json_file<T: serde::Serialize>(path: &std::path::Path, value: &T) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|err| format!("创建目录失败（{}）：{err}", parent.display()))?;
    }
    let body = serde_json::to_string_pretty(value)
        .map_err(|err| format!("JSON 序列化失败：{err}"))?;
    std::fs::write(path, body).map_err(|err| format!("写入文件失败（{}）：{err}", path.display()))
}

fn read_json_file<T: serde::de::DeserializeOwned>(path: &std::path::Path) -> Result<T, String> {
    let body = std::fs::read_to_string(path)
        .map_err(|err| format!("读取文件失败（{}）：{err}", path.display()))?;
    serde_json::from_str(&body).map_err(|err| format!("JSON 解析失败（{}）：{err}", path.display()))
}

fn list_run_records(working_dir: &std::path::Path) -> Result<Vec<RunRecord>, String> {
    let dir = runs_dir(working_dir);
    if !dir.exists() {
        return Ok(vec![]);
    }
    let mut runs = vec![];
    let entries = std::fs::read_dir(&dir)
        .map_err(|err| format!("读取运行记录目录失败（{}）：{err}", dir.display()))?;
    for entry in entries {
        let path = match entry {
            Ok(v) => v.path(),
            Err(_) => continue,
        };
        if path.extension().and_then(|v| v.to_str()) != Some("json") {
            continue;
        }
        if let Ok(run) = read_json_file::<RunRecord>(&path) {
            runs.push(run);
        }
    }
    runs.sort_by(|a, b| b.finished_at.cmp(&a.finished_at));
    Ok(runs)
}

fn summarize_model_payload(action: &str, payload: &serde_json::Value) -> serde_json::Value {
    if action == actions::FIT_MODEL {
        return json!({
            "glance": payload.get("glance").cloned().unwrap_or(serde_json::Value::Null),
            "tidy": payload.get("tidy").cloned().unwrap_or(serde_json::Value::Null),
            "diagnostics": payload.get("diagnostics").cloned().unwrap_or(serde_json::Value::Null),
            "warnings": payload.get("warnings").cloned().unwrap_or(serde_json::Value::Array(vec![])),
            "vcov_label": payload.get("vcov_label").cloned().unwrap_or(serde_json::Value::Null),
        });
    }
    payload.clone()
}

fn build_model_run_record(
    request: &TaskRequest,
    dataset_path: &str,
    status: &str,
    messages: &[Message],
    artifacts: &[String],
    result_payload: Option<&serde_json::Value>,
    started_at: &str,
) -> RunRecord {
    let warnings = result_payload
        .and_then(|payload| payload.get("warnings"))
        .and_then(|value| value.as_array())
        .cloned()
        .unwrap_or_default();

    RunRecord {
        run_id: request.task_id.clone(),
        action: request.action.clone(),
        started_at: started_at.to_string(),
        finished_at: current_timestamp_string(),
        status: status.to_string(),
        dataset_ref: crate::DatasetRef {
            source: request.dataset_ref.source.clone(),
            path: dataset_path.to_string(),
            format: request.dataset_ref.format.clone(),
        },
        model_spec: Some(request.model_spec.clone()),
        operations: None,
        warnings,
        messages: messages.to_vec(),
        artifacts: artifacts.to_vec(),
        result_summary: result_payload.map(|payload| summarize_model_payload(&request.action, payload)),
        request_payload: serde_json::to_value(request).unwrap_or(serde_json::Value::Null),
    }
}

fn build_transform_run_record(
    request: &TransformTaskRequest,
    dataset_path: &str,
    status: &str,
    messages: &[Message],
    artifacts: &[String],
    result_payload: Option<&serde_json::Value>,
    started_at: &str,
) -> RunRecord {
    let notes = result_payload
        .and_then(|payload| payload.get("warnings"))
        .and_then(|value| value.as_array())
        .cloned()
        .unwrap_or_default();
    RunRecord {
        run_id: request.task_id.clone(),
        action: request.action.clone(),
        started_at: started_at.to_string(),
        finished_at: current_timestamp_string(),
        status: status.to_string(),
        dataset_ref: crate::DatasetRef {
            source: request.dataset_ref.source.clone(),
            path: dataset_path.to_string(),
            format: request.dataset_ref.format.clone(),
        },
        model_spec: None,
        operations: Some(request.operations.clone()),
        warnings: notes,
        messages: messages.to_vec(),
        artifacts: artifacts.to_vec(),
        result_summary: result_payload.cloned(),
        request_payload: serde_json::to_value(request).unwrap_or(serde_json::Value::Null),
    }
}

fn persist_run_record(working_dir: &std::path::Path, run_record: &RunRecord) -> Result<(), String> {
    let sanitized_id = sanitize_id(&run_record.run_id)?;
    ensure_metrica_dir(working_dir)?;
    let path = runs_dir(working_dir).join(format!("{}.json", sanitized_id));
    write_json_file(&path, run_record)
}

// === 模型校验（委托给 lib.rs 共享实现） ========================================

fn validation_error_to_response(err: &ValidationError, task_id: &str) -> axum::response::Response {
    json_error_response(
        StatusCode::BAD_REQUEST,
        task_id.to_string(),
        err.code,
        err.message.clone(),
        err.hint.clone(),
    )
}

fn validate_fit_model_request(request: &TaskRequest) -> Option<axum::response::Response> {
    validate_model_request(&request.model_spec)
        .map(|err| validation_error_to_response(&err, &request.task_id))
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
        run_record: None,
        result_payload: None,
    };

    let body = serde_json::to_string(&response).unwrap_or_default();

    (status, [("Content-Type", "application/json")], body).into_response()
}

// === Oneshot 回退模式（每请求 Julia 子进程） =====================================

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
        .route("/health", get(oneshot_health_handler))
        .route("/fit_model", post(oneshot_fit_model_handler))
        .route("/inspect_dataset", post(oneshot_inspect_handler))
        .route("/save_project", post(save_project_handler))
        .route("/load_project", post(load_project_handler))
        .route("/list_runs", post(list_runs_handler))
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
