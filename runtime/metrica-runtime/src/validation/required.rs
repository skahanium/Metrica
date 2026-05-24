use std::collections::HashMap;

use crate::model_params::{
    BayesParams, CausalParams, DurationParams, LinearParams, PanelParams, SpatialParams,
    SurveyParams, SystemParams, TimeSeriesParams,
};
use crate::types::ValidationError;

/// 每个 model_type 的必填字段列表（位于 `params` 对象内）。
pub fn model_required_fields() -> HashMap<&'static str, Vec<&'static str>> {
    HashMap::from([
        ("ols", vec![]),
        ("iv", vec!["instruments", "endog_columns"]),
        ("gmm_linear", vec!["instruments", "endog_columns"]),
        ("quantile", vec![]),
        ("nls", vec![]),
        ("threshold", vec![]),
        ("gls", vec![]),
        ("panel", vec!["panel_id", "panel_time"]),
        ("panel_iv", vec!["panel_id", "panel_time", "instruments", "endog_columns"]),
        ("dynamic_panel_gmm", vec!["panel_id", "panel_time", "instrument_lags"]),
        ("logit", vec![]),
        ("probit", vec![]),
        ("poisson", vec![]),
        ("ordered_logit", vec![]),
        ("multinomial_logit", vec![]),
        ("negbin", vec![]),
        ("did", vec!["panel_id", "panel_time", "treated_column", "post_column"]),
        ("event_study", vec!["panel_id", "panel_time", "treated_column", "post_column"]),
        ("ipw", vec!["treatment_column", "outcome_column", "propensity_formula"]),
        ("psm", vec!["treatment_column", "outcome_column", "propensity_formula"]),
        ("aipw", vec![
            "treatment_column",
            "outcome_column",
            "propensity_formula",
            "outcome_formula",
        ]),
        ("arima", vec!["variable", "time_column", "order"]),
        ("var", vec!["variables", "time_column", "lags"]),
        ("unitroot", vec!["variable", "time_column"]),
        ("cointegration", vec!["variables", "time_column", "ts_method"]),
        ("arch", vec!["variable", "time_column", "arch_order"]),
        ("garch", vec!["variable", "time_column"]),
        ("gjr_garch", vec!["variable", "time_column"]),
        ("egarch", vec!["variable", "time_column"]),
        ("survey_ols", vec!["weights_column"]),
        ("survey_logit", vec!["weights_column"]),
        ("survey_probit", vec!["weights_column"]),
        ("survey_poisson", vec!["weights_column"]),
        ("sur", vec!["equations"]),
        ("system_2sls", vec!["equations", "system_endogenous", "system_instruments"]),
        ("system_3sls", vec!["equations", "system_endogenous", "system_instruments"]),
        ("spatial_lag", vec!["spatial_weights_path", "spatial_id_column"]),
        ("spatial_error", vec!["spatial_weights_path", "spatial_id_column"]),
        ("spatial_slx", vec!["spatial_weights_path", "spatial_id_column"]),
        ("spatial_sdm", vec!["spatial_weights_path", "spatial_id_column"]),
        ("spatial_sdem", vec!["spatial_weights_path", "spatial_id_column"]),
        ("spatial_sac", vec!["spatial_weights_path", "spatial_id_column"]),
        ("spatial_gwr", vec!["spatial_coord_columns"]),
        ("spatial_gtwr", vec!["spatial_coord_columns", "gtwr_time_column"]),
        ("spatial_probit", vec!["spatial_weights_path", "spatial_id_column"]),
        ("duration_cox", vec!["duration_time_column", "duration_event_column"]),
        ("bayes_linear", vec![]),
        ("bayes_logistic", vec![]),
        ("bayes_probit", vec![]),
        ("bayes_hierarchical", vec!["bayes_group_column"]),
        ("aft_weibull", vec!["duration_time_column", "duration_event_column"]),
        ("aft_exponential", vec!["duration_time_column", "duration_event_column"]),
        ("aft_lognormal", vec!["duration_time_column", "duration_event_column"]),
        ("aft_loglogistic", vec!["duration_time_column", "duration_event_column"]),
    ])
}

pub(super) fn missing_field(model_type: &str, field: &str) -> ValidationError {
    ValidationError {
        code: "RUNTIME_MISSING_FIELD",
        message: format!("模型类型 `{model_type}` 需要 params 字段 `{field}`。"),
        hint: Some(format!("请在 model_spec.params 中提供 {field}。")),
    }
}

pub(super) fn non_empty_str(opt: &Option<String>) -> bool {
    opt.as_ref().map(|s| !s.trim().is_empty()).unwrap_or(false)
}

fn non_empty_vec(opt: &Option<Vec<String>>) -> bool {
    opt.as_ref().map(|v| !v.is_empty()).unwrap_or(false)
}

#[allow(clippy::too_many_arguments)]
pub(super) fn check_required_in_params(
    model_type: &str,
    fields: &[&str],
    panel: &PanelParams,
    linear: &LinearParams,
    causal: &CausalParams,
    ts: &TimeSeriesParams,
    survey: &SurveyParams,
    system: &SystemParams,
    spatial: &SpatialParams,
    duration: &DurationParams,
    bayes: &BayesParams,
) -> Result<(), ValidationError> {
    for field in fields {
        let ok = match *field {
            "panel_id" => non_empty_str(&panel.panel_id),
            "panel_time" => non_empty_str(&panel.panel_time),
            "instruments" => {
                non_empty_vec(&linear.instruments) || non_empty_vec(&panel.instruments)
            }
            "endog_columns" => {
                non_empty_vec(&linear.endog_columns) || non_empty_vec(&panel.endog_columns)
            }
            "treatment_column" => non_empty_str(&causal.treatment_column),
            "treated_column" => non_empty_str(&causal.treated_column),
            "post_column" => non_empty_str(&causal.post_column),
            "event_time_column" => non_empty_str(&causal.event_time_column),
            "outcome_column" => non_empty_str(&causal.outcome_column),
            "propensity_formula" => non_empty_str(&causal.propensity_formula),
            "outcome_formula" => non_empty_str(&causal.outcome_formula),
            "time_column" => non_empty_str(&ts.time_column),
            "variable" => non_empty_str(&ts.variable),
            "variables" => non_empty_vec(&ts.variables),
            "order" => ts.order.as_ref().map(|v| !v.is_empty()).unwrap_or(false),
            "ts_method" => non_empty_str(&ts.ts_method),
            "lags" => ts.lags.is_some(),
            "weights_column" => non_empty_str(&survey.weights_column),
            "instrument_lags" => panel
                .instrument_lags
                .as_ref()
                .map(|v| v.len() >= 2)
                .unwrap_or(false),
            "arch_order" => ts.arch_order.is_some(),
            "equations" => non_empty_vec(&system.equations),
            "system_endogenous" => system
                .system_endogenous
                .as_ref()
                .map(|v| !v.is_empty())
                .unwrap_or(false),
            "system_instruments" => system
                .system_instruments
                .as_ref()
                .map(|v| !v.is_empty())
                .unwrap_or(false),
            "spatial_weights_path" => non_empty_str(&spatial.spatial_weights_path),
            "spatial_id_column" => non_empty_str(&spatial.spatial_id_column),
            "spatial_coord_columns" => spatial
                .spatial_coord_columns
                .as_ref()
                .map(|v| v.len() >= 2)
                .unwrap_or(false),
            "gtwr_time_column" => non_empty_str(&spatial.gtwr_time_column),
            "duration_time_column" => non_empty_str(&duration.duration_time_column),
            "duration_event_column" => non_empty_str(&duration.duration_event_column),
            "bayes_group_column" => non_empty_str(&bayes.bayes_group_column),
            _ => true,
        };
        if !ok {
            return Err(missing_field(model_type, field));
        }
    }
    Ok(())
}
