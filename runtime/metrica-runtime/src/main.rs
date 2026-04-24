use metrica_runtime::{
    health_summary, sample_error_response, sample_fit_model_request, sample_success_response,
};

fn main() {
    let mode = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "health".to_string());

    let payload = match mode.as_str() {
        "request" => serde_json::to_string_pretty(&sample_fit_model_request()).unwrap(),
        "success" => serde_json::to_string_pretty(&sample_success_response()).unwrap(),
        "error" => serde_json::to_string_pretty(&sample_error_response()).unwrap(),
        _ => serde_json::to_string_pretty(&health_summary()).unwrap(),
    };

    println!("{payload}");
}
