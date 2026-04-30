//! Alpha 垂直切片：真实 Julia 桥与最小 HTTP 传输测试。

use metrica_runtime::{
    build_http_response, execute_fit_model, sample_fit_model_request,
    sample_inspect_dataset_request, HttpResponse,
};

fn response_header<'a>(response: &'a HttpResponse, name: &str) -> Option<&'a str> {
    response
        .headers
        .iter()
        .find(|(key, _)| *key == name)
        .map(|(_, value)| value.as_str())
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
    request.model_spec.vcov.kind = "HC1".to_string();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    assert_eq!(payload.get("vcov_label").and_then(|value| value.as_str()), Some("HC1"));
}

#[test]
fn fit_model_forwards_weights_to_julia() {
    let mut request = sample_fit_model_request();
    request.model_spec.weights = Some("x1".to_string());
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    let glance = payload.get("glance").expect("glance");
    assert_eq!(glance.get("model").and_then(|value| value.as_str()), Some("wls"));
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
fn options_fit_model_returns_cors_headers() {
    let response = build_http_response("OPTIONS", "/fit_model", &[]).expect("options response");

    assert_eq!(response.status_code, 204);
    assert_eq!(
        response_header(&response, "Access-Control-Allow-Origin"),
        Some("*")
    );
    assert_eq!(
        response_header(&response, "Access-Control-Allow-Methods"),
        Some("POST, OPTIONS")
    );
    assert_eq!(
        response_header(&response, "Access-Control-Allow-Headers"),
        Some("Content-Type")
    );
}

#[test]
fn post_fit_model_returns_json_with_cors_headers() {
    let request_body =
        serde_json::to_vec(&sample_fit_model_request()).expect("serialize sample request");
    let response = build_http_response("POST", "/fit_model", &request_body).expect("post response");

    assert_eq!(response.status_code, 200);
    assert_eq!(
        response_header(&response, "Content-Type"),
        Some("application/json")
    );
    assert_eq!(
        response_header(&response, "Access-Control-Allow-Origin"),
        Some("*")
    );

    let task_response: metrica_runtime::TaskResponse =
        serde_json::from_slice(&response.body).expect("decode task response");
    assert_eq!(task_response.status, "success");
    assert!(task_response.result_payload.is_some());
}

#[test]
fn post_inspect_dataset_returns_json_with_cors_headers() {
    let request_body = serde_json::to_vec(&sample_inspect_dataset_request())
        .expect("serialize sample inspect request");
    let response =
        build_http_response("POST", "/inspect_dataset", &request_body).expect("post response");

    assert_eq!(response.status_code, 200);
    assert_eq!(
        response_header(&response, "Content-Type"),
        Some("application/json")
    );
    assert_eq!(
        response_header(&response, "Access-Control-Allow-Origin"),
        Some("*")
    );

    let task_response: metrica_runtime::TaskResponse =
        serde_json::from_slice(&response.body).expect("decode task response");
    assert_eq!(task_response.status, "success");
    assert!(task_response.result_payload.is_some());
}
