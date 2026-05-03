use std::process::Command;

use serde::Deserialize;
use serde_json::Value;

use crate::{Message, TaskRequest, TaskResponse, ValidationError,
    validate_model_request,
    resolve_working_dir, resolve_dataset_path};

/// 解析 Julia 项目路径。
///
/// 优先读取环境变量 `METRICA_JULIA_PROJECT`；若未设置，则基于
/// 仓库根拼接 `packages/MetricaLinear.jl`。
fn julia_project_path() -> String {
    if let Ok(path) = std::env::var("METRICA_JULIA_PROJECT") {
        return path;
    }

    crate::repo_root()
        .join("packages")
        .join("MetricaLinear.jl")
        .to_string_lossy()
        .to_string()
}

// resolve_working_dir 已由 lib.rs 提供（通过 crate import 引用）

fn resolve_dataset_path_for_request(request: &TaskRequest) -> String {
    let working_dir = resolve_working_dir(&request.project_context.working_dir);
    resolve_dataset_path(&request.dataset_ref.path, &working_dir)
}

const JULIA_SCRIPT: &str = include_str!("../../../scripts/julia_bridge_entry.jl");

#[derive(Debug, Deserialize)]
struct JuliaEnvelope {
    status: String,
    messages: Vec<Message>,
    #[serde(default)]
    result_payload: Option<Value>,
}

pub fn execute_fit_model(request: &TaskRequest) -> Result<TaskResponse, String> {
    if request.action != "fit_model" && request.action != "inspect_dataset" {
        return Ok(runtime_error_response(
            request,
            "RUNTIME_UNSUPPORTED_ACTION",
            format!("runtime 不支持动作 `{}`。", request.action),
            Some("当前 HTTP 入口仅支持 inspect_dataset 与 fit_model。".to_string()),
        ));
    }

    if request.action == "fit_model" {
        if let Some(response) = validate_fit_model_request(request) {
            return Ok(response);
        }
    }

    let mut runtime_request = request.clone();
    runtime_request.project_context.working_dir =
        resolve_working_dir(&request.project_context.working_dir)
            .to_string_lossy()
            .to_string();
    runtime_request.dataset_ref.path = resolve_dataset_path_for_request(request);

    let project_path = julia_project_path();
    let output = Command::new("julia")
        .arg(format!("--project={project_path}"))
        .arg("--startup-file=no")
        .arg("--color=no")
        .arg("-e")
        .arg(JULIA_SCRIPT)
        .arg(
            serde_json::to_string(&runtime_request)
                .map_err(|err| format!("序列化运行时请求失败: {err}"))?,
        )
        .arg(crate::repo_root().to_string_lossy().to_string())
        .output()
        .map_err(|err| format!("启动 Julia 失败: {err}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let message = if stderr.is_empty() {
            "Julia 子进程以非零状态退出，但未返回 stderr。".to_string()
        } else {
            stderr
        };

        return Ok(runtime_error_response(
            request,
            "RUNTIME_JULIA_EXECUTION_FAILED",
            message,
            Some("请检查 Julia 环境、依赖安装与请求参数。".to_string()),
        ));
    }

    let envelope: JuliaEnvelope = serde_json::from_slice(&output.stdout)
        .map_err(|err| format!("解析 Julia JSON 响应失败: {err}"))?;

    Ok(TaskResponse {
        task_id: request.task_id.clone(),
        status: envelope.status.clone(),
        messages: envelope.messages,
        artifacts: if envelope.status == "success" {
            Some(vec![])
        } else {
            None
        },
        run_record: None,
        result_payload: envelope.result_payload,
    })
}

fn validation_error_to_task_response(err: &ValidationError, request: &TaskRequest) -> TaskResponse {
    runtime_error_response(
        request,
        err.code,
        err.message.clone(),
        err.hint.clone(),
    )
}

fn validate_fit_model_request(request: &TaskRequest) -> Option<TaskResponse> {
    validate_model_request(&request.model_spec)
        .map(|err| validation_error_to_task_response(&err, request))
}

fn runtime_error_response(
    request: &TaskRequest,
    code: &str,
    text: String,
    hint: Option<String>,
) -> TaskResponse {
    TaskResponse {
        task_id: request.task_id.clone(),
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
    }
}
