pub mod julia_bridge;
pub mod julia_session;
pub mod server;

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub use server::default_bind_addr;
pub use julia_session::JuliaSession;
pub use server::{build_router, serve as serve_axum, AppState};

/// 解析仓库根目录。

/// 模型请求的校验错误，由共享校验函数返回。
/// 调用方（server / julia_bridge）负责将其转换为各自协议的响应格式。
#[derive(Debug, Clone)]
pub struct ValidationError {
    pub code: &'static str,
    pub message: String,
    pub hint: Option<String>,
}

// === 共享路径解析 =============================================================

/// 将相对工作目录解析为绝对路径。
pub fn resolve_working_dir(raw_working_dir: &str) -> std::path::PathBuf {
    let working_dir = std::path::PathBuf::from(raw_working_dir);
    if working_dir.is_absolute() {
        return working_dir;
    }
    repo_root().join(working_dir)
}

/// 将数据集相对路径解析为绝对路径字符串。
pub fn resolve_dataset_path(raw_path: &str, working_dir: &std::path::PathBuf) -> String {
    let dataset_path = std::path::PathBuf::from(raw_path);
    if dataset_path.is_absolute() {
        return dataset_path.to_string_lossy().to_string();
    }
    working_dir.join(dataset_path).to_string_lossy().to_string()
}

// === 共享模型校验 =============================================================

/// 每个 model_type 的必填字段列表（不含 formula 和 dataset_path）。
fn model_required_fields() -> HashMap<&'static str, Vec<&'static str>> {
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
        // S4c: TimeSeries 模型
        ("arima", vec!["variable", "time_column", "order"]),
        ("var", vec!["variables", "time_column", "lags"]),
        ("unitroot", vec!["variable", "time_column"]),
        ("cointegration", vec!["variables", "time_column", "method"]),
        ("arch", vec!["variable", "time_column", "arch_order"]),
        ("garch", vec!["variable", "time_column"]),
        ("gjr_garch", vec!["variable", "time_column"]),
        ("egarch", vec!["variable", "time_column"]),
        // S4d: Survey 模型
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
    ])
}

/// 校验：model_type 是否在已知注册表中，且必填字段非空。
pub fn validate_model_request(spec: &ModelSpec) -> Option<ValidationError> {
    // panel 族模型：索引字段缺失时统一错误码，便于 CLI / 测试与文档对齐。
    if matches!(
        spec.model_type.as_str(),
        "panel" | "panel_iv" | "dynamic_panel_gmm" | "did" | "event_study"
    ) {
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
    match required.get(spec.model_type.as_str()) {
        None => Some(ValidationError {
            code: "RUNTIME_UNSUPPORTED_MODEL_TYPE",
            message: format!(
                "runtime 当前支持的模型类型：{}。收到 `{}`。",
                required.keys().cloned().collect::<Vec<_>>().join("、"),
                spec.model_type,
            ),
            hint: Some("请选择支持的模型类型。".to_string()),
        }),
        Some(fields) => {
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
                    // S4c: TimeSeries 字段
                    "time_column" => spec.time_column.as_deref(),
                    "variable" => spec.variable.as_deref(),
                    "variables" => spec.variables.as_ref().map(|v| if v.is_empty() { "" } else { "present" }),
                    "order" => spec.order.as_ref().map(|v| if v.is_empty() { "" } else { "present" }),
                    "method" => spec.ts_method.as_deref(),
                    "lags" => spec.lags.map(|_| "present"),
                    // S4d: Survey 字段
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
                    if !t.is_empty() && t != "one_step" && t != "two_step" {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: format!(
                                "模型类型 `{}` 的 gmm_weight 只能为 one_step 或 two_step，收到 `{w}`。",
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
            if matches!(
                spec.model_type.as_str(),
                "sur" | "system_2sls" | "system_3sls"
            ) {
                if let Some(ref eqs) = spec.equations {
                    if eqs.len() > 8 {
                        return Some(ValidationError {
                            code: "RUNTIME_INVALID_FIELD",
                            message: format!(
                                "模型类型 `{}` 的方程数至多 8 条，收到 {} 条。",
                                spec.model_type,
                                eqs.len()
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
                            message: format!(
                                "system_endogenous 外层长度（{}）须等于方程数（{}）。",
                                se.len(),
                                g
                            ),
                            hint: Some("请与 equations 数组对齐。".to_string()),
                        });
                    }
                }
                if let Some(ref si) = spec.system_instruments {
                    if si.len() != g {
                        return Some(ValidationError {
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
            if spec.model_type == "quantile" {
                let tau = spec.quantile_tau.unwrap_or(0.5);
                const EPS: f64 = 1e-8;
                if !tau.is_finite() || tau <= EPS || tau >= 1.0 - EPS {
                    return Some(ValidationError {
                        code: "RUNTIME_INVALID_FIELD",
                        message: format!(
                            "分位数回归要求 quantile_tau 为有限数且满足 {EPS} < τ < {}。",
                            1.0 - EPS
                        ),
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
                        message: format!(
                            "threshold_grid 长度须在 2–500 之间（单调递增），收到 {}。",
                            g.len()
                        ),
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
                        message: format!(
                            "garch_p / garch_q 须满足 1≤p,q≤5 且 p+q≤8；收到 p={p}, q={q}。"
                        ),
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
    }
}

/// 空间模型：校验权重边表文件在磁盘上存在（相对 `working_dir` 解析）。
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

// === 标准化常量 ===============================================================

/// 支持的 action 类型常量，避免字符串字面量散落各处。
pub mod actions {
    pub const FIT_MODEL: &str = "fit_model";
    pub const INSPECT_DATASET: &str = "inspect_dataset";
    pub const QUERY_DATASET: &str = "query_dataset";
    pub const TRANSFORM: &str = "transform";
    pub const EXPORT_REPORT: &str = "export_report";
    pub const SAVE_PROJECT: &str = "save_project";
    pub const LOAD_PROJECT: &str = "load_project";
    pub const LIST_RUNS: &str = "list_runs";
    pub const RERUN_TASK: &str = "rerun_task";
    pub const RUN_DIAGNOSTIC: &str = "run_diagnostic";
}

// === Julia 响应解析 ===========================================================

/// Julia 返回的标准化响应信封，避免各处重复解析 `"status"`、`"messages"` 等 key。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct JuliaResponse {
    pub status: String,
    #[serde(default)]
    pub messages: Vec<Message>,
    #[serde(default)]
    pub result_payload: Option<serde_json::Value>,
}

impl JuliaResponse {
    /// 从 Julia 返回的 JSON 字符串解析响应信封。
    pub fn from_json(raw: &str) -> Result<Self, String> {
        serde_json::from_str::<JuliaResponse>(raw)
            .map_err(|e| format!("解析 Julia 响应失败: {e}"))
    }

    /// 从响应中提取 content 字段（用于导出场景）。
    pub fn content(&self) -> &str {
        self.result_payload
            .as_ref()
            .and_then(|v| v.get("content"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
    }
}

/// 解析仓库根目录。
///
/// 基于 `CARGO_MANIFEST_DIR`（`runtime/metrica-runtime`）向上两级到仓库根。
pub fn repo_root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .map(|p| p.to_path_buf())
        .unwrap_or_default()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectContext {
    pub project_id: String,
    pub working_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatasetRef {
    pub source: String,
    pub path: String,
    pub format: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcovSpec {
    #[serde(rename = "type")]
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelSpec {
    pub model_type: String,
    pub formula: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub vcov: Option<VcovSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub weights: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cluster_column: Option<String>,
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
    /// `gmm_linear` / `dynamic_panel_gmm`：`one_step` 或 `two_step`（默认 `two_step`）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gmm_weight: Option<String>,
    /// 仅 `dynamic_panel_gmm`：首期仅 `difference`；`system` 预留二期。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dpgmm_style: Option<String>,
    /// 仅 `dynamic_panel_gmm`：工具滞后层 `[min_lag, max_lag]`，与 CLI `lags(2 4)` 对齐。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instrument_lags: Option<Vec<i32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub collapse_instruments: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub omega_spec: Option<String>,
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
    pub weights_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub strata_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub psu_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fpc_column: Option<String>,
    /// `sur` / `system_2sls` / `system_3sls`：各方程公式字符串数组（至多 8 条）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub equations: Option<Vec<String>>,
    /// `system_2sls` / `system_3sls`：按方程分组的内生变量名。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system_endogenous: Option<Vec<Vec<String>>>,
    /// `system_2sls` / `system_3sls`：按方程分组的外生工具列名。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system_instruments: Option<Vec<Vec<String>>>,
    /// 仅 `sur`：FGLS 最大迭代次数（默认 5）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sur_max_iter: Option<i32>,
    /// 仅 `sur`：系数变化收敛阈值（默认 1e-6）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sur_tol: Option<f64>,
    /// 仅 `quantile`：单分位点 τ；JSON 省略时 Julia 端按 0.5 处理，Runtime 仍要求落在开区间 (0,1)。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quantile_tau: Option<f64>,
    /// 仅 `nls`：白名单族（首期仅 `exp_growth`）；省略时 Julia 端按 exp_growth 处理。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_family: Option<String>,
    /// 仅 `nls`：初值向量，长度须为 3。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_start: Option<Vec<f64>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_max_iter: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nls_tol: Option<f64>,
    /// 仅 `threshold`：切换变量列名。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold_variable: Option<String>,
    /// 仅 `threshold`：候选门限 γ 网格（严格递增，长度 2–500）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold_grid: Option<Vec<f64>>,
    /// 仅 `threshold`：q 上修剪比例，默认 0.1。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threshold_trim_frac: Option<f64>,
    /// 仅 `arch`：ARCH 阶 q（1–12）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub arch_order: Option<i32>,
    /// 仅 `garch`：ARCH 项阶 p（默认 1，上界 5）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_p: Option<i32>,
    /// 仅 `garch`：GARCH 项阶 q（默认 1，上界 5，且 p+q≤8）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_q: Option<i32>,
    /// `arch` / `garch`：优化最大迭代次数。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_max_iter: Option<i32>,
    /// `arch` / `garch`：优化 f_reltol。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub garch_tol: Option<f64>,
    /// `spatial_lag` / `spatial_error`：边表 CSV 路径（相对 `working_dir` 或绝对路径）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_weights_path: Option<String>,
    /// 主数据中与边表 `id_i`/`id_j` 对齐的列名。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_id_column: Option<String>,
    /// 是否对 \(W\) 行标准化；默认 `true`（省略时 Julia 端按 true 处理）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_row_standardize: Option<bool>,
    /// GWR/GTWR: 坐标列名数组，如 ["lon", "lat"]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_coord_columns: Option<Vec<String>>,
    /// 距离度量: euclidean / haversine / projected
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_distance: Option<String>,
    /// 坐标参考系（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spatial_crs: Option<String>,
    /// GWR 核函数: gaussian / bisquare
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_kernel: Option<String>,
    /// GWR 带宽（数值），与 bandwidth_selection 互斥
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_bandwidth: Option<f64>,
    /// GWR 带宽选择: cv / aicc
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_bandwidth_selection: Option<String>,
    /// 自适应带宽（邻近点数）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gwr_adaptive: Option<bool>,
    /// GTWR 时间列名
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gtwr_time_column: Option<String>,
    /// GTWR 时间尺度（数或 "auto"）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gtwr_time_scale: Option<serde_json::Value>,
    /// `duration_cox`：生存/随访时间列名（须为正有限实数）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_time_column: Option<String>,
    /// `duration_cox`：事件指示列名（0=删失，1=事件；亦支持布尔列）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_event_column: Option<String>,
}

// === 模型族类型（从 ModelSpec 转换，提供类型安全访问）=============================

/// 线性模型族字段（OLS、GLS）。
#[derive(Debug, Clone)]
pub struct LinearSpec {
    pub formula: String,
    pub vcov: Option<VcovSpec>,
    pub weights: Option<String>,
    pub cluster_column: Option<String>,
}

/// IV/2SLS 模型族字段。
#[derive(Debug, Clone)]
pub struct IVSpec {
    pub formula: String,
    pub vcov: Option<VcovSpec>,
    pub instruments: Vec<String>,
    pub endog_columns: Vec<String>,
    pub weights: Option<String>,
    pub cluster_column: Option<String>,
}

/// 面板模型族字段。
#[derive(Debug, Clone)]
pub struct PanelSpec {
    pub formula: String,
    pub panel_id: String,
    pub panel_time: String,
    pub panel_method: Option<String>,
    pub vcov: Option<VcovSpec>,
    pub weights: Option<String>,
}

/// 因果推断模型族字段。
#[derive(Debug, Clone)]
pub struct CausalSpec {
    pub treatment_column: String,
    pub outcome_column: String,
    pub propensity_formula: String,
    pub outcome_formula: Option<String>,
}

/// 时间序列模型族字段。
#[derive(Debug, Clone)]
pub struct TimeSeriesSpec {
    pub time_column: String,
    pub variable: Option<String>,
    pub variables: Option<Vec<String>>,
    pub order: Option<Vec<i32>>,
    pub seasonal_order: Option<Vec<i32>>,
    pub ts_method: Option<String>,
    pub lags: Option<i32>,
    pub deterministic: Option<String>,
}

/// 调查模型族字段。
#[derive(Debug, Clone)]
pub struct SurveySpec {
    pub formula: String,
    pub weights_column: String,
    pub strata_column: Option<String>,
    pub psu_column: Option<String>,
    pub fpc_column: Option<String>,
}

impl ModelSpec {
    /// 提取为线性模型字段（OLS/GLS 共用）。
    pub fn to_linear(&self) -> Result<LinearSpec, ValidationError> {
        Ok(LinearSpec {
            formula: self.formula.clone(),
            vcov: self.vcov.clone(),
            weights: self.weights.clone(),
            cluster_column: self.cluster_column.clone(),
        })
    }

    /// 提取为 IV 模型字段。
    pub fn to_iv(&self) -> Result<IVSpec, ValidationError> {
        Ok(IVSpec {
            formula: self.formula.clone(),
            vcov: self.vcov.clone(),
            instruments: self.instruments.clone().unwrap_or_default(),
            endog_columns: self.endog_columns.clone().unwrap_or_default(),
            weights: self.weights.clone(),
            cluster_column: self.cluster_column.clone(),
        })
    }

    /// 提取为面板模型字段。
    pub fn to_panel(&self) -> Result<PanelSpec, ValidationError> {
        Ok(PanelSpec {
            formula: self.formula.clone(),
            panel_id: self.panel_id.clone().ok_or_else(|| missing_field("panel_id"))?,
            panel_time: self.panel_time.clone().ok_or_else(|| missing_field("panel_time"))?,
            panel_method: self.panel_method.clone(),
            vcov: self.vcov.clone(),
            weights: self.weights.clone(),
        })
    }

    /// 提取为因果推断模型字段。
    pub fn to_causal(&self) -> Result<CausalSpec, ValidationError> {
        Ok(CausalSpec {
            treatment_column: self.treatment_column.clone().ok_or_else(|| missing_field("treatment_column"))?,
            outcome_column: self.outcome_column.clone().ok_or_else(|| missing_field("outcome_column"))?,
            propensity_formula: self.propensity_formula.clone().ok_or_else(|| missing_field("propensity_formula"))?,
            outcome_formula: self.outcome_formula.clone(),
        })
    }

    /// 提取为时间序列模型字段。
    pub fn to_time_series(&self) -> Result<TimeSeriesSpec, ValidationError> {
        Ok(TimeSeriesSpec {
            time_column: self.time_column.clone().ok_or_else(|| missing_field("time_column"))?,
            variable: self.variable.clone(),
            variables: self.variables.clone(),
            order: self.order.clone(),
            seasonal_order: self.seasonal_order.clone(),
            ts_method: self.ts_method.clone(),
            lags: self.lags,
            deterministic: self.deterministic.clone(),
        })
    }

    /// 提取为调查模型字段。
    pub fn to_survey(&self) -> Result<SurveySpec, ValidationError> {
        Ok(SurveySpec {
            formula: self.formula.clone(),
            weights_column: self.weights_column.clone().ok_or_else(|| missing_field("weights_column"))?,
            strata_column: self.strata_column.clone(),
            psu_column: self.psu_column.clone(),
            fpc_column: self.fpc_column.clone(),
        })
    }
}

fn missing_field(name: &'static str) -> ValidationError {
    ValidationError {
        code: "RUNTIME_MISSING_FIELD",
        message: format!("模型需要字段 `{}`。", name),
        hint: Some(format!("请提供 {}。", name)),
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestOptions {
    pub drop_missing: bool,
    pub return_augment: bool,
    #[serde(default = "default_inspect_preview_rows")]
    pub preview_rows: usize,
}

fn default_inspect_preview_rows() -> usize {
    5
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub dataset_ref: DatasetRef,
    pub model_spec: ModelSpec,
    pub options: RequestOptions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiagnosticRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub dataset_ref: DatasetRef,
    pub model_spec: ModelSpec,
    pub diagnostic: DiagnosticSpec,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiagnosticSpec {
    pub test: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lags: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataCommand {
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variables: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataCommandRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub dataset_ref: DatasetRef,
    pub command: DataCommand,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformOptions {
    #[serde(default = "default_transform_preview_rows")]
    pub preview_rows: usize,
    #[serde(default = "default_transform_persist_output")]
    pub persist_output: bool,
}

impl Default for TransformOptions {
    fn default() -> Self {
        Self {
            preview_rows: default_transform_preview_rows(),
            persist_output: default_transform_persist_output(),
        }
    }
}

fn default_transform_preview_rows() -> usize {
    10
}

fn default_transform_persist_output() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformTaskRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub dataset_ref: DatasetRef,
    pub operations: Vec<TransformOperation>,
    #[serde(default)]
    pub options: TransformOptions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub level: String,
    pub code: String,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskResponse {
    pub task_id: String,
    pub status: String,
    pub messages: Vec<Message>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artifacts: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub run_record: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_payload: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataLineage {
    pub source_dataset: String,
    pub active_dataset: String,
    pub operations: Vec<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub row_count_before: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub row_count_after: Option<usize>,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectManifest {
    pub project_id: String,
    pub version: u32,
    pub created_at: String,
    pub updated_at: String,
    pub source_dataset: String,
    pub active_dataset: String,
    pub saved_model_specs: Vec<ModelSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_run_id: Option<String>,
    #[serde(default)]
    pub ui_state: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data_lineage: Option<DataLineage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunRecord {
    pub run_id: String,
    pub action: String,
    pub started_at: String,
    pub finished_at: String,
    pub status: String,
    pub dataset_ref: DatasetRef,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model_spec: Option<ModelSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub operations: Option<Vec<TransformOperation>>,
    #[serde(default)]
    pub warnings: Vec<Value>,
    #[serde(default)]
    pub messages: Vec<Message>,
    #[serde(default)]
    pub artifacts: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_summary: Option<Value>,
    pub request_payload: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SaveProjectRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub manifest: ProjectManifest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadProjectRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListRunsRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub offset: Option<usize>,
    #[serde(default)]
    pub action_filter: Option<String>,
    #[serde(default)]
    pub status_filter: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RerunTaskRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub run_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportReportRequest {
    pub task_id: String,
    pub action: String,
    pub project_context: ProjectContext,
    pub run_id: String,
    pub format: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct HealthSummary {
    pub service: String,
    pub status: String,
    pub supported_actions: Vec<&'static str>,
}

/// 解析示例 demo 目录。
///
/// 优先读取环境变量 `METRICA_DEMO_DIR`；若未设置，则基于仓库根
/// 拼接 `apps/metrica-desktop` 作为默认路径。
fn default_demo_dir() -> String {
    if let Ok(path) = std::env::var("METRICA_DEMO_DIR") {
        return path;
    }

    repo_root()
        .join("datasets")
        .join("demo")
        .to_string_lossy()
        .to_string()
}

/// 解析示例 demo CSV 路径。
///
/// 优先读取环境变量 `METRICA_DEMO_CSV`；若未设置，则在 `default_demo_dir()`
/// 中查找 `ols_demo.csv`。
fn default_demo_csv() -> String {
    if let Ok(path) = std::env::var("METRICA_DEMO_CSV") {
        return path;
    }

    std::path::PathBuf::from(default_demo_dir())
        .join("ols_demo.csv")
        .to_string_lossy()
        .to_string()
}

fn sample_request_base(action: &str, task_id: &str) -> TaskRequest {
    TaskRequest {
        task_id: task_id.to_string(),
        action: action.to_string(),
        project_context: ProjectContext {
            project_id: "alpha-demo".to_string(),
            working_dir: default_demo_dir(),
        },
        dataset_ref: DatasetRef {
            source: "file".to_string(),
            path: default_demo_csv(),
            format: "csv".to_string(),
        },
        model_spec: ModelSpec {
            model_type: "ols".to_string(),
            formula: "y ~ x1 + x2".to_string(),
            vcov: Some(VcovSpec {
                kind: "classical".to_string(),
            }),
            weights: None,
            cluster_column: None,
            panel_id: None,
            panel_time: None,
            panel_method: None,
            instruments: None,
            endog_columns: None,
            gmm_weight: None,
            dpgmm_style: None,
            instrument_lags: None,
            collapse_instruments: None,
            omega_spec: None,
            treatment_column: None,
            treated_column: None,
            post_column: None,
            event_time_column: None,
            outcome_column: None,
            propensity_formula: None,
            outcome_formula: None,
            time_column: None,
            variable: None,
            variables: None,
            order: None,
            seasonal_order: None,
            ts_method: None,
            lags: None,
            deterministic: None,
            weights_column: None,
            strata_column: None,
            psu_column: None,
            fpc_column: None,
            equations: None,
            system_endogenous: None,
            system_instruments: None,
            sur_max_iter: None,
            sur_tol: None,
            quantile_tau: None,
            nls_family: None,
            nls_start: None,
            nls_max_iter: None,
            nls_tol: None,
            threshold_variable: None,
            threshold_grid: None,
            threshold_trim_frac: None,
            arch_order: None,
            garch_p: None,
            garch_q: None,
            garch_max_iter: None,
            garch_tol: None,
            spatial_weights_path: None,
            spatial_id_column: None,
            spatial_row_standardize: None,
            spatial_coord_columns: None,
            spatial_distance: None,
            spatial_crs: None,
            gwr_kernel: None,
            gwr_bandwidth: None,
            gwr_bandwidth_selection: None,
            gwr_adaptive: None,
            gtwr_time_column: None,
            gtwr_time_scale: None,
            duration_time_column: None,
            duration_event_column: None,
        },
        options: RequestOptions {
            drop_missing: true,
            return_augment: false,
            preview_rows: default_inspect_preview_rows(),
        },
    }
}

fn sample_data_command_request_base(kind: &str, task_id: &str) -> DataCommandRequest {
    DataCommandRequest {
        task_id: task_id.to_string(),
        action: actions::QUERY_DATASET.to_string(),
        project_context: ProjectContext {
            project_id: "alpha-demo".to_string(),
            working_dir: default_demo_dir(),
        },
        dataset_ref: DatasetRef {
            source: "file".to_string(),
            path: default_demo_csv(),
            format: "csv".to_string(),
        },
        command: DataCommand {
            kind: kind.to_string(),
            variables: Some(vec!["x1".to_string()]),
            limit: None,
        },
    }
}

pub fn sample_fit_model_request() -> TaskRequest {
    sample_request_base("fit_model", "uuid")
}

pub fn sample_inspect_dataset_request() -> TaskRequest {
    sample_request_base("inspect_dataset", "inspect-uuid")
}

pub fn sample_panel_fit_model_request() -> TaskRequest {
    let mut request = sample_request_base("fit_model", "panel-uuid");
    request.project_context.working_dir = repo_root().to_string_lossy().to_string();
    request.dataset_ref.path = "datasets/demo/grunfeld.csv".to_string();
    request.model_spec = ModelSpec {
        model_type: "panel".to_string(),
        formula: "invest ~ mvalue + capital".to_string(),
        vcov: None,
        weights: None,
        cluster_column: None,
        panel_id: Some("firm".to_string()),
        panel_time: Some("year".to_string()),
        panel_method: Some("fe".to_string()),
        instruments: None,
        endog_columns: None,
        gmm_weight: None,
        dpgmm_style: None,
        instrument_lags: None,
        collapse_instruments: None,
        omega_spec: None,
        treatment_column: None,
        treated_column: None,
        post_column: None,
        event_time_column: None,
        outcome_column: None,
        propensity_formula: None,
        outcome_formula: None,
        time_column: None,
        variable: None,
        variables: None,
        order: None,
        seasonal_order: None,
        ts_method: None,
        lags: None,
        deterministic: None,
        weights_column: None,
        strata_column: None,
        psu_column: None,
        fpc_column: None,
        equations: None,
        system_endogenous: None,
        system_instruments: None,
        sur_max_iter: None,
        sur_tol: None,
        quantile_tau: None,
        nls_family: None,
        nls_start: None,
        nls_max_iter: None,
        nls_tol: None,
        threshold_variable: None,
        threshold_grid: None,
        threshold_trim_frac: None,
        arch_order: None,
        garch_p: None,
        garch_q: None,
        garch_max_iter: None,
        garch_tol: None,
        spatial_weights_path: None,
        spatial_id_column: None,
        spatial_row_standardize: None,
        spatial_coord_columns: None,
        spatial_distance: None,
        spatial_crs: None,
        gwr_kernel: None,
        gwr_bandwidth: None,
        gwr_bandwidth_selection: None,
        gwr_adaptive: None,
        gtwr_time_column: None,
        gtwr_time_scale: None,
        duration_time_column: None,
        duration_event_column: None,
    };
    request.options.return_augment = true;
    request
}

pub fn sample_query_dataset_request(kind: &str) -> DataCommandRequest {
    let mut request = sample_data_command_request_base(kind, "query-uuid");
    if kind == "describe" || kind == "summarize" {
        request.command.variables = Some(vec!["y".to_string(), "x1".to_string()]);
    } else if kind == "browse" {
        request.command.variables = Some(vec!["y".to_string()]);
    }
    request
}

pub fn sample_success_response() -> TaskResponse {
    TaskResponse {
        task_id: "uuid".to_string(),
        status: "success".to_string(),
        messages: vec![Message {
            level: "info".to_string(),
            code: "INFO_ROWS_DROPPED".to_string(),
            text: "因缺失值已移除 12 行。".to_string(),
            hint: Some("拟合前请检查缺失列。".to_string()),
        }],
        artifacts: Some(vec![]),
        run_record: None,
        result_payload: Some(json!({
            "glance": {
                "model": "ols",
                "nobs": 128,
                "dof": 124,
                "metrics": {
                    "r2": 0.81
                }
            },
            "tidy": [],
            "augment_preview": [],
            "diagnostics": {
                "vif": [
                    { "name": "x1", "vif": 1.25 },
                    { "name": "x2", "vif": 2.5 }
                ],
                "breusch_pagan": { "statistic": 3.2, "pvalue": 0.0736, "dof": 2 },
                "white_test": { "statistic": 5.1, "pvalue": 0.0778, "dof": 2 },
                "durbin_watson": { "statistic": 1.85, "pvalue": 0.62 },
                "breusch_godfrey": { "statistic": 1.2, "pvalue": 0.5488, "dof": 2 },
                "reset_test": { "statistic": 0.45, "pvalue": 0.6453, "df_num": 2, "df_den": 4 },
                "jarque_bera": { "statistic": 0.82, "pvalue": 0.6637, "skewness": 0.15, "kurtosis": 2.8 }
            },
            "warnings": []
        })),
    }
}

pub fn sample_error_response() -> TaskResponse {
    TaskResponse {
        task_id: "uuid".to_string(),
        status: "error".to_string(),
        messages: vec![Message {
            level: "error".to_string(),
            code: "NUM_SINGULAR_MATRIX".to_string(),
            text: "设计矩阵奇异，无法估计模型。".to_string(),
            hint: Some("请检查是否存在某一预测变量是其他变量的线性组合。".to_string()),
        }],
        artifacts: None,
        run_record: None,
        result_payload: None,
    }
}

pub fn health_summary() -> HealthSummary {
    HealthSummary {
        service: "metrica-runtime".to_string(),
        status: "ready".to_string(),
        supported_actions: vec!["inspect_dataset", "query_dataset", "fit_model", "transform", "save_project", "load_project", "list_runs", "rerun_task"],
    }
}

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

/// 在 runs 目录下构建安全的 run 文件路径，校验 run_id 后确认路径不越界。
///
/// sanitize_id 已保证 run_id 仅含 A-Za-z0-9_-，不存在路径分隔符或 `..`，
/// 因此 `runs.join("{}.json", sanitized)` 永远在 runs 目录内。
/// 额外做一次 starts_with 检查作为防御层。
pub fn safe_runs_path(working_dir: &std::path::Path, run_id: &str) -> Result<std::path::PathBuf, String> {
    let sanitized = sanitize_id(run_id)?;
    let runs = working_dir.join(".metrica").join("runs");
    let path = runs.join(format!("{}.json", sanitized));
    // 防御性检查：join 结果必须仍在 runs 目录下
    if !path.starts_with(&runs) {
        return Err("路径越界。".into());
    }
    Ok(path)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformOperation {
    pub op: String,
    pub args: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformResult {
    pub operation: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<TransformResultDetail>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview: Option<TransformPreview>,
    pub warnings: Vec<Message>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<TransformError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformResultDetail {
    pub nrows: usize,
    pub ncols: usize,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformPreview {
    pub columns: Vec<String>,
    pub rows: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformError {
    pub op_index: usize,
    pub message: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sample_request_targets_fit_model() {
        let request = sample_fit_model_request();
        assert_eq!(request.action, "fit_model");
        assert_eq!(request.model_spec.model_type, "ols");
    }

    #[test]
    fn sample_panel_request_targets_panel_model() {
        let request = sample_panel_fit_model_request();
        assert_eq!(request.action, "fit_model");
        assert_eq!(request.model_spec.model_type, "panel");
        assert_eq!(request.model_spec.panel_id.as_deref(), Some("firm"));
        assert_eq!(request.model_spec.panel_time.as_deref(), Some("year"));
    }

    #[test]
    fn sample_success_response_contains_result_payload() {
        let response = sample_success_response();
        assert_eq!(response.status, "success");
        assert!(response.result_payload.is_some());
    }

    #[test]
    fn sample_error_response_contains_hint() {
        let response = sample_error_response();
        assert_eq!(response.status, "error");
        assert!(response.messages[0].hint.is_some());
    }
}
