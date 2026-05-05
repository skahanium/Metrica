pub mod julia_bridge;
pub mod julia_session;
pub mod server;

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub use server::default_bind_addr;
pub use julia_bridge::execute_fit_model;
pub use julia_session::JuliaSession;
pub use server::{build_router, serve as serve_axum};

/// 解析仓库根目录。

/// 模型请求的校验错误，由共享校验函数返回。
/// 调用方（server / julia_bridge）负责将其转换为各自协议的响应格式。
#[derive(Debug, Clone)]
pub struct ValidationError {
    pub code: &'static str,
    pub message: String,
    pub hint: Option<String>,
}

// === 共享路径解析 =============================================================

/// 将相对工作目录解析为绝对路径。
pub fn resolve_working_dir(raw_working_dir: &str) -> std::path::PathBuf {
    let working_dir = std::path::PathBuf::from(raw_working_dir);
    if working_dir.is_absolute() {
        return working_dir;
    }
    repo_root().join(working_dir)
}

/// 将数据集相对路径解析为绝对路径字符串。
pub fn resolve_dataset_path(raw_path: &str, working_dir: &std::path::PathBuf) -> String {
    let dataset_path = std::path::PathBuf::from(raw_path);
    if dataset_path.is_absolute() {
        return dataset_path.to_string_lossy().to_string();
    }
    working_dir.join(dataset_path).to_string_lossy().to_string()
}

// === 共享模型校验 =============================================================

/// 每个 model_type 的必填字段列表（不含 formula 和 dataset_path）。
fn model_required_fields() -> HashMap<&'static str, Vec<&'static str>> {
    HashMap::from([
        ("ols", vec![]),
        ("iv", vec!["instruments", "endog_columns"]),
        ("gls", vec![]),
        ("panel", vec!["panel_id", "panel_time"]),
        ("logit", vec![]),
        ("probit", vec![]),
        ("poisson", vec![]),
        ("ordered_logit", vec![]),
        ("multinomial_logit", vec![]),
        ("negbin", vec![]),
        ("did", vec!["panel_id", "panel_time"]),
        ("event_study", vec!["panel_id", "panel_time"]),
        ("ipw", vec!["treatment_column"]),
        ("psm", vec!["treatment_column"]),
        ("aipw", vec!["treatment_column"]),
    ])
}

/// 校验：model_type 是否在已知注册表中，且必填字段非空。
pub fn validate_model_request(spec: &ModelSpec) -> Option<ValidationError> {
    let required = model_required_fields();
    match required.get(spec.model_type.as_str()) {
        None => Some(ValidationError {
            code: "RUNTIME_UNSUPPORTED_MODEL_TYPE",
            message: format!(
                "runtime 当前支持的模型类型：{}。收到 `{}`。",
                required.keys().cloned().collect::<Vec<_>>().join("、"),
                spec.model_type,
            ),
            hint: Some("请选择支持的模型类型。".to_string()),
        }),
        Some(fields) => {
            for field in fields {
                let value: Option<&str> = match *field {
                    "panel_id" => spec.panel_id.as_deref(),
                    "panel_time" => spec.panel_time.as_deref(),
                    "instruments" => spec.instruments.as_ref().map(|v| if v.is_empty() { "" } else { "present" }),
                    "endog_columns" => spec.endog_columns.as_ref().map(|v| if v.is_empty() { "" } else { "present" }),
                    "treatment_column" => spec.treatment_column.as_deref(),
                    _ => Some("present"),
                };
                match value {
                    Some(v) if !v.is_empty() => {}
                    _ => return Some(ValidationError {
                        code: "RUNTIME_MISSING_FIELD",
                        message: format!("模型类型 `{}` 需要字段 `{}`。", spec.model_type, field),
                        hint: Some(format!("请提供 {}。", field)),
                    }),
                }
            }
            None
        }
    }
}

// === 标准化常量 ===============================================================

/// 支持的 action 类型常量，避免字符串字面量散落各处。
pub mod actions {
    pub const FIT_MODEL: &str = "fit_model";
    pub const INSPECT_DATASET: &str = "inspect_dataset";
    pub const TRANSFORM: &str = "transform";
    pub const EXPORT_REPORT: &str = "export_report";
    pub const SAVE_PROJECT: &str = "save_project";
    pub const LOAD_PROJECT: &str = "load_project";
    pub const LIST_RUNS: &str = "list_runs";
    pub const RERUN_TASK: &str = "rerun_task";
}

// === Julia 响应解析 ===========================================================

/// Julia 返回的标准化响应信封，避免各处重复解析 `"status"`、`"messages"` 等 key。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct JuliaResponse {
    pub status: String,
    #[serde(default)]
    pub messages: Vec<Message>,
    #[serde(default)]
    pub result_payload: Option<serde_json::Value>,
}

impl JuliaResponse {
    /// 从 Julia 返回的 JSON 字符串解析响应信封。
    pub fn from_json(raw: &str) -> Result<Self, String> {
        serde_json::from_str::<JuliaResponse>(raw)
            .map_err(|e| format!("解析 Julia 响应失败: {e}"))
    }

    /// 从响应中提取 content 字段（用于导出场景）。
    pub fn content(&self) -> &str {
        self.result_payload
            .as_ref()
            .and_then(|v| v.get("content"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
    }
}

/// 解析仓库根目录。
///
/// 基于 `CARGO_MANIFEST_DIR`（`runtime/metrica-runtime`）向上两级到仓库根。
pub fn repo_root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .map(|p| p.to_path_buf())
        .unwrap_or_default()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectContext {
    pub project_id: String,
    pub working_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatasetRef {
    pub source: String,
    pub path: String,
    pub format: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcovSpec {
    #[serde(rename = "type")]
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelSpec {
    pub model_type: String,
    pub formula: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub vcov: Option<VcovSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub weights: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cluster_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_method: Option<String>,
    // M6: IV/2SLS 字段
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instruments: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub endog_columns: Option<Vec<String>>,
    // M6: GLS 字段
    #[serde(skip_serializing_if = "Option::is_none")]
    pub omega_spec: Option<String>,
    // S4b: Causal 字段
    #[serde(skip_serializing_if = "Option::is_none")]
    pub treatment_column: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestOptions {
    pub drop_missing: bool,
    pub return_augment: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub dataset_ref: DatasetRef,
    pub model_spec: ModelSpec,
    pub options: RequestOptions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformOptions {
    #[serde(default = "default_transform_preview_rows")]
    pub preview_rows: usize,
    #[serde(default = "default_transform_persist_output")]
    pub persist_output: bool,
}

impl Default for TransformOptions {
    fn default() -> Self {
        Self {
            preview_rows: default_transform_preview_rows(),
            persist_output: default_transform_persist_output(),
        }
    }
}

fn default_transform_preview_rows() -> usize {
    10
}

fn default_transform_persist_output() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformTaskRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub dataset_ref: DatasetRef,
    pub operations: Vec<TransformOperation>,
    #[serde(default)]
    pub options: TransformOptions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub level: String,
    pub code: String,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskResponse {
    pub task_id: String,
    pub status: String,
    pub messages: Vec<Message>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artifacts: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub run_record: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_payload: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataLineage {
    pub source_dataset: String,
    pub active_dataset: String,
    pub operations: Vec<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub row_count_before: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub row_count_after: Option<usize>,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectManifest {
    pub project_id: String,
    pub version: u32,
    pub created_at: String,
    pub updated_at: String,
    pub source_dataset: String,
    pub active_dataset: String,
    pub saved_model_specs: Vec<ModelSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_run_id: Option<String>,
    #[serde(default)]
    pub ui_state: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data_lineage: Option<DataLineage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunRecord {
    pub run_id: String,
    pub action: String,
    pub started_at: String,
    pub finished_at: String,
    pub status: String,
    pub dataset_ref: DatasetRef,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model_spec: Option<ModelSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub operations: Option<Vec<TransformOperation>>,
    #[serde(default)]
    pub warnings: Vec<Value>,
    #[serde(default)]
    pub messages: Vec<Message>,
    #[serde(default)]
    pub artifacts: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_summary: Option<Value>,
    pub request_payload: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SaveProjectRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub manifest: ProjectManifest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadProjectRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListRunsRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub offset: Option<usize>,
    #[serde(default)]
    pub action_filter: Option<String>,
    #[serde(default)]
    pub status_filter: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RerunTaskRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub run_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportReportRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub run_id: String,
    pub format: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct HealthSummary {
    pub service: String,
    pub status: String,
    pub supported_actions: Vec<&'static str>,
}

/// 解析示例 demo 目录。
///
/// 优先读取环境变量 `METRICA_DEMO_DIR`；若未设置，则基于仓库根
/// 拼接 `apps/metrica-desktop` 作为默认路径。
fn default_demo_dir() -> String {
    if let Ok(path) = std::env::var("METRICA_DEMO_DIR") {
        return path;
    }

    repo_root()
        .join("apps")
        .join("metrica-desktop")
        .to_string_lossy()
        .to_string()
}

/// 解析示例 demo CSV 路径。
///
/// 优先读取环境变量 `METRICA_DEMO_CSV`；若未设置，则在 `default_demo_dir()`
/// 的 `data/demo.csv` 子路径中查找。
fn default_demo_csv() -> String {
    if let Ok(path) = std::env::var("METRICA_DEMO_CSV") {
        return path;
    }

    std::path::PathBuf::from(default_demo_dir())
        .join("data")
        .join("demo.csv")
        .to_string_lossy()
        .to_string()
}

fn sample_request_base(action: &str, task_id: &str) -> TaskRequest {
    TaskRequest {
        task_id: task_id.to_string(),
        action: action.to_string(),
        project_context: ProjectContext {
            project_id: "alpha-demo".to_string(),
            working_dir: default_demo_dir(),
        },
        dataset_ref: DatasetRef {
            source: "file".to_string(),
            path: default_demo_csv(),
            format: "csv".to_string(),
        },
        model_spec: ModelSpec {
            model_type: "ols".to_string(),
            formula: "y ~ x1 + x2".to_string(),
            vcov: Some(VcovSpec {
                kind: "classical".to_string(),
            }),
            weights: None,
            cluster_column: None,
            panel_id: None,
            panel_time: None,
            panel_method: None,
            instruments: None,
            endog_columns: None,
            omega_spec: None,
        },
        options: RequestOptions {
            drop_missing: true,
            return_augment: false,
        },
    }
}

pub fn sample_fit_model_request() -> TaskRequest {
    sample_request_base("fit_model", "uuid")
}

pub fn sample_inspect_dataset_request() -> TaskRequest {
    sample_request_base("inspect_dataset", "inspect-uuid")
}

pub fn sample_panel_fit_model_request() -> TaskRequest {
    let mut request = sample_request_base("fit_model", "panel-uuid");
    request.project_context.working_dir = repo_root().to_string_lossy().to_string();
    request.dataset_ref.path = "datasets/teaching/grunfeld.csv".to_string();
    request.model_spec = ModelSpec {
        model_type: "panel".to_string(),
        formula: "invest ~ mvalue + capital".to_string(),
        vcov: None,
        weights: None,
        cluster_column: None,
        panel_id: Some("firm".to_string()),
        panel_time: Some("year".to_string()),
        panel_method: Some("fe".to_string()),
        instruments: None,
        endog_columns: None,
        omega_spec: None,
    };
    request.options.return_augment = true;
    request
}

pub fn sample_success_response() -> TaskResponse {
    TaskResponse {
        task_id: "uuid".to_string(),
        status: "success".to_string(),
        messages: vec![Message {
            level: "info".to_string(),
            code: "INFO_ROWS_DROPPED".to_string(),
            text: "因缺失值已移除 12 行。".to_string(),
            hint: Some("拟合前请检查缺失列。".to_string()),
        }],
        artifacts: Some(vec![]),
        run_record: None,
        result_payload: Some(json!({
            "glance": {
                "model": "ols",
                "nobs": 128,
                "dof": 124,
                "metrics": {
                    "r2": 0.81
                }
            },
            "tidy": [],
            "augment_preview": [],
            "diagnostics": {
                "vif": [
                    { "name": "x1", "vif": 1.25 },
                    { "name": "x2", "vif": 2.5 }
                ],
                "breusch_pagan": { "statistic": 3.2, "pvalue": 0.0736, "dof": 2 },
                "white_test": { "statistic": 5.1, "pvalue": 0.0778, "dof": 2 },
                "durbin_watson": { "statistic": 1.85, "pvalue": 0.62 },
                "breusch_godfrey": { "statistic": 1.2, "pvalue": 0.5488, "dof": 2 },
                "reset_test": { "statistic": 0.45, "pvalue": 0.6453, "df_num": 2, "df_den": 4 },
                "jarque_bera": { "statistic": 0.82, "pvalue": 0.6637, "skewness": 0.15, "kurtosis": 2.8 }
            },
            "warnings": []
        })),
    }
}

pub fn sample_error_response() -> TaskResponse {
    TaskResponse {
        task_id: "uuid".to_string(),
        status: "error".to_string(),
        messages: vec![Message {
            level: "error".to_string(),
            code: "NUM_SINGULAR_MATRIX".to_string(),
            text: "设计矩阵奇异，无法估计模型。".to_string(),
            hint: Some("请检查是否存在某一预测变量是其他变量的线性组合。".to_string()),
        }],
        artifacts: None,
        run_record: None,
        result_payload: None,
    }
}

pub fn health_summary() -> HealthSummary {
    HealthSummary {
        service: "metrica-runtime".to_string(),
        status: "ready".to_string(),
        supported_actions: vec!["inspect_dataset", "fit_model", "transform", "save_project", "load_project", "list_runs", "rerun_task"],
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformOperation {
    pub op: String,
    pub args: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformResult {
    pub operation: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<TransformResultDetail>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview: Option<TransformPreview>,
    pub warnings: Vec<Message>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<TransformError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformResultDetail {
    pub nrows: usize,
    pub ncols: usize,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformPreview {
    pub columns: Vec<String>,
    pub rows: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformError {
    pub op_index: usize,
    pub message: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sample_request_targets_fit_model() {
        let request = sample_fit_model_request();
        assert_eq!(request.action, "fit_model");
        assert_eq!(request.model_spec.model_type, "ols");
    }

    #[test]
    fn sample_panel_request_targets_panel_model() {
        let request = sample_panel_fit_model_request();
        assert_eq!(request.action, "fit_model");
        assert_eq!(request.model_spec.model_type, "panel");
        assert_eq!(request.model_spec.panel_id.as_deref(), Some("firm"));
        assert_eq!(request.model_spec.panel_time.as_deref(), Some("year"));
    }

    #[test]
    fn sample_success_response_contains_result_payload() {
        let response = sample_success_response();
        assert_eq!(response.status, "success");
        assert!(response.result_payload.is_some());
    }

    #[test]
    fn sample_error_response_contains_hint() {
        let response = sample_error_response();
        assert_eq!(response.status, "error");
        assert!(response.messages[0].hint.is_some());
    }
}
