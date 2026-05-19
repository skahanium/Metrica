use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::oneshot;

// === 共享类型 ====================================================================

/// 模型请求的校验错误，由共享校验函数返回。
#[derive(Debug, Clone)]
pub struct ValidationError {
    pub code: &'static str,
    pub message: String,
    pub hint: Option<String>,
}

// === Julia 响应解析 =============================================================

/// Julia 返回的标准化响应信封。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JuliaResponse {
    pub status: String,
    #[serde(default)]
    pub messages: Vec<Message>,
    #[serde(default)]
    pub result_payload: Option<Value>,
}

impl JuliaResponse {
    pub fn from_json(raw: &str) -> Result<Self, String> {
        serde_json::from_str::<JuliaResponse>(raw)
            .map_err(|e| format!("解析 Julia 响应失败: {e}"))
    }

    pub fn content(&self) -> &str {
        self.result_payload
            .as_ref()
            .and_then(|v| v.get("content"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
    }
}

// === 请求 / 响应 结构体 ==========================================================

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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instruments: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub endog_columns: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gmm_weight: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dpgmm_style: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instrument_lags: Option<Vec<i32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub collapse_instruments: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub omega_spec: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub treatment_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub treated_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub post_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub event_time_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub outcome_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub propensity_formula: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub outcome_formula: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub time_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variable: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variables: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order: Option<Vec<i32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub seasonal_order: Option<Vec<i32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ts_method: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lags: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deterministic: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub weights_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub strata_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub psu_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fpc_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub equations: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system_endogenous: Option<Vec<Vec<String>>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system_instruments: Option<Vec<Vec<String>>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sur_max_iter: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sur_tol: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quantile_tau: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_family: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_start: Option<Vec<f64>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_max_iter: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_tol: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold_variable: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold_grid: Option<Vec<f64>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold_trim_frac: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arch_order: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_p: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_q: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_max_iter: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_tol: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_weights_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_id_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_row_standardize: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_coord_columns: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_distance: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_crs: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_kernel: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_bandwidth: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_bandwidth_selection: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_adaptive: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gtwr_time_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gtwr_time_scale: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_time_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_event_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_seed: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_prior_scale: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_iter: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_warmup: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_chains: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_group_column: Option<String>,
}

// === 模型族类型 ==================================================================

#[derive(Debug, Clone)]
pub struct LinearSpec {
    pub formula: String,
    pub vcov: Option<VcovSpec>,
    pub weights: Option<String>,
    pub cluster_column: Option<String>,
}

#[derive(Debug, Clone)]
pub struct IVSpec {
    pub formula: String,
    pub vcov: Option<VcovSpec>,
    pub instruments: Vec<String>,
    pub endog_columns: Vec<String>,
    pub weights: Option<String>,
    pub cluster_column: Option<String>,
}

#[derive(Debug, Clone)]
pub struct PanelSpec {
    pub formula: String,
    pub panel_id: String,
    pub panel_time: String,
    pub panel_method: Option<String>,
    pub vcov: Option<VcovSpec>,
    pub weights: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CausalSpec {
    pub treatment_column: String,
    pub outcome_column: String,
    pub propensity_formula: String,
    pub outcome_formula: Option<String>,
}

#[derive(Debug, Clone)]
pub struct TimeSeriesSpec {
    pub time_column: String,
    pub variable: Option<String>,
    pub variables: Option<Vec<String>>,
    pub order: Option<Vec<i32>>,
    pub seasonal_order: Option<Vec<i32>>,
    pub ts_method: Option<String>,
    pub lags: Option<i32>,
    pub deterministic: Option<String>,
}

#[derive(Debug, Clone)]
pub struct SurveySpec {
    pub formula: String,
    pub weights_column: String,
    pub strata_column: Option<String>,
    pub psu_column: Option<String>,
    pub fpc_column: Option<String>,
}

/// Internal dispatch token — replaces string-based model_type dispatch.
/// Adding a variant here ensures compile-time exhaustiveness checking
/// across validation and params building.
#[derive(Debug, Clone, PartialEq)]
pub enum ModelSpecKind {
    Linear,
    IV,
    GMM,
    Panel,
    Causal,
    TimeSeries,
    Survey,
    Spatial,
    Duration,
    Bayes,
    Nonlinear,
    Quantile,
    System,
    Discrete,
}

impl ModelSpec {
    /// Classify model_type into a ModelSpecKind variant.
    pub fn kind(&self) -> Result<ModelSpecKind, ValidationError> {
        use ModelSpecKind::*;
        match self.model_type.as_str() {
            "ols" | "gls" | "pca" => Ok(Linear),
            "iv" => Ok(IV),
            "gmm_linear" => Ok(GMM),
            "panel" | "panel_iv" | "did" | "event_study" | "dynamic_panel_gmm" => Ok(Panel),
            "logit" | "probit" | "poisson" | "negbin" | "ordered_logit" | "multinomial_logit" => Ok(Discrete),
            "ipw" | "aipw" | "psm" | "did_iv" | "rd" | "rd_iv" => Ok(Causal),
            "sur" | "system_2sls" | "system_3sls" => Ok(System),
            "arima" | "var" | "unitroot" | "cointegration" | "arch" | "garch" | "gjr_garch" | "egarch" => {
                Ok(TimeSeries)
            }
            _ if self.model_type.starts_with("survey_") => Ok(Survey),
            _ if self.model_type.starts_with("spatial_")
                || self.model_type.starts_with("gwr")
                || self.model_type.starts_with("gtwr") =>
            {
                Ok(Spatial)
            }
            "duration_cox" | "aft_weibull" | "aft_exponential" | "aft_lognormal" | "aft_loglogistic" => {
                Ok(Duration)
            }
            "bayes_linear" | "bayes_logistic" | "bayes_probit" | "bayes_hierarchical" => Ok(Bayes),
            "nls" | "threshold" => Ok(Nonlinear),
            "quantile" => Ok(Quantile),
            _ => Err(ValidationError {
                code: "RUNTIME_UNKNOWN_MODEL_TYPE",
                message: format!("未知的模型类型：{}", self.model_type),
                hint: Some("请检查 model_type 字段。".to_string()),
            }),
        }
    }
}



// === 请求 / 选项结构体 ============================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestOptions {
    pub drop_missing: bool,
    pub return_augment: bool,
    #[serde(default = "default_inspect_preview_rows")]
    pub preview_rows: usize,
}

pub fn default_inspect_preview_rows() -> usize { 5 }

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
pub struct DiagnosticRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub dataset_ref: DatasetRef,
    pub model_spec: ModelSpec,
    pub diagnostic: DiagnosticSpec,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiagnosticSpec {
    pub test: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lags: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataCommand {
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variables: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataCommandRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub dataset_ref: DatasetRef,
    pub command: DataCommand,
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

pub fn default_transform_preview_rows() -> usize { 10 }
pub fn default_transform_persist_output() -> bool { true }

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

// === Transform 结构体 ===========================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformOperation {
    pub op: String,
    pub args: Value,
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
    pub rows: Vec<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformError {
    pub op_index: usize,
    pub message: String,
}

// === Julia 命令通道类型 =========================================================

pub type JuliaCommand = (String, Value, oneshot::Sender<Result<Value, String>>);

// === action 常量 ================================================================

pub mod actions {
    pub const FIT_MODEL: &str = "fit_model";
    pub const INSPECT_DATASET: &str = "inspect_dataset";
    pub const QUERY_DATASET: &str = "query_dataset";
    pub const TRANSFORM: &str = "transform";
    pub const EXPORT_REPORT: &str = "export_report";
    pub const SAVE_PROJECT: &str = "save_project";
    pub const LOAD_PROJECT: &str = "load_project";
    pub const LIST_RUNS: &str = "list_runs";
    pub const RERUN_TASK: &str = "rerun_task";
    pub const RUN_DIAGNOSTIC: &str = "run_diagnostic";
}
