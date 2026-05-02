//! Alpha 垂直切片：真实 Julia 桥与最小 HTTP 传输测试。

use metrica_runtime::{
    execute_fit_model, repo_root,
    server::build_router,
    sample_fit_model_request, sample_inspect_dataset_request, sample_panel_fit_model_request,
    JuliaSession,
};
use std::sync::{Arc, Mutex};

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

#[tokio::test(flavor = "multi_thread")]
async fn transform_filter_operation_returns_ok() {
    let root = repo_root();
    let julia_project = root.join("packages").join("MetricaLinear.jl");
    let session = JuliaSession::start(&root.to_string_lossy(), &julia_project.to_string_lossy())
        .expect("Julia session should start");
    let app = build_router(Arc::new(Mutex::new(session)));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test runtime");
    let addr = listener.local_addr().expect("test runtime address");
    let server = tokio::spawn(async move {
        axum::serve(listener, app).await.expect("serve test runtime");
    });

    let client = reqwest::Client::new();

    let body = serde_json::json!({
        "dataset_path": concat!(env!("CARGO_MANIFEST_DIR"), "/../../datasets/teaching/pwt_productivity_panel.csv"),
        "operations": [
            {"op": "filter", "args": {"condition": "year >= 2015"}},
            {"op": "generate", "args": {"name": "log_output", "expr": "log(output_per_worker)"}}
        ]
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
    assert_eq!(json["status"], "success");
    assert!(json["result_payload"]["result"]["nrows"].as_u64().unwrap() > 0);
    server.abort();
}
