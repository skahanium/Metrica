//! Alpha 垂直切片：真实 Julia 桥与最小 HTTP 传输测试。

use metrica_runtime::{
    julia_bridge::{execute_fit_model, execute_query_dataset},
    repo_root,
    server::build_router,
    sample_fit_model_request, sample_inspect_dataset_request, sample_panel_fit_model_request,
    sample_query_dataset_request,
    AppState, JuliaSession,
};
use std::fs;

/// 与 `sample_fit_model_request` 默认落盘目录一致，便于 list_runs / export / rerun 与 fit 使用同一 `working_dir`。
fn default_demo_working_dir() -> String {
    if let Ok(p) = std::env::var("METRICA_DEMO_DIR") {
        return p;
    }
    repo_root()
        .join("datasets")
        .join("demo")
        .to_string_lossy()
        .to_string()
}

async fn spawn_test_runtime() -> (std::net::SocketAddr, tokio::task::JoinHandle<()>) {
    let root = repo_root();
    let julia_project = root.join("packages").join("MetricaRuntime.jl");
    let session = JuliaSession::start(&root.to_string_lossy(), &julia_project.to_string_lossy())
        .expect("Julia session should start");
    let state = AppState::from_session(session);
    let app = build_router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test runtime");
    let addr = listener.local_addr().expect("test runtime address");
    let server = tokio::spawn(async move {
        axum::serve(listener, app).await.expect("serve test runtime");
    });
    (addr, server)
}

#[test]
fn fit_model_returns_real_payload_shape() {
    let request = sample_fit_model_request();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    assert!(payload.get("glance").is_some());
    assert!(payload.get("tidy").is_some());
}

#[test]
fn fit_model_accepts_paths_relative_to_project_context() {
    let mut request = sample_fit_model_request();
    request.project_context.working_dir = "apps/metrica-desktop".to_string();
    request.dataset_ref.path = "data/demo.csv".to_string();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    assert!(payload.get("glance").is_some());
    assert!(payload.get("tidy").is_some());
}

#[test]
fn fit_model_forwards_hc1_vcov_to_julia() {
    let mut request = sample_fit_model_request();
    request.model_spec.vcov.as_mut().expect("vcov").kind = "HC1".to_string();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    assert_eq!(
        payload.get("vcov_label").and_then(|value| value.as_str()),
        Some("HC1")
    );
}

#[test]
fn fit_model_forwards_lowercase_hc1_vcov_to_julia() {
    let mut request = sample_fit_model_request();
    request.model_spec.vcov.as_mut().expect("vcov").kind = "hc1".to_string();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    assert_eq!(
        payload.get("vcov_label").and_then(|value| value.as_str()),
        Some("HC1")
    );
}

#[test]
fn fit_model_runs_unitroot_through_time_series_bridge() {
    let path = std::env::temp_dir().join("metrica_unitroot_bridge.csv");
    fs::write(
        &path,
        "time,y\n1,1.0\n2,1.2\n3,1.1\n4,1.4\n5,1.3\n6,1.6\n7,1.5\n8,1.8\n9,1.7\n10,2.0\n11,1.9\n12,2.2\n",
    )
    .expect("write time series fixture");

    let mut request = sample_fit_model_request();
    request.dataset_ref.path = path.to_string_lossy().to_string();
    request.model_spec.model_type = "unitroot".to_string();
    request.model_spec.formula = "y".to_string();
    request.model_spec.variable = Some("y".to_string());
    request.model_spec.time_column = Some("time".to_string());
    request.model_spec.deterministic = Some("constant".to_string());

    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    let glance = payload.get("glance").expect("glance");
    let model = glance.get("model").and_then(|v| v.as_str()).expect("glance.model");
    assert!(
        model.to_ascii_lowercase().contains("unitroot"),
        "unexpected glance.model: {model}"
    );
}

#[test]
fn fit_model_runs_ipw_with_propensity_formula() {
    let path = std::env::temp_dir().join("metrica_ipw_bridge.csv");
    fs::write(
        &path,
        "y,treated,x1,x2\n10,0,0.1,1.0\n11,0,0.2,0.8\n12,0,0.3,0.6\n14,1,0.7,0.4\n15,1,0.8,0.2\n16,1,0.9,0.1\n",
    )
    .expect("write causal fixture");

    let mut request = sample_fit_model_request();
    request.dataset_ref.path = path.to_string_lossy().to_string();
    request.model_spec.model_type = "ipw".to_string();
    request.model_spec.formula = "".to_string();
    request.model_spec.treatment_column = Some("treated".to_string());
    request.model_spec.outcome_column = Some("y".to_string());
    request.model_spec.propensity_formula = Some("treated ~ x1 + x2".to_string());

    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    let glance = payload.get("glance").expect("glance");
    assert_eq!(
        glance.get("model").and_then(|value| value.as_str()),
        Some("ipw")
    );
}

#[test]
fn fit_model_forwards_weights_to_julia() {
    let mut request = sample_fit_model_request();
    request.model_spec.weights = Some("x1".to_string());
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    let glance = payload.get("glance").expect("glance");
    assert_eq!(
        glance.get("model").and_then(|value| value.as_str()),
        Some("wls")
    );
}

#[test]
fn fit_model_forwards_panel_request_to_julia() {
    let request = sample_panel_fit_model_request();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    let glance = payload.get("glance").expect("glance");
    assert_eq!(
        glance.get("model").and_then(|value| value.as_str()),
        Some("fe")
    );

    let metrics = glance.get("metrics").expect("metrics");
    assert_eq!(
        metrics.get("n_ids").and_then(|value| value.as_i64()),
        Some(20)
    );
    assert_eq!(
        metrics.get("n_times").and_then(|value| value.as_i64()),
        Some(20)
    );

    let tidy = payload
        .get("tidy")
        .and_then(|value| value.as_array())
        .expect("tidy");
    assert!(!tidy.is_empty());

    let augment = payload.get("augment_preview").expect("augment_preview");
    assert!(augment
        .get("fitted")
        .and_then(|value| value.as_array())
        .is_some());
    assert!(augment
        .get("residual")
        .and_then(|value| value.as_array())
        .is_some());

    let diagnostics = payload.get("diagnostics").expect("diagnostics");
    assert!(diagnostics.get("hausman").is_some());
    assert!(diagnostics.get("fixed_effect_f").is_some());
    assert!(diagnostics.get("breusch_pagan_lm").is_some());
}

#[test]
fn fit_model_requires_panel_index_fields() {
    let mut request = sample_panel_fit_model_request();
    request.model_spec.panel_id = None;
    request.model_spec.panel_time = Some("".to_string());
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "error");
    assert_eq!(response.messages[0].code, "RUNTIME_PANEL_INDEX_REQUIRED");
    assert!(response.messages[0].text.contains("panel_id"));
    assert!(response.messages[0].text.contains("panel_time"));
}

#[test]
fn fit_model_returns_structured_diagnostics() {
    let request = sample_fit_model_request();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    let diagnostics = payload.get("diagnostics").expect("diagnostics");

    // VIF
    assert!(diagnostics
        .get("vif")
        .and_then(|value| value.as_array())
        .is_some());

    // Breusch-Pagan
    let bp = diagnostics.get("breusch_pagan").expect("breusch_pagan");
    assert!(bp.get("statistic").is_some());
    assert!(bp.get("pvalue").is_some());
    assert!(bp.get("dof").is_some());

    // White
    let white = diagnostics.get("white_test").expect("white_test");
    assert!(white.get("statistic").is_some());
    assert!(white.get("pvalue").is_some());
    assert!(white.get("dof").is_some());

    // Durbin-Watson
    let dw = diagnostics.get("durbin_watson").expect("durbin_watson");
    assert!(dw.get("statistic").is_some());

    // Breusch-Godfrey
    let bg = diagnostics.get("breusch_godfrey").expect("breusch_godfrey");
    assert!(bg.get("statistic").is_some());
    assert!(bg.get("pvalue").is_some());
    assert!(bg.get("dof").is_some());

    // RESET
    let reset = diagnostics.get("reset_test").expect("reset_test");
    assert!(reset.get("statistic").is_some());
    assert!(reset.get("pvalue").is_some());
    assert!(reset.get("df_num").is_some());
    assert!(reset.get("df_den").is_some());

    // Jarque-Bera
    let jb = diagnostics.get("jarque_bera").expect("jarque_bera");
    assert!(jb.get("statistic").is_some());
    assert!(jb.get("pvalue").is_some());
    assert!(jb.get("skewness").is_some());
    assert!(jb.get("kurtosis").is_some());
}

#[test]
fn inspect_dataset_returns_preview_payload_shape() {
    let request = sample_inspect_dataset_request();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    assert!(payload.get("dataset_summary").is_some());
    assert!(payload.get("columns").is_some());
    assert!(payload.get("preview_rows").is_some());
}

#[test]
fn inspect_dataset_accepts_paths_relative_to_project_context() {
    let mut request = sample_inspect_dataset_request();
    request.project_context.working_dir = "apps/metrica-desktop".to_string();
    request.dataset_ref.path = "data/demo.csv".to_string();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    assert!(payload.get("dataset_summary").is_some());
    assert!(payload.get("columns").is_some());
    assert!(payload.get("preview_rows").is_some());
}

#[test]
fn query_dataset_returns_describe_payload_shape() {
    let request = sample_query_dataset_request("describe");
    let response = execute_query_dataset(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    assert_eq!(
        payload.get("kind").and_then(|value| value.as_str()),
        Some("describe")
    );
    assert!(payload.get("dataset_summary").is_some());
    assert!(payload.get("variables").is_some());
}

#[tokio::test(flavor = "multi_thread")]
async fn query_dataset_endpoint_returns_tabulate_payload() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();

    let body = serde_json::json!({
        "task_id": "query-tabulate",
        "action": "query_dataset",
        "project_context": {
            "project_id": "alpha-demo",
            "working_dir": concat!(env!("CARGO_MANIFEST_DIR"), "/../..")
        },
        "dataset_ref": {
            "source": "file",
            "path": "apps/metrica-desktop/data/demo.csv",
            "format": "csv"
        },
        "command": {
            "kind": "tabulate",
            "variables": ["x1"]
        }
    });

    let response = client
        .post(format!("http://{addr}/query_dataset"))
        .json(&body)
        .send()
        .await
        .expect("query dataset response");

    assert!(response.status().is_success());
    let json: serde_json::Value = response.json().await.expect("query dataset json");
    let payload = json.get("result_payload").expect("result payload");
    assert_eq!(payload.get("kind").and_then(|value| value.as_str()), Some("tabulate"));
    assert!(payload.get("rows").and_then(|value| value.as_array()).is_some());

    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn transform_filter_operation_returns_ok() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();

    let body = serde_json::json!({
        "task_id": "transform-ok",
        "action": "transform",
        "project_context": {
            "project_id": "alpha-demo",
            "working_dir": concat!(env!("CARGO_MANIFEST_DIR"), "/../..")
        },
        "dataset_ref": {
            "source": "file",
            "path": "datasets/demo/pwt_productivity_panel.csv",
            "format": "csv"
        },
        "operations": [
            {"op": "filter", "args": {"condition": "year >= 2015"}},
            {"op": "generate", "args": {"name": "log_output", "expr": "log(output_per_worker)"}}
        ],
        "options": {"preview_rows": 5, "persist_output": true}
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/transform"))
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .expect("POST /transform should succeed");

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = resp.json().await.expect("response should be JSON");
    assert_eq!(json["task_id"], "transform-ok");
    assert_eq!(json["status"], "success");
    assert!(json["result_payload"]["result"]["nrows"].as_u64().unwrap() > 0);
    let derived_path = json["result_payload"]["result"]["dataset_path"]
        .as_str()
        .expect("derived dataset path");
    assert!(std::path::Path::new(derived_path).is_file());
    assert!(derived_path.contains(".metrica/derived/transform-ok.csv"));
    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn save_and_load_project_roundtrip() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let working_dir = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

    let save_body = serde_json::json!({
        "task_id": "save-project",
        "action": "save_project",
        "project_context": { "project_id": "alpha-demo", "working_dir": working_dir },
        "manifest": {
            "project_id": "alpha-demo",
            "version": 1,
            "created_at": "1",
            "updated_at": "2",
            "source_dataset": "/tmp/demo.csv",
            "active_dataset": "/tmp/demo.csv",
            "saved_model_specs": [{ "model_type": "ols", "formula": "y ~ x1" }],
            "last_run_id": null,
            "ui_state": {},
            "data_lineage": null
        }
    })
    .to_string();

    let save_resp = client
        .post(format!("http://{addr}/save_project"))
        .header("Content-Type", "application/json")
        .body(save_body)
        .send()
        .await
        .expect("POST /save_project");
    assert_eq!(save_resp.status(), 200);

    let load_body = serde_json::json!({
        "task_id": "load-project",
        "action": "load_project",
        "project_context": { "project_id": "alpha-demo", "working_dir": working_dir }
    })
    .to_string();

    let load_resp = client
        .post(format!("http://{addr}/load_project"))
        .header("Content-Type", "application/json")
        .body(load_body)
        .send()
        .await
        .expect("POST /load_project");
    assert_eq!(load_resp.status(), 200);
    let json: serde_json::Value = load_resp.json().await.expect("JSON");
    assert_eq!(json["status"], "success");
    assert_eq!(json["result_payload"]["manifest"]["project_id"], "alpha-demo");
    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn fit_model_generates_run_record_and_list_runs_returns_it() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let body = serde_json::to_string(&sample_fit_model_request()).expect("request json");

    let fit_resp = client
        .post(format!("http://{addr}/fit_model"))
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .expect("POST /fit_model");
    assert_eq!(fit_resp.status(), 200);
    let fit_json: serde_json::Value = fit_resp.json().await.expect("fit JSON");
    assert_eq!(fit_json["status"], "success");
    assert!(fit_json["run_record"]["run_id"].as_str().is_some());

    let list_body = serde_json::json!({
        "task_id": "list-runs",
        "action": "list_runs",
        "project_context": {
            "project_id": "alpha-demo",
            "working_dir": default_demo_working_dir()
        }
    })
    .to_string();

    let list_resp = client
        .post(format!("http://{addr}/list_runs"))
        .header("Content-Type", "application/json")
        .body(list_body)
        .send()
        .await
        .expect("POST /list_runs");
    assert_eq!(list_resp.status(), 200);
    let list_json: serde_json::Value = list_resp.json().await.expect("list JSON");
    assert_eq!(list_json["status"], "success");
    assert!(list_json["result_payload"]["runs"].as_array().unwrap().iter().any(|item| item["action"] == "fit_model"));
    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn transform_failure_does_not_write_output() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let derived_path = repo_root()
        .join(".metrica")
        .join("derived")
        .join("transform-fail.csv");
    let _ = std::fs::remove_file(&derived_path);

    let body = serde_json::json!({
        "task_id": "transform-fail",
        "action": "transform",
        "project_context": {
            "project_id": "alpha-demo",
            "working_dir": concat!(env!("CARGO_MANIFEST_DIR"), "/../..")
        },
        "dataset_ref": {
            "source": "file",
            "path": "datasets/demo/pwt_productivity_panel.csv",
            "format": "csv"
        },
        "operations": [
            {"op": "generate", "args": {"name": "bad", "expr": "missing_col + 1"}}
        ],
        "options": {"preview_rows": 5, "persist_output": true}
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/transform"))
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .expect("POST /transform should succeed");

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = resp.json().await.expect("response should be JSON");
    assert_eq!(json["task_id"], "transform-fail");
    assert_eq!(json["status"], "error");
    assert_eq!(json["result_payload"]["error"]["op_index"], 1);
    assert!(!derived_path.is_file());
    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn save_project_rejects_empty_project_id() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();

    let body = serde_json::json!({
        "task_id": "save-invalid",
        "action": "save_project",
        "project_context": { "project_id": "alpha-demo", "working_dir": concat!(env!("CARGO_MANIFEST_DIR"), "/../..") },
        "manifest": {
            "project_id": "",
            "version": 1,
            "created_at": "1",
            "updated_at": "2",
            "source_dataset": "/tmp/demo.csv",
            "active_dataset": "/tmp/demo.csv",
            "saved_model_specs": [],
            "last_run_id": null,
            "ui_state": {},
            "data_lineage": null
        }
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/save_project"))
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .expect("POST /save_project");

    assert_eq!(resp.status(), 400);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    assert_eq!(json["messages"][0]["code"], "RUNTIME_MANIFEST_INVALID");
    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn save_project_rejects_empty_source_dataset() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();

    let body = serde_json::json!({
        "task_id": "save-invalid-src",
        "action": "save_project",
        "project_context": { "project_id": "alpha-demo", "working_dir": concat!(env!("CARGO_MANIFEST_DIR"), "/../..") },
        "manifest": {
            "project_id": "alpha-demo",
            "version": 1,
            "created_at": "1",
            "updated_at": "2",
            "source_dataset": "",
            "active_dataset": "/tmp/demo.csv",
            "saved_model_specs": [],
            "last_run_id": null,
            "ui_state": {},
            "data_lineage": null
        }
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/save_project"))
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .expect("POST /save_project");

    assert_eq!(resp.status(), 400);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    assert_eq!(json["messages"][0]["code"], "RUNTIME_MANIFEST_INVALID");
    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn list_runs_supports_pagination_and_filtering() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let working_dir = default_demo_working_dir();

    // 先执行一次 fit_model 生成 run record
    let mut fit_req = sample_fit_model_request();
    fit_req.project_context.working_dir = working_dir.clone();
    let fit_body = serde_json::to_string(&fit_req).expect("request json");
    let fit_resp = client
        .post(format!("http://{addr}/fit_model"))
        .header("Content-Type", "application/json")
        .body(fit_body)
        .send()
        .await
        .expect("POST /fit_model");
    assert_eq!(fit_resp.status(), 200);

    // 测试 limit
    let list_body = serde_json::json!({
        "task_id": "list-limit",
        "action": "list_runs",
        "project_context": { "project_id": "alpha-demo", "working_dir": working_dir },
        "limit": 1
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/list_runs"))
        .header("Content-Type", "application/json")
        .body(list_body)
        .send()
        .await
        .expect("POST /list_runs");
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    let runs = json["result_payload"]["runs"].as_array().unwrap();
    assert!(runs.len() <= 1);

    // 测试 action_filter
    let filter_body = serde_json::json!({
        "task_id": "list-filter",
        "action": "list_runs",
        "project_context": { "project_id": "alpha-demo", "working_dir": working_dir },
        "action_filter": "fit_model"
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/list_runs"))
        .header("Content-Type", "application/json")
        .body(filter_body)
        .send()
        .await
        .expect("POST /list_runs");
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    let runs = json["result_payload"]["runs"].as_array().unwrap();
    assert!(runs.iter().all(|r| r["action"] == "fit_model"));

    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn rerun_task_returns_error_for_missing_dataset() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let working_dir = default_demo_working_dir();

    // 先执行一次 fit_model 生成 run record
    let mut fit_req = sample_fit_model_request();
    fit_req.project_context.working_dir = working_dir.clone();
    let fit_body = serde_json::to_string(&fit_req).expect("request json");
    let fit_resp = client
        .post(format!("http://{addr}/fit_model"))
        .header("Content-Type", "application/json")
        .body(fit_body)
        .send()
        .await
        .expect("POST /fit_model");
    let fit_json: serde_json::Value = fit_resp.json().await.expect("JSON");
    let run_id = fit_json["run_record"]["run_id"].as_str().expect("run_id");

    // 覆盖 run record 的 dataset_ref 路径为不存在的文件
    let runs_dir = std::path::Path::new(&working_dir).join(".metrica").join("runs");
    let run_path = runs_dir.join(format!("{run_id}.json"));
    assert!(
        run_path.exists(),
        "run record 未落盘，无法测试重跑缺失数据：{}",
        run_path.display()
    );
    let mut run: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(&run_path).expect("read run record"))
            .expect("parse run record");
    run["dataset_ref"]["path"] = serde_json::json!("/nonexistent/missing.csv");
    std::fs::write(&run_path, serde_json::to_string_pretty(&run).unwrap()).unwrap();

    // 尝试重跑
    let rerun_body = serde_json::json!({
        "task_id": "rerun-missing",
        "action": "rerun_task",
        "project_context": { "project_id": "alpha-demo", "working_dir": working_dir },
        "run_id": run_id
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/rerun_task"))
        .header("Content-Type", "application/json")
        .body(rerun_body)
        .send()
        .await
        .expect("POST /rerun_task");

    assert_eq!(resp.status(), 400);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    assert_eq!(json["messages"][0]["code"], "RUNTIME_RERUN_DATASET_MISSING");

    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn export_report_markdown_returns_content() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let working_dir = default_demo_working_dir();

    // 先执行一次 fit_model 生成 run record
    let mut fit_req = sample_fit_model_request();
    fit_req.project_context.working_dir = working_dir.clone();
    let fit_body = serde_json::to_string(&fit_req).expect("request json");
    let fit_resp = client
        .post(format!("http://{addr}/fit_model"))
        .header("Content-Type", "application/json")
        .body(fit_body)
        .send()
        .await
        .expect("POST /fit_model");
    let fit_json: serde_json::Value = fit_resp.json().await.expect("JSON");
    assert_eq!(fit_json["status"], "success");
    let run_id = fit_json["run_record"]["run_id"].as_str().expect("run_id");

    // 导出 Markdown 报告
    let export_body = serde_json::json!({
        "task_id": "export-md",
        "action": "export_report",
        "project_context": { "project_id": "alpha-demo", "working_dir": working_dir },
        "run_id": run_id,
        "format": "markdown"
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/export_report"))
        .header("Content-Type", "application/json")
        .body(export_body)
        .send()
        .await
        .expect("POST /export_report");

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    assert_eq!(json["status"], "success");
    assert_eq!(json["result_payload"]["format"], "markdown");
    let content = json["result_payload"]["content"].as_str().expect("content");
    assert!(content.contains("# Metrica 单次运行报告"));
    assert!(content.contains("y ~ x1 + x2"));

    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn export_report_csv_tidy_returns_csv() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let working_dir = default_demo_working_dir();

    // 先执行一次 fit_model 生成 run record
    let mut fit_req = sample_fit_model_request();
    fit_req.project_context.working_dir = working_dir.clone();
    let fit_body = serde_json::to_string(&fit_req).expect("request json");
    let fit_resp = client
        .post(format!("http://{addr}/fit_model"))
        .header("Content-Type", "application/json")
        .body(fit_body)
        .send()
        .await
        .expect("POST /fit_model");
    let fit_json: serde_json::Value = fit_resp.json().await.expect("JSON");
    assert_eq!(fit_json["status"], "success");
    let run_id = fit_json["run_record"]["run_id"].as_str().expect("run_id");

    // 导出 CSV 系数表
    let export_body = serde_json::json!({
        "task_id": "export-csv",
        "action": "export_report",
        "project_context": { "project_id": "alpha-demo", "working_dir": working_dir },
        "run_id": run_id,
        "format": "csv_tidy"
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/export_report"))
        .header("Content-Type", "application/json")
        .body(export_body)
        .send()
        .await
        .expect("POST /export_report");

    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    assert_eq!(json["status"], "success");
    assert_eq!(json["result_payload"]["format"], "csv_tidy");
    let content = json["result_payload"]["content"].as_str().expect("content");
    assert!(content.contains("term,estimate,std_error,statistic,p_value"));

    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn export_report_rejects_missing_run() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();

    let body = serde_json::json!({
        "task_id": "export-missing",
        "action": "export_report",
        "project_context": { "project_id": "alpha-demo", "working_dir": concat!(env!("CARGO_MANIFEST_DIR"), "/../..") },
        "run_id": "nonexistent-run-id",
        "format": "markdown"
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/export_report"))
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .expect("POST /export_report");

    assert_eq!(resp.status(), 404);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    assert_eq!(json["messages"][0]["code"], "RUNTIME_RUN_NOT_FOUND");

    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn fit_model_http_logit_returns_glance_and_tidy() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let wd = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
    let body = serde_json::json!({
        "task_id": "fit-logit-http",
        "action": "fit_model",
        "project_context": { "project_id": "alpha-demo", "working_dir": wd },
        "dataset_ref": { "source": "file", "path": "datasets/teaching/s4_discrete_demo.csv", "format": "csv" },
        "model_spec": {
            "model_type": "logit",
            "formula": "y_bin ~ x1 + x2"
        },
        "options": { "drop_missing": true, "return_augment": false }
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/fit_model"))
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .expect("POST /fit_model");
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    assert_eq!(json["status"], "success");
    let glance = json["result_payload"]["glance"].as_object().expect("glance");
    assert_eq!(glance["model"].as_str(), Some("logit"));
    let tidy = json["result_payload"]["tidy"].as_array().expect("tidy");
    assert!(!tidy.is_empty());

    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn fit_model_http_arima_returns_time_series_fields() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let wd = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
    let body = serde_json::json!({
        "task_id": "fit-arima-http",
        "action": "fit_model",
        "project_context": { "project_id": "alpha-demo", "working_dir": wd },
        "dataset_ref": { "source": "file", "path": "datasets/teaching/s4_timeseries_demo.csv", "format": "csv" },
        "model_spec": {
            "model_type": "arima",
            "formula": "y",
            "variable": "y",
            "time_column": "time",
            "order": [1, 0, 0]
        },
        "options": { "drop_missing": true, "return_augment": false }
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/fit_model"))
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .expect("POST /fit_model");
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    assert_eq!(json["status"], "success");
    let glance = json["result_payload"]["glance"].as_object().expect("glance");
    let model = glance["model"].as_str().expect("glance.model");
    assert!(
        model.to_ascii_lowercase().contains("arima"),
        "unexpected glance.model: {model}"
    );

    server.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn fit_model_http_survey_ols_returns_survey_fields() {
    let (addr, server) = spawn_test_runtime().await;
    let client = reqwest::Client::new();
    let wd = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
    let body = serde_json::json!({
        "task_id": "fit-svyols-http",
        "action": "fit_model",
        "project_context": { "project_id": "alpha-demo", "working_dir": wd },
        "dataset_ref": { "source": "file", "path": "datasets/teaching/s4_survey_demo.csv", "format": "csv" },
        "model_spec": {
            "model_type": "survey_ols",
            "formula": "y ~ x1 + x2",
            "weights_column": "wt",
            "strata_column": "strata",
            "psu_column": "psu"
        },
        "options": { "drop_missing": true, "return_augment": false }
    })
    .to_string();

    let resp = client
        .post(format!("http://{addr}/fit_model"))
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .expect("POST /fit_model");
    assert_eq!(resp.status(), 200);
    let json: serde_json::Value = resp.json().await.expect("JSON");
    assert_eq!(json["status"], "success");
    let glance = json["result_payload"]["glance"].as_object().expect("glance");
    assert_eq!(glance["model"].as_str(), Some("survey_ols"));

    server.abort();
}
