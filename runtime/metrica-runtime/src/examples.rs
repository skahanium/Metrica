use serde_json::json;

use crate::repo_root;
use crate::types::{
    DataCommand, DataCommandRequest, DatasetRef, HealthSummary, Message, ModelSpec, ProjectContext,
    RequestOptions, TaskRequest, TaskResponse, VcovSpec,
};

/// 默认 demo 目录路径。
fn default_demo_dir() -> String {
    if let Ok(path) = std::env::var("METRICA_DEMO_DIR") {
        return path;
    }
    repo_root()
        .join("datasets")
        .join("demo")
        .to_string_lossy()
        .to_string()
}

/// 默认 demo CSV 路径。
fn default_demo_csv() -> String {
    if let Ok(path) = std::env::var("METRICA_DEMO_CSV") {
        return path;
    }
    std::path::PathBuf::from(default_demo_dir())
        .join("ols_demo.csv")
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
            vcov: Some(VcovSpec { kind: "classical".to_string() }),
            weights: None,
            cluster_column: None,
            params: json!({}),
        },
        options: RequestOptions {
            drop_missing: true,
            return_augment: false,
            preview_rows: 5,
        },
    }
}

fn sample_data_command_request_base(kind: &str, task_id: &str) -> DataCommandRequest {
    DataCommandRequest {
        task_id: task_id.to_string(),
        action: crate::types::actions::QUERY_DATASET.to_string(),
        project_context: ProjectContext {
            project_id: "alpha-demo".to_string(),
            working_dir: default_demo_dir(),
        },
        dataset_ref: DatasetRef {
            source: "file".to_string(),
            path: default_demo_csv(),
            format: "csv".to_string(),
        },
        command: DataCommand {
            kind: kind.to_string(),
            variables: Some(vec!["x1".to_string()]),
            limit: None,
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
    request.dataset_ref.path = "datasets/demo/grunfeld.csv".to_string();
    request.model_spec = ModelSpec {
        model_type: "panel".to_string(),
        formula: "invest ~ mvalue + capital".to_string(),
        vcov: None,
        weights: None,
        cluster_column: None,
        params: json!({
            "panel_id": "firm",
            "panel_time": "year",
            "panel_method": "fe"
        }),
    };
    request.options.return_augment = true;
    request
}

pub fn sample_query_dataset_request(kind: &str) -> DataCommandRequest {
    let mut request = sample_data_command_request_base(kind, "query-uuid");
    if kind == "describe" || kind == "summarize" {
        request.command.variables = Some(vec!["y".to_string(), "x1".to_string()]);
    } else if kind == "browse" {
        request.command.variables = Some(vec!["y".to_string()]);
    }
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
        supported_actions: vec![
            "inspect_dataset", "query_dataset", "fit_model", "transform",
            "save_project", "load_project", "list_runs", "rerun_task",
        ],
    }
}
