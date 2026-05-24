use crate::model_params::{
    parse_params, BayesParams, CausalParams, DiscreteParams, DurationParams, LinearParams,
    NonlinearParams, PanelParams, QuantileParams, SpatialParams, SurveyParams, SystemParams,
    TimeSeriesParams, ValidatedModelParams,
};
use crate::types::{ModelSpec, ModelSpecKind, ValidationError};

use super::model_rules::validate_model_specific_rules;
use super::required::{check_required_in_params, model_required_fields, non_empty_str};

struct ParsedParams {
    panel: PanelParams,
    linear: LinearParams,
    causal: CausalParams,
    ts: TimeSeriesParams,
    survey: SurveyParams,
    system: SystemParams,
    spatial: SpatialParams,
    duration: DurationParams,
    bayes: BayesParams,
    nonlinear: NonlinearParams,
    quantile: QuantileParams,
}

impl ParsedParams {
    fn load(spec: &ModelSpec) -> Result<Self, ValidationError> {
        Ok(Self {
            panel: parse_params(&spec.params, "INVALID_PANEL_PARAMS")?,
            linear: parse_params(&spec.params, "INVALID_LINEAR_PARAMS")?,
            causal: parse_params(&spec.params, "INVALID_CAUSAL_PARAMS")?,
            ts: parse_params(&spec.params, "INVALID_TIMESERIES_PARAMS")?,
            survey: parse_params(&spec.params, "INVALID_SURVEY_PARAMS")?,
            system: parse_params(&spec.params, "INVALID_SYSTEM_PARAMS")?,
            spatial: parse_params(&spec.params, "INVALID_SPATIAL_PARAMS")?,
            duration: parse_params(&spec.params, "INVALID_DURATION_PARAMS")?,
            bayes: parse_params(&spec.params, "INVALID_BAYES_PARAMS")?,
            nonlinear: parse_params(&spec.params, "INVALID_NONLINEAR_PARAMS")?,
            quantile: parse_params(&spec.params, "INVALID_QUANTILE_PARAMS")?,
        })
    }
}

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

fn into_validated(
    kind: &ModelSpecKind,
    spec: &ModelSpec,
    p: ParsedParams,
) -> Result<ValidatedModelParams, ValidationError> {
    Ok(match *kind {
        ModelSpecKind::Linear => ValidatedModelParams::Linear(p.linear),
        ModelSpecKind::IV => ValidatedModelParams::IV(p.linear),
        ModelSpecKind::GMM => ValidatedModelParams::Gmm(p.linear),
        ModelSpecKind::Panel => ValidatedModelParams::Panel(p.panel),
        ModelSpecKind::Causal => ValidatedModelParams::Causal(p.causal),
        ModelSpecKind::TimeSeries => ValidatedModelParams::TimeSeries(p.ts),
        ModelSpecKind::Survey => ValidatedModelParams::Survey(p.survey),
        ModelSpecKind::System => ValidatedModelParams::System(p.system),
        ModelSpecKind::Spatial => ValidatedModelParams::Spatial(p.spatial),
        ModelSpecKind::Duration => ValidatedModelParams::Duration(p.duration),
        ModelSpecKind::Bayes => ValidatedModelParams::Bayes(p.bayes),
        ModelSpecKind::Nonlinear => ValidatedModelParams::Nonlinear(p.nonlinear),
        ModelSpecKind::Quantile => ValidatedModelParams::Quantile(p.quantile),
        ModelSpecKind::Discrete => {
            let discrete: DiscreteParams = parse_params(&spec.params, "INVALID_DISCRETE_PARAMS")?;
            ValidatedModelParams::Discrete(discrete)
        }
    })
}

fn validate_impl(spec: &ModelSpec, kind: &ModelSpecKind) -> Result<ValidatedModelParams, ValidationError> {
    let mt = spec.model_type.as_str();
    let p = ParsedParams::load(spec)?;

    validate_panel_index(kind, &p.panel)?;

    let required = model_required_fields();
    let empty = vec![];
    let fields = required.get(mt).unwrap_or(&empty);
    check_required_in_params(
        mt, fields, &p.panel, &p.linear, &p.causal, &p.ts, &p.survey, &p.system, &p.spatial,
        &p.duration, &p.bayes,
    )?;

    validate_model_specific_rules(
        mt, &p.panel, &p.linear, &p.ts, &p.system, &p.spatial, &p.nonlinear, &p.quantile,
    )?;

    into_validated(kind, spec, p)
}

macro_rules! validate_kind_fn {
    ($name:ident, $variant:ident) => {
        pub(super) fn $name(spec: &ModelSpec) -> Result<ValidatedModelParams, ValidationError> {
            validate_impl(spec, &ModelSpecKind::$variant)
        }
    };
}

validate_kind_fn!(validate_linear, Linear);
validate_kind_fn!(validate_iv, IV);
validate_kind_fn!(validate_gmm, GMM);
validate_kind_fn!(validate_panel, Panel);
validate_kind_fn!(validate_causal, Causal);
validate_kind_fn!(validate_time_series, TimeSeries);
validate_kind_fn!(validate_survey, Survey);
validate_kind_fn!(validate_system, System);
validate_kind_fn!(validate_spatial, Spatial);
validate_kind_fn!(validate_duration, Duration);
validate_kind_fn!(validate_bayes, Bayes);
validate_kind_fn!(validate_nonlinear, Nonlinear);
validate_kind_fn!(validate_quantile, Quantile);
validate_kind_fn!(validate_discrete, Discrete);

pub(super) fn dispatch(spec: &ModelSpec) -> Result<ValidatedModelParams, ValidationError> {
    let kind = spec.kind()?;
    match kind {
        ModelSpecKind::Linear => validate_linear(spec),
        ModelSpecKind::IV => validate_iv(spec),
        ModelSpecKind::GMM => validate_gmm(spec),
        ModelSpecKind::Panel => validate_panel(spec),
        ModelSpecKind::Causal => validate_causal(spec),
        ModelSpecKind::TimeSeries => validate_time_series(spec),
        ModelSpecKind::Survey => validate_survey(spec),
        ModelSpecKind::System => validate_system(spec),
        ModelSpecKind::Spatial => validate_spatial(spec),
        ModelSpecKind::Duration => validate_duration(spec),
        ModelSpecKind::Bayes => validate_bayes(spec),
        ModelSpecKind::Nonlinear => validate_nonlinear(spec),
        ModelSpecKind::Quantile => validate_quantile(spec),
        ModelSpecKind::Discrete => validate_discrete(spec),
    }
}
