use serde::Serialize;
use serde_json::{json, Value};

#[derive(Debug, Serialize)]
pub struct ProjectContext {
    pub project_id: String,
    pub working_dir: String,
}

#[derive(Debug, Serialize)]
pub struct DatasetRef {
    pub source: String,
    pub path: String,
    pub format: String,
}

#[derive(Debug, Serialize)]
pub struct VcovSpec {
    #[serde(rename = "type")]
    pub kind: String,
}

#[derive(Debug, Serialize)]
pub struct ModelSpec {
    pub model_type: String,
    pub formula: String,
    pub vcov: VcovSpec,
}

#[derive(Debug, Serialize)]
pub struct RequestOptions {
    pub drop_missing: bool,
    pub return_augment: bool,
}

#[derive(Debug, Serialize)]
pub struct TaskRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub dataset_ref: DatasetRef,
    pub model_spec: ModelSpec,
    pub options: RequestOptions,
}

#[derive(Debug, Serialize)]
pub struct Message {
    pub level: String,
    pub code: String,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hint: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct TaskResponse {
    pub task_id: String,
    pub status: String,
    pub messages: Vec<Message>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artifacts: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_payload: Option<Value>,
}

#[derive(Debug, Serialize)]
pub struct HealthSummary {
    pub service: String,
    pub status: String,
    pub supported_actions: Vec<&'static str>,
}

pub fn sample_fit_model_request() -> TaskRequest {
    TaskRequest {
        task_id: "uuid".to_string(),
        action: "fit_model".to_string(),
        project_context: ProjectContext {
            project_id: "proj_001".to_string(),
            working_dir: "/path/to/project".to_string(),
        },
        dataset_ref: DatasetRef {
            source: "file".to_string(),
            path: "/path/to/data.csv".to_string(),
            format: "csv".to_string(),
        },
        model_spec: ModelSpec {
            model_type: "ols".to_string(),
            formula: "y ~ x1 + x2 + x3".to_string(),
            vcov: VcovSpec {
                kind: "classical".to_string(),
            },
        },
        options: RequestOptions {
            drop_missing: true,
            return_augment: true,
        },
    }
}

pub fn sample_success_response() -> TaskResponse {
    TaskResponse {
        task_id: "uuid".to_string(),
        status: "success".to_string(),
        messages: vec![Message {
            level: "info".to_string(),
            code: "ROWS_DROPPED".to_string(),
            text: "12 rows were removed due to missing values.".to_string(),
            hint: None,
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
            "diagnostics": [],
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
            code: "SINGULAR_MATRIX".to_string(),
            text: "Model could not be estimated because the design matrix is singular.".to_string(),
            hint: Some("Check whether one predictor is a linear combination of others.".to_string()),
        }],
        artifacts: None,
        result_payload: None,
    }
}

pub fn health_summary() -> HealthSummary {
    HealthSummary {
        service: "metrica-runtime".to_string(),
        status: "ready".to_string(),
        supported_actions: vec![
            "inspect_dataset",
            "fit_model",
            "export_result",
            "explain_warning",
        ],
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
