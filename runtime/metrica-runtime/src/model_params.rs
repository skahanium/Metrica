//! Per-model-family parameter structs and validated dispatch payloads.

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::types::{ModelSpec, ValidationError};

// === Family parameter structs ===================================================

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LinearParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instruments: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub endog_columns: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gmm_weight: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PanelParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_method: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instruments: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub endog_columns: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gmm_weight: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dpgmm_style: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instrument_lags: Option<Vec<i32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub collapse_instruments: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub omega_spec: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub treated_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub post_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub event_time_column: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CausalParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub treatment_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub treated_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub post_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub event_time_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub outcome_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub propensity_formula: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub outcome_formula: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TimeSeriesParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub time_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variable: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variables: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order: Option<Vec<i32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub seasonal_order: Option<Vec<i32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ts_method: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lags: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deterministic: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arch_order: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_p: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_q: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_max_iter: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_tol: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SurveyParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub weights_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub strata_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub psu_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fpc_column: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SystemParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub equations: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system_endogenous: Option<Vec<Vec<String>>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system_instruments: Option<Vec<Vec<String>>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sur_max_iter: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sur_tol: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SpatialParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_weights_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_id_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_row_standardize: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_coord_columns: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_distance: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_crs: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_kernel: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_bandwidth: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_bandwidth_selection: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_adaptive: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gtwr_time_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gtwr_time_scale: Option<Value>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DurationParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_time_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_event_column: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct BayesParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_seed: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_prior_scale: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_iter: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_warmup: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_chains: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bayes_group_column: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct NonlinearParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_family: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_start: Option<Vec<f64>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_max_iter: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_tol: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold_variable: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold_grid: Option<Vec<f64>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold_trim_frac: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct QuantileParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quantile_tau: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DiscreteParams {}

// === Validated payload ==========================================================

#[derive(Debug, Clone)]
pub enum ValidatedModelParams {
    Linear(LinearParams),
    IV(LinearParams),
    Gmm(LinearParams),
    Panel(PanelParams),
    Causal(CausalParams),
    TimeSeries(TimeSeriesParams),
    Survey(SurveyParams),
    System(SystemParams),
    Spatial(SpatialParams),
    Duration(DurationParams),
    Bayes(BayesParams),
    Nonlinear(NonlinearParams),
    Quantile(QuantileParams),
    Discrete(DiscreteParams),
}

pub fn parse_params<T: for<'de> Deserialize<'de>>(
    raw: &Value,
    code: &'static str,
) -> Result<T, ValidationError> {
    serde_json::from_value(raw.clone()).map_err(|e| ValidationError {
        code,
        message: format!("params 字段解析失败: {e}"),
        hint: Some("请检查 model_spec.params 是否为该模型族的有效 JSON 对象。".to_string()),
    })
}

/// Flatten nested `ModelSpec` into a single JSON object for legacy Julia bridge scripts.
pub fn flatten_model_spec_for_julia(spec: &ModelSpec) -> Value {
    let mut map = Map::new();
    map.insert("model_type".to_string(), Value::String(spec.model_type.clone()));
    map.insert("formula".to_string(), Value::String(spec.formula.clone()));
    if let Some(ref v) = spec.vcov {
        map.insert(
            "vcov".to_string(),
            serde_json::json!({ "type": v.kind }),
        );
    }
    if let Some(ref w) = spec.weights {
        map.insert("weights".to_string(), Value::String(w.clone()));
    }
    if let Some(ref c) = spec.cluster_column {
        map.insert("cluster_column".to_string(), Value::String(c.clone()));
    }
    merge_value_into_map(&mut map, spec.params.clone());
    Value::Object(map)
}

pub fn merge_value_into_map(target: &mut Map<String, Value>, value: Value) {
    if let Value::Object(map) = value {
        for (k, v) in map {
            if !v.is_null() {
                target.insert(k, v);
            }
        }
    }
}

impl ValidatedModelParams {
    /// Merge family-specific fields into the flat Julia request object.
    pub fn merge_into_flat(&self, target: &mut Map<String, Value>) {
        let value = match self {
            ValidatedModelParams::Linear(p)
            | ValidatedModelParams::IV(p)
            | ValidatedModelParams::Gmm(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::Panel(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::Causal(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::TimeSeries(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::Survey(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::System(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::Spatial(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::Duration(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::Bayes(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::Nonlinear(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::Quantile(p) => serde_json::to_value(p).unwrap_or(Value::Null),
            ValidatedModelParams::Discrete(p) => serde_json::to_value(p).unwrap_or(Value::Null),
        };
        merge_value_into_map(target, value);
    }

    pub fn spatial_weights_path(&self) -> Option<&str> {
        match self {
            ValidatedModelParams::Spatial(p) => p
                .spatial_weights_path
                .as_deref()
                .map(|s| s.trim())
                .filter(|s| !s.is_empty()),
            _ => None,
        }
    }
}
