use std::collections::HashMap;

use crate::model_params::{
    parse_params, BayesParams, CausalParams, DiscreteParams, DurationParams, LinearParams,
    NonlinearParams, PanelParams, QuantileParams, SpatialParams, SurveyParams, SystemParams,
    TimeSeriesParams, ValidatedModelParams,
};
use crate::types::{ModelSpec, ModelSpecKind, TaskRequest, ValidationError};
use crate::resolve_working_dir;

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
        ("aipw", vec!["treatment_column", "outcome_column", "propensity_formula", "outcome_formula"]),
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

fn missing_field(model_type: &str, field: &str) -> ValidationError {
    ValidationError {
        code: "RUNTIME_MISSING_FIELD",
        message: format!("模型类型 `{model_type}` 需要 params 字段 `{field}`。"),
        hint: Some(format!("请在 model_spec.params 中提供 {field}。")),
    }
}

fn non_empty_str(opt: &Option<String>) -> bool {
    opt.as_ref().map(|s| !s.trim().is_empty()).unwrap_or(false)
}

fn non_empty_vec(opt: &Option<Vec<String>>) -> bool {
    opt.as_ref().map(|v| !v.is_empty()).unwrap_or(false)
}

#[allow(clippy::too_many_arguments)]
fn check_required_in_params(
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

    if matches!(kind, ModelSpecKind::Panel) {
        let pid_ok = non_empty_str(&panel.panel_id);
        let ptime_ok = non_empty_str(&panel.panel_time);
        if !pid_ok || !ptime_ok {
            return Err(ValidationError {
                code: "RUNTIME_PANEL_INDEX_REQUIRED",
                message: "panel 类模型需要同时提供非空的 panel_id 与 panel_time。".to_string(),
                hint: Some("请在 model_spec.params 中填写 panel_id 与 panel_time。".to_string()),
            });
        }
    }

    let required = model_required_fields();
    let empty = vec![];
    let fields = required.get(mt).unwrap_or(&empty);
    check_required_in_params(
        mt, fields, &panel, &linear, &causal, &ts, &survey, &system, &spatial, &duration, &bayes,
    )?;

    if mt == "gmm_linear" || mt == "dynamic_panel_gmm" {
        if let Some(ref w) = panel.gmm_weight.as_ref().or(linear.gmm_weight.as_ref()) {
            let t = w.trim().to_ascii_lowercase();
            if !t.is_empty()
                && t != "one_step"
                && t != "two_step"
                && t != "iterated"
                && t != "cue"
            {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: format!(
                        "模型类型 `{mt}` 的 gmm_weight 只能为 one_step / two_step / iterated / cue，收到 `{w}`。"
                    ),
                    hint: Some("请省略该字段以使用默认 two_step。".to_string()),
                });
            }
        }
    }

    if mt == "dynamic_panel_gmm" {
        if let Some(ref ds) = panel.dpgmm_style {
            let t = ds.trim().to_ascii_lowercase();
            if !t.is_empty() && t != "difference" && t != "system" {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: format!(
                        "模型类型 `dynamic_panel_gmm` 的 dpgmm_style 只能为 difference 或 system，收到 `{ds}`。"
                    ),
                    hint: Some("请使用 difference 或省略该字段。".to_string()),
                });
            }
        }
        if let Some(ref il) = panel.instrument_lags {
            if il.len() < 2 || il[0] > il[1] {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: "instrument_lags 必须为 [min_lag, max_lag] 且 min_lag ≤ max_lag。".to_string(),
                    hint: Some("例如 JSON 数组 [2, 4]。".to_string()),
                });
            }
        }
    }

    if matches!(mt, "sur" | "system_2sls" | "system_3sls") {
        if let Some(ref eqs) = system.equations {
            if eqs.len() > 8 {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: format!("模型类型 `{mt}` 的方程数至多 8 条，收到 {} 条。", eqs.len()),
                    hint: Some("请拆分模型或减少方程数。".to_string()),
                });
            }
        }
    }

    if matches!(mt, "system_2sls" | "system_3sls") {
        let g = system.equations.as_ref().map(|e| e.len()).unwrap_or(0);
        if let Some(ref se) = system.system_endogenous {
            if se.len() != g {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: format!(
                        "system_endogenous 外层长度（{}）须等于方程数（{}）。",
                        se.len(),
                        g
                    ),
                    hint: Some("请与 equations 数组对齐。".to_string()),
                });
            }
        }
        if let Some(ref si) = system.system_instruments {
            if si.len() != g {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: format!(
                        "system_instruments 外层长度（{}）须等于方程数（{}）。",
                        si.len(),
                        g
                    ),
                    hint: Some("请与 equations 数组对齐。".to_string()),
                });
            }
        }
    }

    let nonlinear: NonlinearParams = parse_params(&spec.params, "INVALID_NONLINEAR_PARAMS")?;
    let quantile: QuantileParams = parse_params(&spec.params, "INVALID_QUANTILE_PARAMS")?;

    if mt == "quantile" {
        let tau = quantile.quantile_tau.unwrap_or(0.5);
        const EPS: f64 = 1e-8;
        if !tau.is_finite() || tau <= EPS || tau >= 1.0 - EPS {
            return Err(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: format!(
                    "分位数回归要求 quantile_tau 为有限数且满足 {EPS} < τ < {}.",
                    1.0 - EPS
                ),
                hint: Some("请在 params 中设置 quantile_tau，例如 0.5。".to_string()),
            });
        }
    }

    if mt == "nls" {
        let start = nonlinear.nls_start.as_deref().unwrap_or(&[]);
        if start.len() != 3 || start.iter().any(|x| !x.is_finite()) {
            return Err(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: "nls 要求 nls_start 为长度 3 的有限浮点数组。".to_string(),
                hint: Some("请在 params 中设置 nls_start，例如 [1.0, 0.5, 0.05]。".to_string()),
            });
        }
        if let Some(ref fam) = nonlinear.nls_family {
            let t = fam.trim().to_ascii_lowercase();
            if !t.is_empty() && t != "exp_growth" {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: format!("首期 nls 仅支持 nls_family = exp_growth，收到 `{fam}`。"),
                    hint: Some("请省略 nls_family 或显式设为 exp_growth。".to_string()),
                });
            }
        }
    }

    if mt == "threshold" {
        let qv = nonlinear.threshold_variable.as_deref().unwrap_or("").trim();
        if qv.is_empty() {
            return Err(missing_field(mt, "threshold_variable"));
        }
        let g = nonlinear.threshold_grid.as_deref().unwrap_or(&[]);
        if g.len() < 2 || g.len() > 500 {
            return Err(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: format!("threshold_grid 长度须在 2–500 之间（单调递增），收到 {}。", g.len()),
                hint: Some("请使用已排序的等距网格或缩短点数。".to_string()),
            });
        }
        if g.iter().any(|x| !x.is_finite()) {
            return Err(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: "threshold_grid 元素须全为有限实数。".to_string(),
                hint: None,
            });
        }
        for i in 1..g.len() {
            if g[i] <= g[i - 1] {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: "threshold_grid 须按输入顺序严格递增。".to_string(),
                    hint: Some("请使用 grid(min max n) 在 CLI 端展开为单调数组。".to_string()),
                });
            }
        }
        if let Some(tf) = nonlinear.threshold_trim_frac {
            if !tf.is_finite() || !(0.0..0.45).contains(&tf) {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: "threshold_trim_frac 须为有限数且满足 0 ≤ trim < 0.45。".to_string(),
                    hint: Some("请省略以使用默认 0.1。".to_string()),
                });
            }
        }
    }

    if mt == "arch" {
        if ts.garch_p.is_some() || ts.garch_q.is_some() {
            return Err(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: "arch 模型不得同时提供 garch_p / garch_q。".to_string(),
                hint: Some("请仅使用 arch_order 指定 ARCH 阶数。".to_string()),
            });
        }
        let ao = ts.arch_order.unwrap_or(0);
        if !(1..=12).contains(&ao) {
            return Err(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: format!("arch_order 须为 1–12 的整数，收到 {ao}。"),
                hint: None,
            });
        }
    }

    if mt == "garch" {
        if ts.arch_order.is_some() {
            return Err(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: "garch 模型不得同时提供 arch_order。".to_string(),
                hint: Some("请改用 model_type=arch 或移除 arch_order。".to_string()),
            });
        }
        let p = ts.garch_p.unwrap_or(1);
        let q = ts.garch_q.unwrap_or(1);
        if p < 1 || q < 1 || p > 5 || q > 5 || p + q > 8 {
            return Err(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: format!("garch_p / garch_q 须满足 1≤p,q≤5 且 p+q≤8；收到 p={p}, q={q}。"),
                hint: Some("可省略两字段以使用默认 GARCH(1,1)。".to_string()),
            });
        }
    }

    if matches!(mt, "spatial_gwr" | "spatial_gtwr") {
        if let Some(ref coords) = spatial.spatial_coord_columns {
            if coords.len() != 2 {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: "spatial_coord_columns 必须是长度为 2 的数组。".to_string(),
                    hint: Some("如 [\"lon\", \"lat\"]。".to_string()),
                });
            }
        }
        if let Some(ref kern) = spatial.gwr_kernel {
            let k = kern.trim().to_ascii_lowercase();
            if k != "gaussian" && k != "bisquare" {
                return Err(ValidationError {
                    code: "RUNTIME_INVALID_FIELD",
                    message: format!("gwr_kernel 只能为 gaussian 或 bisquare，收到 `{kern}`。"),
                    hint: Some("请省略以使用默认 gaussian。".to_string()),
                });
            }
        }
        if spatial.gwr_bandwidth.is_some() && spatial.gwr_bandwidth_selection.is_some() {
            return Err(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: "gwr_bandwidth 与 gwr_bandwidth_selection 互斥。".to_string(),
                hint: Some("请只提供一个。".to_string()),
            });
        }
    }

    let validated = match kind {
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
    };

    Ok(validated)
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
