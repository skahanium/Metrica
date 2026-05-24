use crate::model_params::{
    LinearParams, NonlinearParams, PanelParams, QuantileParams, SpatialParams, SystemParams,
    TimeSeriesParams,
};
use crate::types::ValidationError;

use super::required::missing_field;

/// 各 model_type 的族专属校验（必填字段已在 `required` 中处理）。
#[allow(clippy::too_many_arguments)]
pub(super) fn validate_model_specific_rules(
    mt: &str,
    panel: &PanelParams,
    linear: &LinearParams,
    ts: &TimeSeriesParams,
    system: &SystemParams,
    spatial: &SpatialParams,
    nonlinear: &NonlinearParams,
    quantile: &QuantileParams,
) -> Result<(), ValidationError> {
    validate_gmm_panel(mt, panel, linear)?;
    validate_system_equations(mt, system)?;
    validate_quantile(mt, quantile)?;
    validate_nonlinear(mt, nonlinear)?;
    validate_timeseries_arch_garch(mt, ts)?;
    validate_spatial_gwr(mt, spatial)?;
    Ok(())
}

fn validate_gmm_panel(
    mt: &str,
    panel: &PanelParams,
    linear: &LinearParams,
) -> Result<(), ValidationError> {
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
    Ok(())
}

fn validate_system_equations(mt: &str, system: &SystemParams) -> Result<(), ValidationError> {
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
    Ok(())
}

fn validate_quantile(mt: &str, quantile: &QuantileParams) -> Result<(), ValidationError> {
    if mt != "quantile" {
        return Ok(());
    }
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
    Ok(())
}

fn validate_nonlinear(mt: &str, nonlinear: &NonlinearParams) -> Result<(), ValidationError> {
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
    Ok(())
}

fn validate_timeseries_arch_garch(mt: &str, ts: &TimeSeriesParams) -> Result<(), ValidationError> {
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
    Ok(())
}

fn validate_spatial_gwr(mt: &str, spatial: &SpatialParams) -> Result<(), ValidationError> {
    if !matches!(mt, "spatial_gwr" | "spatial_gtwr") {
        return Ok(());
    }
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
    Ok(())
}
