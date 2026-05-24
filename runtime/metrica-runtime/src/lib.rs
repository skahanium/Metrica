pub mod model_params;
pub mod types;
pub mod validation;
pub mod examples;
pub mod julia_bridge;
pub mod julia_session;
pub mod julia_actor;
pub mod persistence;
pub mod handlers;
pub mod server;

pub use model_params::*;
pub use types::*;
pub use validation::*;
pub use examples::*;
pub use server::default_bind_addr;
pub use julia_session::JuliaSession;
pub use server::{build_router, serve as serve_axum, AppState};
pub use server::serve_oneshot;

// === 仓库根目录解析 =============================================================

/// 解析仓库根目录（基于 `CARGO_MANIFEST_DIR` 向上两级）。
pub fn repo_root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .map(|p| p.to_path_buf())
        .unwrap_or_default()
}

/// 将相对工作目录解析为绝对路径。
pub fn resolve_working_dir(raw_working_dir: &str) -> std::path::PathBuf {
    let working_dir = std::path::PathBuf::from(raw_working_dir);
    if working_dir.is_absolute() {
        return working_dir;
    }
    repo_root().join(working_dir)
}

/// 将数据集相对路径解析为绝对路径字符串。
pub fn resolve_dataset_path(raw_path: &str, working_dir: &std::path::Path) -> String {
    let dataset_path = std::path::PathBuf::from(raw_path);
    if dataset_path.is_absolute() {
        return dataset_path.to_string_lossy().to_string();
    }
    working_dir.join(dataset_path).to_string_lossy().to_string()
}

// === 安全 ID 校验 ===============================================================

/// 校验 ID 白名单：仅允许 A-Za-z0-9_-，不能为空。
pub fn sanitize_id(id: &str) -> Result<String, String> {
    if id.is_empty() {
        return Err("ID 不能为空。".into());
    }
    if id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        Ok(id.to_string())
    } else {
        Err(format!("ID '{}' 包含非法字符，仅允许 A-Za-z0-9_-。", id))
    }
}

/// 在 runs 目录下构建安全的 run 文件路径。
pub fn safe_runs_path(working_dir: &std::path::Path, run_id: &str) -> Result<std::path::PathBuf, String> {
    let sanitized = sanitize_id(run_id)?;
    let runs = working_dir.join(".metrica").join("runs");
    let path = runs.join(format!("{}.json", sanitized));
    if !path.starts_with(&runs) {
        return Err("路径越界。".into());
    }
    Ok(path)
}

// === 测试 =======================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sample_request_targets_fit_model() {
        let request = examples::sample_fit_model_request();
        assert_eq!(request.action, "fit_model");
        assert_eq!(request.model_spec.model_type, "ols");
    }

    #[test]
    fn sample_panel_request_targets_panel_model() {
        let request = examples::sample_panel_fit_model_request();
        assert_eq!(request.action, "fit_model");
        assert_eq!(request.model_spec.model_type, "panel");
        assert_eq!(
            request.model_spec.params.get("panel_id").and_then(|v| v.as_str()),
            Some("firm")
        );
        assert_eq!(
            request.model_spec.params.get("panel_time").and_then(|v| v.as_str()),
            Some("year")
        );
    }

    #[test]
    fn sample_success_response_contains_result_payload() {
        let response = examples::sample_success_response();
        assert_eq!(response.status, "success");
        assert!(response.result_payload.is_some());
    }

    #[test]
    fn sample_error_response_contains_hint() {
        let response = examples::sample_error_response();
        assert_eq!(response.status, "error");
        assert!(response.messages[0].hint.is_some());
    }
}
