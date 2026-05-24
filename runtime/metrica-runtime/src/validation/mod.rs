mod model_rules;
mod required;

pub use required::model_required_fields;

use crate::model_params::{
    parse_params, BayesParams, CausalParams, DiscreteParams, DurationParams, LinearParams,
    NonlinearParams, PanelParams, QuantileParams, SpatialParams, SurveyParams, SystemParams,
    TimeSeriesParams, ValidatedModelParams,
};
use crate::types::{ModelSpec, ModelSpecKind, TaskRequest, ValidationError};
use crate::resolve_working_dir;

use model_rules::validate_model_specific_rules;
use required::{check_required_in_params, non_empty_str};

fn validate_panel_index(kind: &ModelSpecKind, panel: &PanelParams) -> Result<(), ValidationError> {
    if !matches!(kind, ModelSpecKind::Panel) {
        return Ok(());
    }
    if non_empty_str(&panel.panel_id) && non_empty_str(&panel.panel_time) {
        return Ok(());
    }
    Err(ValidationError {
        code: "RUNTIME_PANEL_INDEX_REQUIRED",
        message: "panel 类模型需要同时提供非空的 panel_id 与 panel_time。".to_string(),
        hint: Some("请在 model_spec.params 中填写 panel_id 与 panel_time。".to_string()),
    })
}

fn into_validated_params(
    kind: ModelSpecKind,
    spec: &ModelSpec,
    linear: LinearParams,
    panel: PanelParams,
    causal: CausalParams,
    ts: TimeSeriesParams,
    survey: SurveyParams,
    system: SystemParams,
    spatial: SpatialParams,
    duration: DurationParams,
    bayes: BayesParams,
    nonlinear: NonlinearParams,
    quantile: QuantileParams,
) -> Result<ValidatedModelParams, ValidationError> {
    Ok(match kind {
        ModelSpecKind::Linear => ValidatedModelParams::Linear(linear),
        ModelSpecKind::IV => ValidatedModelParams::IV(linear),
        ModelSpecKind::GMM => ValidatedModelParams::Gmm(linear),
        ModelSpecKind::Panel => ValidatedModelParams::Panel(panel),
        ModelSpecKind::Causal => ValidatedModelParams::Causal(causal),
        ModelSpecKind::TimeSeries => ValidatedModelParams::TimeSeries(ts),
        ModelSpecKind::Survey => ValidatedModelParams::Survey(survey),
        ModelSpecKind::System => ValidatedModelParams::System(system),
        ModelSpecKind::Spatial => ValidatedModelParams::Spatial(spatial),
        ModelSpecKind::Duration => ValidatedModelParams::Duration(duration),
        ModelSpecKind::Bayes => ValidatedModelParams::Bayes(bayes),
        ModelSpecKind::Nonlinear => ValidatedModelParams::Nonlinear(nonlinear),
        ModelSpecKind::Quantile => ValidatedModelParams::Quantile(quantile),
        ModelSpecKind::Discrete => {
            let discrete: DiscreteParams = parse_params(&spec.params, "INVALID_DISCRETE_PARAMS")?;
            ValidatedModelParams::Discrete(discrete)
        }
    })
}

/// 校验模型请求并返回已解析的族参数。
pub fn validate_model_request(spec: &ModelSpec) -> Result<ValidatedModelParams, ValidationError> {
    let kind = spec.kind()?;
    let mt = spec.model_type.as_str();

    let panel: PanelParams = parse_params(&spec.params, "INVALID_PANEL_PARAMS")?;
    let linear: LinearParams = parse_params(&spec.params, "INVALID_LINEAR_PARAMS")?;
    let causal: CausalParams = parse_params(&spec.params, "INVALID_CAUSAL_PARAMS")?;
    let ts: TimeSeriesParams = parse_params(&spec.params, "INVALID_TIMESERIES_PARAMS")?;
    let survey: SurveyParams = parse_params(&spec.params, "INVALID_SURVEY_PARAMS")?;
    let system: SystemParams = parse_params(&spec.params, "INVALID_SYSTEM_PARAMS")?;
    let spatial: SpatialParams = parse_params(&spec.params, "INVALID_SPATIAL_PARAMS")?;
    let duration: DurationParams = parse_params(&spec.params, "INVALID_DURATION_PARAMS")?;
    let bayes: BayesParams = parse_params(&spec.params, "INVALID_BAYES_PARAMS")?;
    let nonlinear: NonlinearParams = parse_params(&spec.params, "INVALID_NONLINEAR_PARAMS")?;
    let quantile: QuantileParams = parse_params(&spec.params, "INVALID_QUANTILE_PARAMS")?;

    validate_panel_index(&kind, &panel)?;

    let required = model_required_fields();
    let empty = vec![];
    let fields = required.get(mt).unwrap_or(&empty);
    check_required_in_params(
        mt, fields, &panel, &linear, &causal, &ts, &survey, &system, &spatial, &duration, &bayes,
    )?;

    validate_model_specific_rules(mt, &panel, &linear, &ts, &system, &spatial, &nonlinear, &quantile)?;

    into_validated_params(
        kind, spec, linear, panel, causal, ts, survey, system, spatial, duration, bayes, nonlinear,
        quantile,
    )
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
