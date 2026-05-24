mod kind;
mod model_rules;
mod required;

pub use required::model_required_fields;

use crate::model_params::ValidatedModelParams;
use crate::types::{ModelSpec, TaskRequest, ValidationError};
use crate::resolve_working_dir;

use kind::dispatch;

/// 校验模型请求并返回已解析的族参数（按 `ModelSpecKind` 分派至各 `validate_*`）。
pub fn validate_model_request(spec: &ModelSpec) -> Result<ValidatedModelParams, ValidationError> {
    dispatch(spec)
}

/// 空间模型：校验权重边表文件在磁盘上存在。
pub fn validate_spatial_weights_on_disk(
    request: &TaskRequest,
    validated: &ValidatedModelParams,
) -> Option<ValidationError> {
    if !matches!(
        request.model_spec.model_type.as_str(),
        "spatial_lag" | "spatial_error" | "spatial_slx" |
        "spatial_sdm" | "spatial_sdem" | "spatial_sac" | "spatial_probit"
    ) {
        return None;
    }
    let wp = validated.spatial_weights_path().unwrap_or("");
    if wp.is_empty() {
        return None;
    }
    let wd = resolve_working_dir(&request.project_context.working_dir);
    let p = std::path::Path::new(wp);
    let full = if p.is_absolute() {
        p.to_path_buf()
    } else {
        wd.join(wp)
    };
    if !full.exists() {
        return Some(ValidationError {
            code: "RUNTIME_SPATIAL_WEIGHTS_NOT_FOUND",
            message: format!("空间权重文件不存在：{}", full.display()),
            hint: Some("请检查 params.spatial_weights_path 与 project_context.working_dir。".to_string()),
        });
    }
    None
}
