use serde_json::Value;

use crate::types::{
    actions, Message, RunRecord, TaskRequest, TransformTaskRequest,
};
use crate::sanitize_id;

pub fn current_timestamp_string() -> String {
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

pub fn project_manifest_path(working_dir: &std::path::Path) -> std::path::PathBuf {
    metrica_dir(working_dir).join("project.json")
}

pub fn ensure_metrica_dir(working_dir: &std::path::Path) -> Result<(), String> {
    std::fs::create_dir_all(runs_dir(working_dir))
        .map_err(|err| format!("创建 .metrica 目录失败（{}）：{err}", metrica_dir(working_dir).display()))
}

pub fn write_json_file<T: serde::Serialize>(path: &std::path::Path, value: &T) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|err| format!("创建目录失败（{}）：{err}", parent.display()))?;
    }
    let body = serde_json::to_string_pretty(value)
        .map_err(|err| format!("JSON 序列化失败：{err}"))?;
    std::fs::write(path, body).map_err(|err| format!("写入文件失败（{}）：{err}", path.display()))
}

pub fn read_json_file<T: serde::de::DeserializeOwned>(path: &std::path::Path) -> Result<T, String> {
    let body = std::fs::read_to_string(path)
        .map_err(|err| format!("读取文件失败（{}）：{err}", path.display()))?;
    serde_json::from_str(&body).map_err(|err| format!("JSON 解析失败（{}）：{err}", path.display()))
}

pub fn ensure_transform_output_path(
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

pub fn list_run_records(working_dir: &std::path::Path) -> Result<Vec<RunRecord>, String> {
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

// === Run record =====

fn summarize_model_payload(action: &str, payload: &Value) -> Value {
    if action == actions::FIT_MODEL {
        return serde_json::json!({
            "glance": payload.get("glance").cloned().unwrap_or(Value::Null),
            "tidy": payload.get("tidy").cloned().unwrap_or(Value::Null),
            "diagnostics": payload.get("diagnostics").cloned().unwrap_or(Value::Null),
            "warnings": payload.get("warnings").cloned().unwrap_or(Value::Array(vec![])),
            "vcov_label": payload.get("vcov_label").cloned().unwrap_or(Value::Null),
        });
    }
    payload.clone()
}

pub fn build_model_run_record(
    request: &TaskRequest,
    dataset_path: &str,
    status: &str,
    messages: &[Message],
    artifacts: &[String],
    result_payload: Option<&Value>,
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
        request_payload: serde_json::to_value(request).unwrap_or(Value::Null),
    }
}

pub fn build_transform_run_record(
    request: &TransformTaskRequest,
    dataset_path: &str,
    status: &str,
    messages: &[Message],
    artifacts: &[String],
    result_payload: Option<&Value>,
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
        request_payload: serde_json::to_value(request).unwrap_or(Value::Null),
    }
}

pub fn persist_run_record(working_dir: &std::path::Path, run_record: &RunRecord) -> Result<(), String> {
    let sanitized_id = sanitize_id(&run_record.run_id)?;
    ensure_metrica_dir(working_dir)?;
    let path = runs_dir(working_dir).join(format!("{}.json", sanitized_id));
    write_json_file(&path, run_record)
}

// 所有函数已直接标记为 pub，无需额外重导出。
