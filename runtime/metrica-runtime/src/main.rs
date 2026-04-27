use metrica_runtime::{
    default_bind_addr, health_summary, sample_error_response, sample_fit_model_request,
    sample_success_response, serve_http,
};

fn main() {
    let mode = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "health".to_string());

    if mode == "serve" {
        let bind_addr = std::env::args().nth(2);
        let bind_addr = bind_addr.as_deref().unwrap_or(default_bind_addr());
        eprintln!("metrica-runtime HTTP server listening on http://{bind_addr}");
        serve_http(Some(bind_addr)).unwrap();
        return;
    }

    let payload = match mode.as_str() {
        "request" => serde_json::to_string_pretty(&sample_fit_model_request()).unwrap(),
        "success" => serde_json::to_string_pretty(&sample_success_response()).unwrap(),
        "error" => serde_json::to_string_pretty(&sample_error_response()).unwrap(),
        _ => serde_json::to_string_pretty(&health_summary()).unwrap(),
    };

    println!("{payload}");
}
