use std::collections::HashMap;

use crate::types::{ModelSpec, ModelSpecKind, TaskRequest, ValidationError};
use crate::resolve_working_dir;

/// 每个 model_type 的必填字段列表（不含 formula 和 dataset_path）。
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
        ("cointegration", vec!["variables", "time_column", "method"]),
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

/// 校验模型请求的必填字段和约束条件。
pub fn validate_model_request(spec: &ModelSpec) -> Option<ValidationError> {
    let kind = match spec.kind() {
        Ok(k) => k,
        Err(e) => return Some(e),
    };

    if kind == ModelSpecKind::Panel {
        let pid_ok = spec
            .panel_id
            .as_deref()
            .map(|s| !s.trim().is_empty())
            .unwrap_or(false);
        let ptime_ok = spec
            .panel_time
            .as_deref()
            .map(|s| !s.trim().is_empty())
            .unwrap_or(false);
        if !pid_ok || !ptime_ok {
            return Some(ValidationError {
                code: "RUNTIME_PANEL_INDEX_REQUIRED",
                message: "panel 类模型需要同时提供非空的 panel_id 与 panel_time。"
                    .to_string(),
                hint: Some("请在 model_spec 中填写 panel_id 与 panel_time。".to_string()),
            });
        }
    }

    let required = model_required_fields();
    let empty = vec![];
    let fields = required.get(spec.model_type.as_str()).unwrap_or(&empty);
    for field in fields {
                let value: Option<&str> = match *field {
                    "panel_id" => spec.panel_id.as_deref(),
                    "panel_time" => spec.panel_time.as_deref(),
                    "instruments" => spec.instruments.as_ref().map(|v| if v.is_empty() { "" } else { "present" }),
                    "endog_columns" => spec.endog_columns.as_ref().map(|v| if v.is_empty() { "" } else { "present" }),
                    "treatment_column" => spec.treatment_column.as_deref(),
                    "treated_column" => spec.treated_column.as_deref(),
                    "post_column" => spec.post_column.as_deref(),
                    "event_time_column" => spec.event_time_column.as_deref(),
                    "outcome_column" => spec.outcome_column.as_deref(),
                    "propensity_formula" => spec.propensity_formula.as_deref(),
                    "outcome_formula" => spec.outcome_formula.as_deref(),
                    "time_column" => spec.time_column.as_deref(),
                    "variable" => spec.variable.as_deref(),
                    "variables" => spec.variables.as_ref().map(|v| if v.is_empty() { "" } else { "present" }),
                    "order" => spec.order.as_ref().map(|v| if v.is_empty() { "" } else { "present" }),
                    "method" => spec.ts_method.as_deref(),
                    "lags" => spec.lags.map(|_| "present"),
                    "weights_column" => spec.weights_column.as_deref(),
                    "strata_column" => spec.strata_column.as_deref(),
                    "psu_column" => spec.psu_column.as_deref(),
                    "fpc_column" => spec.fpc_column.as_deref(),
                    "instrument_lags" => spec
                        .instrument_lags
                        .as_ref()
                        .map(|v| if v.len() >= 2 { "present" } else { "" }),
                    "arch_order" => spec.arch_order.map(|_| "present"),
                    "equations" => spec
                        .equations
                        .as_ref()
                        .map(|v| if v.is_empty() { "" } else { "present" }),
                    "system_endogenous" => spec
                        .system_endogenous
                        .as_ref()
                        .map(|v| if v.is_empty() { "" } else { "present" }),
                    "system_instruments" => spec
                        .system_instruments
                        .as_ref()
                        .map(|v| if v.is_empty() { "" } else { "present" }),
                    "spatial_weights_path" => spec.spatial_weights_path.as_deref(),
                    "spatial_id_column" => spec.spatial_id_column.as_deref(),
                    "spatial_coord_columns" => spec.spatial_coord_columns.as_ref().map(|v| if v.len() >= 2 { "present" } else { "" }),
                    "gtwr_time_column" => spec.gtwr_time_column.as_deref(),
                    "duration_time_column" => spec.duration_time_column.as_deref(),
                    "duration_event_column" => spec.duration_event_column.as_deref(),
                    "bayes_group_column" => spec.bayes_group_column.as_deref(),
                    _ => Some("present"),
                };
                match value {
                    Some(v) if !v.is_empty() => {}
                    _ => return Some(ValidationError {
                        code: "RUNTIME_MISSING_FIELD",
                        message: format!("模型类型 `{}` 需要字段 `{}`。", spec.model_type, field),
                        hint: Some(format!("请提供 {}。", field)),
                    }),
                }
            }
            if spec.model_type == "gmm_linear" || spec.model_type == "dynamic_panel_gmm" {
                if let Some(ref w) = spec.gmm_weight {
                    let t = w.trim().to_ascii_lowercase();
                    if !t.is_empty() && t != "one_step" && t != "two_step" && t != "iterated" && t != "cue" {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: format!(
                                "模型类型 `{}` 的 gmm_weight 只能为 one_step / two_step / iterated / cue，收到 `{w}`。",
                                spec.model_type
                            ),
                            hint: Some("请省略该字段以使用默认 two_step。".to_string()),
                        });
                    }
                }
            }
            if spec.model_type == "dynamic_panel_gmm" {
                if let Some(ref ds) = spec.dpgmm_style {
                    let t = ds.trim().to_ascii_lowercase();
                    if !t.is_empty() && t != "difference" && t != "system" {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: format!(
                                "模型类型 `dynamic_panel_gmm` 的 dpgmm_style 只能为 difference 或 system（首期仅实现 difference），收到 `{ds}`。"
                            ),
                            hint: Some("请使用 difference 或省略该字段。".to_string()),
                        });
                    }
                }
                if let Some(ref il) = spec.instrument_lags {
                    if il.len() < 2 || il[0] > il[1] {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: "instrument_lags 必须为 [min_lag, max_lag] 且 min_lag ≤ max_lag。"
                                .to_string(),
                            hint: Some("例如 JSON 数组 [2, 4]。".to_string()),
                        });
                    }
                }
            }
            if matches!(spec.model_type.as_str(), "sur" | "system_2sls" | "system_3sls") {
                if let Some(ref eqs) = spec.equations {
                    if eqs.len() > 8 {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: format!(
                                "模型类型 `{}` 的方程数至多 8 条，收到 {} 条。",
                                spec.model_type, eqs.len()
                            ),
                            hint: Some("请拆分模型或减少方程数。".to_string()),
                        });
                    }
                }
            }
            if matches!(spec.model_type.as_str(), "system_2sls" | "system_3sls") {
                let g = spec.equations.as_ref().map(|e| e.len()).unwrap_or(0);
                if let Some(ref se) = spec.system_endogenous {
                    if se.len() != g {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: format!("system_endogenous 外层长度（{}）须等于方程数（{}）。", se.len(), g),
                            hint: Some("请与 equations 数组对齐。".to_string()),
                        });
                    }
                }
                if let Some(ref si) = spec.system_instruments {
                    if si.len() != g {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: format!("system_instruments 外层长度（{}）须等于方程数（{}）。", si.len(), g),
                            hint: Some("请与 equations 数组对齐。".to_string()),
                        });
                    }
                }
            }
            if spec.model_type == "quantile" {
                let tau = spec.quantile_tau.unwrap_or(0.5);
                const EPS: f64 = 1e-8;
                if !tau.is_finite() || tau <= EPS || tau >= 1.0 - EPS {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: format!("分位数回归要求 quantile_tau 为有限数且满足 {EPS} < τ < {}.", 1.0 - EPS),
                        hint: Some("请在 model_spec 中设置 quantile_tau，例如 0.5。".to_string()),
                    });
                }
            }
            if spec.model_type == "nls" {
                let start = spec.nls_start.as_deref().unwrap_or(&[]);
                if start.len() != 3 || start.iter().any(|x| !x.is_finite()) {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: "nls 要求 nls_start 为长度 3 的有限浮点数组。".to_string(),
                        hint: Some("请在 model_spec 中设置 nls_start，例如 [1.0, 0.5, 0.05]。".to_string()),
                    });
                }
                if let Some(ref fam) = spec.nls_family {
                    let t = fam.trim().to_ascii_lowercase();
                    if !t.is_empty() && t != "exp_growth" {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: format!("首期 nls 仅支持 nls_family = exp_growth，收到 `{fam}`。"),
                            hint: Some("请省略 nls_family 或显式设为 exp_growth。".to_string()),
                        });
                    }
                }
            }
            if spec.model_type == "threshold" {
                let qv = spec.threshold_variable.as_deref().unwrap_or("").trim();
                if qv.is_empty() {
                    return Some(ValidationError {
                        code: "RUNTIME_MISSING_FIELD",
                        message: "门限回归需要非空的 threshold_variable（切换变量列名）。".to_string(),
                        hint: Some("请在 model_spec 中设置 threshold_variable。".to_string()),
                    });
                }
                let g = spec.threshold_grid.as_deref().unwrap_or(&[]);
                if g.len() < 2 || g.len() > 500 {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: format!("threshold_grid 长度须在 2–500 之间（单调递增），收到 {}。", g.len()),
                        hint: Some("请使用已排序的等距网格或缩短点数。".to_string()),
                    });
                }
                if g.iter().any(|x| !x.is_finite()) {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: "threshold_grid 元素须全为有限实数。".to_string(),
                        hint: None,
                    });
                }
                for i in 1..g.len() {
                    if g[i] <= g[i - 1] {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: "threshold_grid 须按输入顺序严格递增（不允许重复或乱序）。".to_string(),
                            hint: Some("请使用 grid(min max n) 在 CLI 端展开为单调数组。".to_string()),
                        });
                    }
                }
                if let Some(tf) = spec.threshold_trim_frac {
                    if !tf.is_finite() || !(0.0..0.45).contains(&tf) {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: "threshold_trim_frac 须为有限数且满足 0 ≤ trim < 0.45。".to_string(),
                            hint: Some("请省略以使用默认 0.1。".to_string()),
                        });
                    }
                }
            }
            if spec.model_type == "arch" {
                if spec.garch_p.is_some() || spec.garch_q.is_some() {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: "arch 模型不得同时提供 garch_p / garch_q。".to_string(),
                        hint: Some("请仅使用 arch_order 指定 ARCH 阶数。".to_string()),
                    });
                }
                let ao = spec.arch_order.unwrap_or(0);
                if ao < 1 || ao > 12 {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: format!("arch_order 须为 1–12 的整数，收到 {ao}。"),
                        hint: None,
                    });
                }
            }
            if spec.model_type == "garch" {
                if spec.arch_order.is_some() {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: "garch 模型不得同时提供 arch_order。".to_string(),
                        hint: Some("请改用 model_type=arch 或移除 arch_order。".to_string()),
                    });
                }
                let p = spec.garch_p.unwrap_or(1);
                let q = spec.garch_q.unwrap_or(1);
                if p < 1 || q < 1 || p > 5 || q > 5 || p + q > 8 {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: format!("garch_p / garch_q 须满足 1≤p,q≤5 且 p+q≤8；收到 p={p}, q={q}。"),
                        hint: Some("可省略两字段以使用默认 GARCH(1,1)。".to_string()),
                    });
                }
            }
            if matches!(spec.model_type.as_str(), "spatial_gwr" | "spatial_gtwr") {
                if let Some(ref coords) = spec.spatial_coord_columns {
                    if coords.len() != 2 {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: "spatial_coord_columns 必须是长度为 2 的数组。".to_string(),
                            hint: Some("如 [\"lon\", \"lat\"]。".to_string()),
                        });
                    }
                }
                if let Some(ref kern) = spec.gwr_kernel {
                    let k = kern.trim().to_ascii_lowercase();
                    if k != "gaussian" && k != "bisquare" {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: format!("gwr_kernel 只能为 gaussian 或 bisquare，收到 `{kern}`。"),
                            hint: Some("请省略以使用默认 gaussian。".to_string()),
                        });
                    }
                }
                if spec.gwr_bandwidth.is_some() && spec.gwr_bandwidth_selection.is_some() {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: "gwr_bandwidth 与 gwr_bandwidth_selection 互斥。".to_string(),
                        hint: Some("请只提供一个。".to_string()),
                    });
                }
            }
            None
}

/// 空间模型：校验权重边表文件在磁盘上存在。
pub fn validate_spatial_weights_on_disk(request: &TaskRequest) -> Option<ValidationError> {
    if !matches!(
        request.model_spec.model_type.as_str(),
        "spatial_lag" | "spatial_error" | "spatial_slx" |
        "spatial_sdm" | "spatial_sdem" | "spatial_sac" | "spatial_probit"
    ) {
        return None;
    }
    let wp = request
        .model_spec
        .spatial_weights_path
        .as_deref()
        .unwrap_or("")
        .trim();
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
            hint: Some("请检查 spatial_weights_path 与 project_context.working_dir。".to_string()),
        });
    }
    None
}
