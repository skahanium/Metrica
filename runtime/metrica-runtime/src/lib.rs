pub mod http;
pub mod julia_bridge;
pub mod julia_session;
pub mod server;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub use http::{build_http_response, default_bind_addr, serve_http, HttpResponse};
pub use julia_bridge::execute_fit_model;
pub use julia_session::JuliaSession;
pub use server::{build_router, serve as serve_axum};

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
    pub result_payload: Option<Value>,
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
        result_payload: None,
    }
}

pub fn health_summary() -> HealthSummary {
    HealthSummary {
        service: "metrica-runtime".to_string(),
        status: "ready".to_string(),
        supported_actions: vec!["inspect_dataset", "fit_model"],
    }
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
