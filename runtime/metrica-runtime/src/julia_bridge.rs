use std::process::Command;

use serde::Deserialize;
use serde_json::Value;

use crate::{Message, TaskRequest, TaskResponse};

const JULIA_PROJECT: &str = "/Users/skahanium/Metrica/packages/MetricaLinear.jl";

const JULIA_SCRIPT: &str = r#"
using JSON3
using MetricaLinear

request = JSON3.read(ARGS[1])
action = String(request.action)
dataset_path = String(request.dataset_ref.path)
payload = if action == "inspect_dataset"
    inspect_dataset(dataset_path)
else
    formula = String(request.model_spec.formula)
    result = fit_ols_file(dataset_path, formula)
    result_to_payload(result)
end
println(JSON3.write(payload))
"#;

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

    if request.action == "fit_model" && request.model_spec.model_type != "ols" {
        return Ok(runtime_error_response(
            request,
            "RUNTIME_UNSUPPORTED_MODEL_TYPE",
            format!(
                "runtime 当前仅支持 `ols`，收到 `{}`。",
                request.model_spec.model_type
            ),
            Some("请将 model_type 设为 `ols`。".to_string()),
        ));
    }

    let request_json = serde_json::to_string(request)
        .map_err(|err| format!("序列化 fit_model 请求失败: {err}"))?;

    let output = Command::new("julia")
        .arg(format!("--project={JULIA_PROJECT}"))
        .arg("--startup-file=no")
        .arg("--color=no")
        .arg("-e")
        .arg(JULIA_SCRIPT)
        .arg(request_json)
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
        result_payload: envelope.result_payload,
    })
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
        result_payload: None,
    }
}
