use std::sync::atomic::Ordering;

use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde_json::json;
use tokio::sync::mpsc;

use crate::julia_actor::dispatch_via_channel;
use crate::julia_bridge::{execute_fit_model, execute_query_dataset};
use crate::persistence;
use crate::types::{actions, JuliaCommand, JuliaResponse, Message, TaskResponse, ValidationError};
use crate::types::{
    DataCommandRequest, DiagnosticRequest, ExportReportRequest,
    ListRunsRequest, LoadProjectRequest, ProjectManifest, RerunTaskRequest, RunRecord,
    SaveProjectRequest, TaskRequest, TransformTaskRequest,
};
use crate::{
    health_summary, resolve_dataset_path, resolve_working_dir, safe_runs_path, sanitize_id,
    validate_model_request, validate_spatial_weights_on_disk, ValidatedModelParams,
};

use crate::server::AppState;

// === Handler 函数 ===============================================================

pub(crate) async fn health_handler(State(state): State<AppState>) -> impl IntoResponse {
    let julia_healthy = state.julia_healthy.load(Ordering::Acquire);

    Json(json!({
        "service": "metrica-runtime",
        "status": if julia_healthy { "ready" } else { "degraded" },
        "julia_healthy": julia_healthy,
        "supported_actions": [
            "inspect_dataset", "query_dataset", "fit_model", "transform",
            "run_diagnostic", "save_project", "load_project", "list_runs",
            "rerun_task", "export_report",
        ],
    }))
}

pub(crate) async fn fit_model_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    handle_model_request(state, body, actions::FIT_MODEL).await
}

pub(crate) async fn inspect_dataset_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    handle_model_request(state, body, actions::INSPECT_DATASET).await
}

pub(crate) async fn run_diagnostic_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    let request: DiagnosticRequest = match serde_json::from_str(&body) {
        Ok(req) => req,
        Err(err) => {
            return json_error_response(
                StatusCode::BAD_REQUEST, "unknown".to_string(), "RUNTIME_INVALID_JSON",
                format!("诊断请求 JSON 解析失败: {err}"),
                Some("请确认请求体包含 model_spec 和 diagnostic 字段。".to_string()),
            );
        }
    };

    if let Err(err) = sanitize_id(&request.task_id) {
        return json_error_response(
            StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_INVALID_TASK_ID", err, None,
        );
    }

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let dataset_path = resolve_dataset_path(&request.dataset_ref.path, &working_dir);

    let vcov = request.model_spec.vcov.as_ref()
        .map(|spec| spec.kind.as_str())
        .unwrap_or("classical");

    let params = json!({
        "dataset_path": dataset_path,
        "formula": request.model_spec.formula,
        "model_type": request.model_spec.model_type,
        "vcov": vcov,
        "test": request.diagnostic.test,
        "lags": request.diagnostic.lags,
    });

    let result = dispatch_via_channel(&state.cmd_tx, actions::RUN_DIAGNOSTIC, params).await;

    match result {
        Ok(Ok(julia_response)) => {
            let status = julia_response.get("status").and_then(|v| v.as_str()).unwrap_or("error").to_string();
            let messages: Vec<Message> = julia_response.get("messages").and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default();
            let result_payload = julia_response.get("result_payload").cloned();

            let task_response = TaskResponse {
                task_id: request.task_id, status: status.clone(), messages,
                artifacts: if status == "success" { Some(vec![]) } else { None },
                run_record: None,
                result_payload,
            };

            (StatusCode::OK, [("Content-Type", "application/json")], serde_json::to_string(&task_response).unwrap_or_default()).into_response()
        }
        Ok(Err(err)) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR, request.task_id, "RUNTIME_JULIA_EXECUTION_FAILED", err,
            Some("请检查 Julia 环境与请求参数。".to_string()),
        ),
        Err(send_err) => json_error_response(
            StatusCode::INTERNAL_SERVER_ERROR, request.task_id, "RUNTIME_INTERNAL_ERROR",
            send_err,
            Some("请重试或联系管理员。".to_string()),
        ),
    }
}

pub(crate) async fn query_dataset_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    handle_query_dataset_request(state, body).await
}

pub(crate) async fn transform_handler(
    State(state): State<AppState>,
    body: String,
) -> impl IntoResponse {
    let started_at = persistence::current_timestamp_string();
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
            let run_record = persistence::build_transform_run_record(&request, &dataset_path, &status, &messages, &artifacts, result_payload.as_ref(), &started_at);
            let _ = persistence::persist_run_record(&working_dir, &run_record);

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

pub(crate) async fn save_project_handler(body: String) -> impl IntoResponse {
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
    let project_path = persistence::project_manifest_path(&working_dir);
    if let Err(err) = persistence::ensure_metrica_dir(&working_dir) {
        return json_error_response(StatusCode::INTERNAL_SERVER_ERROR, request.task_id, "RUNTIME_PROJECT_DIR_FAILED", err, None);
    }
    if let Err(err) = persistence::write_json_file(&project_path, &request.manifest) {
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

pub(crate) async fn load_project_handler(body: String) -> impl IntoResponse {
    let request: LoadProjectRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(err) => {
            return json_error_response(StatusCode::BAD_REQUEST, "unknown".to_string(), "RUNTIME_INVALID_JSON", format!("请求 JSON 解析失败: {err}"), None);
        }
    };
    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let project_path = persistence::project_manifest_path(&working_dir);
    let manifest: ProjectManifest = match persistence::read_json_file(&project_path) {
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

pub(crate) async fn list_runs_handler(body: String) -> impl IntoResponse {
    let request: ListRunsRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(err) => {
            return json_error_response(StatusCode::BAD_REQUEST, "unknown".to_string(), "RUNTIME_INVALID_JSON", format!("请求 JSON 解析失败: {err}"), None);
        }
    };
    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let mut runs = persistence::list_run_records(&working_dir).unwrap_or_default();

    if let Some(ref action) = request.action_filter {
        runs.retain(|r| r.action == *action);
    }
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

pub(crate) async fn rerun_task_handler(
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
    let run_record: RunRecord = match persistence::read_json_file(&run_path) {
        Ok(v) => v,
        Err(err) => {
            return json_error_response(StatusCode::NOT_FOUND, request.task_id, "RUNTIME_RUN_NOT_FOUND", err, Some("请确认 run_id 是否存在。".to_string()));
        }
    };

    let dataset_path = resolve_dataset_path(&run_record.dataset_ref.path, &working_dir);
    if !std::path::Path::new(&dataset_path).exists() {
        return json_error_response(StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_RERUN_DATASET_MISSING", format!("重跑所需数据集不存在：{dataset_path}"), Some("请恢复数据文件后再重跑。".to_string()));
    }

    let new_run_id = format!("rerun-{}", persistence::current_timestamp_string());

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

async fn dispatch_export_via_channel(
    cmd_tx: &mpsc::Sender<JuliaCommand>,
    task_id: &str,
    params: serde_json::Value,
) -> Result<String, axum::response::Response> {
    let result = dispatch_via_channel(cmd_tx, actions::EXPORT_REPORT, params).await;

    match result {
        Ok(Ok(resp)) => {
            let status = resp
                .get("status")
                .and_then(|value| value.as_str())
                .unwrap_or("error");
            if status != "success" {
                let messages: Vec<Message> = resp
                    .get("messages")
                    .and_then(|value| serde_json::from_value(value.clone()).ok())
                    .unwrap_or_default();
                let text = messages
                    .first()
                    .map(|m| m.text.clone())
                    .unwrap_or_else(|| "Julia 导出返回错误状态。".to_string());
                return Err(json_error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
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

pub(crate) async fn export_report_handler(
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
    let run_record: RunRecord = match persistence::read_json_file(&run_path) {
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

    let params = match request.format.as_str() {
        "markdown" => {
            let run_record_dict = serde_json::to_value(&run_record)
                .and_then(serde_json::from_value::<serde_json::Value>)
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

// === Oneshot 模式 handler =======================================================

pub(crate) async fn oneshot_health_handler() -> impl IntoResponse {
    Json(health_summary())
}

pub(crate) async fn oneshot_fit_model_handler(body: String) -> impl IntoResponse {
    oneshot_handle(body).await
}

pub(crate) async fn oneshot_inspect_handler(body: String) -> impl IntoResponse {
    oneshot_handle(body).await
}

pub(crate) async fn oneshot_query_dataset_handler(body: String) -> impl IntoResponse {
    let request: DataCommandRequest = match serde_json::from_str(&body) {
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

    match execute_query_dataset(&request) {
        Ok(response) => {
            let body = serde_json::to_string(&response).unwrap_or_default();
            (StatusCode::OK, [("Content-Type", "application/json")], body).into_response()
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
            let body = serde_json::to_string(&response).unwrap_or_default();
            (StatusCode::OK, [("Content-Type", "application/json")], body).into_response()
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

// === 共享请求处理 ===============================================================

async fn handle_model_request(
    state: AppState,
    body: String,
    expected_action: &str,
) -> axum::response::Response {
    let started_at = persistence::current_timestamp_string();
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

    let validated = if request.action == actions::FIT_MODEL {
        match validate_fit_model_request(&request) {
            Ok(v) => Some(v),
            Err(resp) => return resp,
        }
    } else {
        None
    };

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let dataset_path = resolve_dataset_path(&request.dataset_ref.path, &working_dir);

    let mut params = if let Some(ref validated) = validated {
        build_model_params(&request, validated)
    } else {
        build_model_params_inspect(&request)
    };
    params["dataset_path"] = json!(dataset_path.clone());
    params["working_dir"] = json!(working_dir.to_string_lossy().to_string());

    let result = dispatch_via_channel(&state.cmd_tx, expected_action, params).await;

    match result {
        Ok(Ok(julia_response)) => {
            let status = julia_response.get("status").and_then(|v| v.as_str()).unwrap_or("error").to_string();
            let messages: Vec<Message> = julia_response.get("messages").and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default();
            let result_payload = julia_response.get("result_payload").cloned();

            let run_record = persistence::build_model_run_record(&request, &dataset_path, &status, &messages, &[], result_payload.as_ref(), &started_at);
            let _ = persistence::persist_run_record(&working_dir, &run_record);

            let task_response = TaskResponse {
                task_id: request.task_id, status: status.clone(), messages,
                artifacts: if status == "success" { Some(vec![]) } else { None },
                run_record: serde_json::to_value(&run_record).ok(),
                result_payload,
            };

            (StatusCode::OK, [("Content-Type", "application/json")], serde_json::to_string(&task_response).unwrap_or_default()).into_response()
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

async fn handle_query_dataset_request(
    state: AppState,
    body: String,
) -> axum::response::Response {
    let request: DataCommandRequest = match serde_json::from_str(&body) {
        Ok(req) => req,
        Err(err) => {
            return json_error_response(
                StatusCode::BAD_REQUEST,
                "unknown".to_string(),
                "RUNTIME_INVALID_JSON",
                format!("请求 JSON 解析失败: {err}"),
                Some("请确认 /query_dataset 请求符合协议。".to_string()),
            );
        }
    };

    if request.action != actions::QUERY_DATASET {
        return json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id,
            "RUNTIME_UNSUPPORTED_ACTION",
            format!("端点 query_dataset 不支持动作 `{}`。", request.action),
            Some("请将 action 设为 `query_dataset`。".to_string()),
        );
    }

    if let Err(err) = sanitize_id(&request.task_id) {
        return json_error_response(
            StatusCode::BAD_REQUEST, request.task_id, "RUNTIME_INVALID_TASK_ID", err, None,
        );
    }

    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    let dataset_path = resolve_dataset_path(&request.dataset_ref.path, &working_dir);
    let params = json!({
        "dataset_path": dataset_path,
        "kind": request.command.kind,
        "variables": request.command.variables,
        "limit": request.command.limit,
    });

    let result = dispatch_via_channel(&state.cmd_tx, actions::QUERY_DATASET, params).await;

    match result {
        Ok(Ok(julia_response)) => {
            let status = julia_response.get("status").and_then(|v| v.as_str()).unwrap_or("error").to_string();
            let messages: Vec<Message> = julia_response.get("messages").and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default();
            let result_payload = julia_response.get("result_payload").cloned();
            let artifacts = if status == "success" { Some(vec![]) } else { None };

            let task_response = TaskResponse {
                task_id: request.task_id,
                status,
                messages,
                artifacts,
                run_record: None,
                result_payload,
            };

            (StatusCode::OK, [("Content-Type", "application/json")], serde_json::to_string(&task_response).unwrap_or_default()).into_response()
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

// === 模型参数构建 ===============================================================

fn build_model_params(request: &TaskRequest, validated: &ValidatedModelParams) -> serde_json::Value {
    let vcov = request
        .model_spec
        .vcov
        .as_ref()
        .map(|spec| spec.kind.as_str())
        .unwrap_or("classical");

    let mut map = serde_json::Map::new();
    map.insert("dataset_path".to_string(), json!(""));
    map.insert("formula".to_string(), json!(request.model_spec.formula));
    map.insert("model_type".to_string(), json!(request.model_spec.model_type));
    map.insert("vcov".to_string(), json!(vcov));
    if let Some(ref w) = request.model_spec.weights {
        map.insert("weights".to_string(), json!(w));
    }
    map.insert(
        "return_augment".to_string(),
        json!(request.options.return_augment),
    );
    map.insert(
        "preview_rows".to_string(),
        json!(request.options.preview_rows),
    );
    if let Some(ref col) = request.model_spec.cluster_column {
        map.insert("cluster_column".to_string(), json!(col));
    }

    validated.merge_into_flat(&mut map);

    if request.model_spec.model_type == "quantile" && !map.contains_key("quantile_tau") {
        map.insert("quantile_tau".to_string(), json!(0.5));
    }

    serde_json::Value::Object(map)
}

fn build_model_params_inspect(request: &TaskRequest) -> serde_json::Value {
    let vcov = request
        .model_spec
        .vcov
        .as_ref()
        .map(|spec| spec.kind.as_str())
        .unwrap_or("classical");

    let mut map = serde_json::Map::new();
    map.insert("dataset_path".to_string(), json!(""));
    map.insert("formula".to_string(), json!(request.model_spec.formula));
    map.insert("model_type".to_string(), json!(request.model_spec.model_type));
    map.insert("vcov".to_string(), json!(vcov));
    if let Some(ref w) = request.model_spec.weights {
        map.insert("weights".to_string(), json!(w));
    }
    map.insert(
        "return_augment".to_string(),
        json!(request.options.return_augment),
    );
    map.insert(
        "preview_rows".to_string(),
        json!(request.options.preview_rows),
    );
    crate::model_params::merge_value_into_map(&mut map, request.model_spec.params.clone());
    serde_json::Value::Object(map)
}

// === 校验桥接 ===================================================================

fn validation_error_to_response(err: &ValidationError, task_id: &str) -> axum::response::Response {
    json_error_response(
        StatusCode::BAD_REQUEST,
        task_id.to_string(),
        err.code,
        err.message.clone(),
        err.hint.clone(),
    )
}

#[allow(clippy::result_large_err)]
fn validate_fit_model_request(
    request: &TaskRequest,
) -> Result<ValidatedModelParams, axum::response::Response> {
    let validated = validate_model_request(&request.model_spec)
        .map_err(|err| validation_error_to_response(&err, &request.task_id))?;
    if let Some(err) = validate_spatial_weights_on_disk(request, &validated) {
        return Err(validation_error_to_response(&err, &request.task_id));
    }
    Ok(validated)
}

// === 错误响应 ===================================================================

pub fn json_error_response(
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

// === 辅助函数 ===================================================================

#[allow(clippy::result_large_err)]
fn resolve_transform_output_path(
    working_dir: &std::path::Path,
    task_id: &str,
    persist_output: bool,
) -> Result<Option<String>, axum::response::Response> {
    if !persist_output {
        return Ok(None);
    }
    match persistence::ensure_transform_output_path(working_dir, task_id) {
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
