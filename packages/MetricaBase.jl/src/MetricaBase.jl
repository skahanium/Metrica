module MetricaBase

using Dates
using Distributions: TDist, quantile

# === 导出列表 ================================================================

export AbstractEconModel,
    AbstractFittedModel,
    AbstractCovarianceSpec,
    AbstractPanelModel,
    AbstractLinearModel,
    AbstractLinearFitResult,
    Severity,
    info,
    warning,
    critical,
    ModelWarning,
    ModelCapabilities,
    ModelError,
    MetricValue,
    ModelGlance,
    CoefRow,
    TidyTable,
    AugmentTable,
    PanelData,
    ProjectManifest,
    RunRecord,
    DataLineage,
    WARNING_CODE,
    fit,
    coef,
    vcov,
    predict,
    glance,
    tidy,
    augment,
    stderror,
    confint,
    nobs,
    dof,
    r2,
    fitted,
    residuals,
    design_matrix,
    response,
    coefficient_names,
    model_capabilities,
    parse_metrica_formula

# === 严重程度枚举 ============================================================

"""
消息与警告的严重程度等级，供 `ModelWarning` 等类型使用。
"""
@enum Severity begin
    info
    warning
    critical
end

# === 抽象协议类型 ============================================================

"""
计量模型的抽象父类型。

既是模型规格对象（如 `OLSModel`）的协议入口，也是已拟合结果
（`AbstractFittedModel`）的祖先链终点。所有跨包共享的模型语义均通过
此类型及其子类型承载。
"""
abstract type AbstractEconModel end

"""
已拟合模型的抽象父类型。

携带拟合后的结果载荷、警告与诊断信息。下游应通过 `glance`、`tidy`、
`coef`、`vcov` 等函数消费其内容，而非直接访问内部字段。
"""
abstract type AbstractFittedModel end

"""
协方差估计规格的抽象父类型。

供 `vcov`、`fit` 等函数分派。子类型应编码协方差估计方法
（经典、HC1、聚类等）及其所需参数。
"""
abstract type AbstractCovarianceSpec end

"""
面板模型的抽象父类型。

子类型应编码面板估计方法（FE、RE、FD、Between 等）及其所需参数。
面板模型需要个体标识和时间标识来定义面板结构。
"""
abstract type AbstractPanelModel <: AbstractEconModel end

"""
线性模型族的抽象父类型。

OLS、WLS、IV/2SLS、GLS 等线性模型均应继承此类型。
用于统一 `fit` 泛型分派和协议方法分派。
"""
abstract type AbstractLinearModel <: AbstractEconModel end

"""
线性模型拟合结果的抽象父类型。

所有线性模型的拟合结果（OLSFitResult、IVFitResult、GLSFitResult）
均应继承此类型，以统一 `coef`、`vcov`、`predict` 等协议方法的分派。
"""
abstract type AbstractLinearFitResult <: AbstractFittedModel end

# === 消息与错误载荷 ==========================================================

"""
供包内、Runtime 与 App 消费的轻量警告对象。

警告表示拟合过程中发生了值得用户关注、但不阻断结果产出的情况
（例如缺失值删除、样本量变化、自由度修正等）。
"""
struct ModelWarning
    code::Symbol
    title::String
    detail::String
    hint::Union{Nothing, String}
    severity::Severity
end

"""
模型族能力声明。

该结构描述一个结果所属模型族当前真实可用的模型、估计器、诊断、效应与预测能力。
Runtime 与 App 应消费该结构化声明，而不是从模型名称或摘要文本推断能力。
"""
struct ModelCapabilities
    status::Symbol
    model_family::Symbol
    supported_models::Vector{Symbol}
    estimators::Vector{String}
    diagnostics_available::Vector{Symbol}
    diagnostics_unavailable::Vector{Symbol}
    effects_available::Vector{Symbol}
    prediction_available::Bool
    limitations::Vector{String}
end

"""
拟合或数据处理过程中断性错误的载荷。

与 `ModelWarning` 不同，`ModelError` 表示结果**无法**产出的阻断性错误
（例如设计矩阵奇异、有效样本为空、公式含未定义变量等）。

字段 `hint` 可为 `nothing`，此时下游不应展示建议区域。
"""
struct ModelError
    code::Symbol
    title::String
    detail::String
    hint::Union{Nothing, String}
end

# === 结构化结果中使用的值类型 =================================================

"""
`ModelGlance.metrics` 字典中允许的值类型。

当前仅包含 `Float64` 与 `Int`，后续可根据需要扩展 `Missing` 等成员。
"""
const MetricValue = Union{Float64, Int}

# === 结构化输出类型 ==========================================================

"""
模型级单行摘要载荷。

一个 `ModelGlance` 包含拟合后单模型的关键数字，供 Runtime 序列化及
App 结果卡片渲染。不携带系数表、诊断图或逐行预测数据。
"""
# ModelGlance.metrics 标准键名约定：
#
# 线性模型（OLS/WLS/IV/GLS）：
#   :r2, :adj_r2, :rss, :tss, :sigma, :f_stat, :f_pvalue,
#   :model_ss, :model_df, :model_ms, :resid_ss, :resid_df, :resid_ms,
#   :total_ss, :total_df, :total_ms
#
# 面板模型（FE/RE/FD/Between/CRE/HDFE）：
#   :r2, :adj_r2, :rss, :tss, :sigma, :f_stat, :f_pvalue,
#   :n_ids, :n_times, :r2_within, :r2_between, :r2_overall,
#   :rho, :sigma_u, :sigma_e
#
# 离散模型（Logit/Probit/Poisson/NegBin）：
#   :pseudo_r2, :loglik, :aic, :bic, :deviance,
#   :lr_chi2, :lr_pvalue, :iterations, :converged
#
# 时间序列（ARIMA/VAR）：
#   :loglik, :aic, :bic, :sigma2,
#   :ljung_box_stat, :ljung_box_pvalue
#
# 因果推断（DID/IPW/PSM/AIPW）：
#   :ate, :att, :atu, :ate_se, :att_se, :atu_se
#
# 调查模型（Survey OLS/Logit/Probit/Poisson）：
#   :r2/:pseudo_r2, :loglik, :aic, :bic, :mean_deff,
#   :wald_f, :wald_pvalue
struct ModelGlance
    model::Symbol
    nobs::Int
    dof::Int
    metrics::Dict{Symbol, MetricValue}
    warnings::Vector{ModelWarning}
end

"""
结构化参数表中的一行系数。

`stderror`、`statistic`、`pvalue`、`ci_lower`、`ci_upper` 可为 `nothing`——
当某模型未输出相应列（例如仅提供标准误而不计算 t 统计量或置信区间）时，
下游应据此省略展示。
"""
struct CoefRow
    name::Symbol
    estimate::Float64
    stderror::Union{Nothing, Float64}
    statistic::Union{Nothing, Float64}
    pvalue::Union{Nothing, Float64}
    ci_lower::Union{Nothing, Float64}
    ci_upper::Union{Nothing, Float64}
end

"""
面向输出层与 App 的结构化系数表。

由 `tidy()` 返回。`vcov_label` 标明所使用的协方差估计方法
（例如 `"classical"`、`"HC1"`），便于下游标注。
"""
struct TidyTable
    rows::Vector{CoefRow}
    vcov_label::String
end

"""
逐观测值增强表（拟合值、残差、诊断量等）。

由 `augment()` 返回。列式存储，每列为一个 `Vector{Float64}`。
标准列包括 `:observation`、`:fitted`、`:residual`，可选列包括
`:std_residual`、`:leverage`、`:cooks_d` 等。

下游可通过 `table.columns[:fitted]` 访问指定列。
"""
struct AugmentTable
    columns::Dict{Symbol, Vector{Float64}}
    nobs::Int
end

AugmentTable() = AugmentTable(Dict{Symbol, Vector{Float64}}(), 0)

"""
面板数据容器。

存储面板结构的数据，包含个体标识和时间标识。
`data` 可以是 DataFrame、Dict 或任何 Tables.jl 兼容容器。
类型参数 `T` 保留具体数据类型，便于下游分派。
"""
struct PanelData{T}
    data::T
    id_col::Symbol
    time_col::Symbol
end

"""
项目文件的最小结构化载荷。

由桌面端与 Runtime 共享，用于保存当前项目上下文。该类型只承载
项目状态，不承载完整模型大载荷。
"""
struct ProjectManifest
    project_id::String
    version::Int
    created_at::DateTime
    updated_at::DateTime
    source_dataset::String
    active_dataset::String
    saved_model_specs::Vector{Dict{Symbol, Any}}
    last_run_id::Union{Nothing, String}
    ui_state::Dict{Symbol, Any}
    data_lineage::Union{Nothing, Dict{Symbol, Any}}
end

"""
一次 inspect / transform / fit 的结构化运行记录。

运行记录用于项目重开、历史查看与重跑，不要求保存完整拟合大表，
但必须足以恢复原始请求和关键结果摘要。
"""
struct RunRecord
    run_id::String
    action::String
    started_at::DateTime
    finished_at::DateTime
    status::String
    dataset_ref::Dict{Symbol, Any}
    model_spec::Union{Nothing, Dict{Symbol, Any}}
    operations::Union{Nothing, Vector{Dict{Symbol, Any}}}
    warnings::Vector{Dict{Symbol, Any}}
    messages::Vector{Dict{Symbol, Any}}
    artifacts::Vector{String}
    result_summary::Union{Nothing, Dict{Symbol, Any}}
end

"""
数据从源文件到当前活动数据集的最小谱系摘要。
"""
struct DataLineage
    source_dataset::String
    active_dataset::String
    operations::Vector{Dict{Symbol, Any}}
    row_count_before::Union{Nothing, Int}
    row_count_after::Union{Nothing, Int}
    notes::Vector{String}
end

# === 公共 API 函数（接口桩）==================================================

"""
使用给定模型规格与数据拟合模型。

返回 `AbstractFittedModel` 的子类型实例；若拟合失败则返回 `ModelError`。
具体方法由各模型包（如 `MetricaLinear`）实现。
"""
function fit end

"""
从已拟合结果中提取系数向量。
"""
function coef end

"""
从已拟合结果中提取方差-协方差矩阵。

协方差估计方法由可选的 `AbstractCovarianceSpec` 参数指定。
"""
function vcov end

"""
基于已拟合结果对新数据进行预测。
"""
function predict end

"""
返回模型级单行摘要（`ModelGlance`）。
"""
function glance end

"""
返回结构化系数表（`TidyTable`）。
"""
function tidy end

"""
返回逐观测值增强表（拟合值、残差、诊断量等）。

具体列集合由各模型实现决定。
"""
function augment end

"""
从已拟合结果中提取标准误向量。
"""
function stderror end

"""
    confint(result; level=0.95)

计算系数的置信区间。返回 `(ci_lower, ci_upper)` 向量。
默认 95% 置信水平。

若 `stderror(result)` 返回 `nothing`，则返回两个由 `nothing` 填充的向量。
"""
function confint(result; level::Float64=0.95)
    coef_vals = coef(result)
    se_vals = stderror(result)
    dof_val = dof(result)

    if isnothing(se_vals)
        return (fill(nothing, length(coef_vals)), fill(nothing, length(coef_vals)))
    end

    α = 1 - level
    t_crit = quantile(TDist(dof_val), 1 - α / 2)

    ci_lower = coef_vals .- t_crit .* se_vals
    ci_upper = coef_vals .+ t_crit .* se_vals
    return (ci_lower, ci_upper)
end

"""
返回拟合所用的有效观测数。
"""
function nobs end

"""
返回模型的残差自由度。
"""
function dof end

"""
返回模型的 R² 决定系数。
"""
function r2 end

"""
返回拟合值向量。
"""
function fitted end

"""
返回残差向量。
"""
function residuals end

"""
从已拟合结果中提取设计矩阵（若可用）。

对于通过迭代优化拟合的模型（如 Logit、Probit），此函数返回 `nothing`。
诊断检验应检查返回值并在设计矩阵不可用时优雅降级。
"""
function design_matrix(fit::AbstractFittedModel)
    return nothing
end

"""
从已拟合结果中提取响应向量（若可用）。

对于没有显式响应向量的模型，此函数返回 `nothing`。
"""
function response(fit::AbstractFittedModel)
    return nothing
end

"""
从已拟合结果中提取系数名称向量。

默认实现从 `coef()` 的返回值中提取名称，适用于所有实现了 `coef` 的拟合结果。
"""
function coefficient_names(fit::AbstractFittedModel)
    pairs = coef(fit)
    isnothing(pairs) && return Symbol[]
    return [p[1] for p in pairs]
end

"""
返回拟合结果的模型族能力声明。

未实现专用方法的结果返回 `nothing`，表示该包尚未接入统一能力协议。
"""
function model_capabilities(fit::AbstractFittedModel)
    return nothing
end

# === 工具函数 ================================================================

"""
    parse_metrica_formula(formula)

将计量经济学公式字符串解析为因变量和自变量列表。

返回 `(response_name::String, predictor_names::Vector{String})`。
若格式无效则返回 `ModelError`。

# 示例
```julia
parse_metrica_formula("y ~ x1 + x2")  # → ("y", ["x1", "x2"])
```
"""
function parse_metrica_formula(formula::AbstractString)
    parts = split(formula, "~")
    if length(parts) != 2
        return ModelError(
            :formula_parse_failed,
            "公式解析失败",
            "公式必须包含一个 `~`。",
            "请使用如 y ~ x1 + x2 的公式格式。",
        )
    end
    response_name = strip(parts[1])
    predictor_names = [strip(x) for x in split(parts[2], "+")]
    if isempty(response_name)
        return ModelError(
            :formula_parse_failed,
            "公式解析失败",
            "公式缺少因变量。",
            "请使用如 y ~ x1 + x2 的公式格式。",
        )
    end
    return response_name, predictor_names
end

# === 统一 WARNING CODE 注册表 =================================================

"""
    跨包共享的 warning code 符号常量。

    所有 S5 包在构造 `ModelWarning` 时均应使用此注册表中的 code，
    以确保 Runtime / App 能按机器可读 code 进行分类展示与教学解释。
"""
const WARNING_CODE = Dict(
    # 通用数据/样本
    :rows_dropped_missing => "因缺失值删除行",
    :rows_dropped_listwise => "listwise 删行",
    :rows_dropped => "因缺失值删除观测行",
    :n_obs_low => "样本量偏小，估计精度可能不足",
    :small_sample => "样本量偏小，推断应谨慎",
    # 数值/矩阵
    :near_singular => "矩阵近奇异，结果可能不稳定",
    :singular_hessian => "Hessian 不可逆，标准误不可用",
    :singular_design => "设计矩阵奇异",
    :weak_instrument => "工具变量与内生变量相关性弱",
    # 优化/收敛
    :convergence_not_reached => "优化未收敛",
    :local_optimum_risk => "存在局部最优风险，建议尝试不同初值",
    :optimizer_failure => "优化器返回失败状态",
    :irls_not_converged => "IRLS 迭代未收敛",
    :nls_not_converged => "非线性最小二乘未收敛",
    :garch_not_converged => "GARCH 估计未收敛",
    :arch_not_converged => "ARCH 估计未收敛",
    :gjr_not_converged => "GJR-GARCH 估计未收敛",
    :egarch_not_converged => "EGARCH 估计未收敛",
    :mle_not_converged => "MLE 优化未收敛",
    :css_not_converged => "CSS 估计未收敛",
    :mlogit_not_converged => "多项 Logit 估计未收敛",
    # 诊断不可用
    :diag_unavailable => "诊断指标不可用",
    :diag_not_applicable => "该诊断不适用于当前模型",
    :nls_se_not_implemented => "NLS 标准误尚未实现",
    :quantile_se_unavailable => "分位数回归标准误不可用",
    # 效应与预测
    :effects_unavailable => "效应分解不可用",
    :prediction_unavailable => "当前模型不支持预测",
    # 空间专用
    :isolated_unit => "空间权重中存在孤立单元",
    :bandwidth_too_small => "带宽过小，局部回归可能不稳定",
    :duplicate_coordinates => "存在重复坐标",
    :crs_unknown => "坐标参考系未声明，距离度量可能不准确",
    # 面板/动态
    :instrument_proliferation => "工具变量过多，可能存在过度拟合",
    :many_instruments => "工具变量数量较多",
    :short_panel => "面板时间维度偏短",
    :few_groups => "截面个体数偏少",
    :ar2_serial_correlation => "AR(2) 序列相关检验提示自相关",
    # 因果推断
    :parallel_trends_unchecked => "平行趋势假设尚未检验",
    :parallel_trends_check => "事件研究平行趋势预检验提示",
    # 波动率
    :volatility_nonstationary => "波动率过程非平稳（persistence ≥ 1）",
    :variance_nonpositive => "方差参数估计值非正",
    :garch_fit_failed => "GARCH 模型拟合失败",
    :arch_fit_failed => "ARCH 模型拟合失败",
    # 久期
    :ph_assumption_untested => "PH 假设尚未检验",
    :all_censored => "所有观测均为删失，无法估计",
    # 贝叶斯
    :mcmc_not_applicable => "当前使用解析推断，MCMC 诊断不适用",
    # 分位数
    :tau_near_boundary => "分位点 τ 接近边界，估计方差可能较大",
    :extreme_quantile => "极端分位点估计，方差可能较大",
    # 离散选择
    :possible_separation => "可能存在完全分离，参数估计不可靠",
    :overdispersion => "数据存在过度分散，应考虑负二项模型",
    :near_poisson => "负二项过分散参数接近 Poisson 边界",
    # 时间序列
    :unitroot_conflict => "单位根检验结论冲突",
    :pp_adf_conflict => "PP 与 ADF 检验结论不一致",
    :var_instability => "VAR 模型参数可能存在结构性不稳定",
    # 数据操作
    :tabulate_truncated => "唯一值数量超过显示上限，频数表已截断",
    # 模型构建
    :mle_se_unavailable => "MLE 标准误不可用，使用伪方差估计",
    :css_se_unavailable => "CSS 标准误不可用",
)

# === 模型注册表 ==============================================================

"""
    MODEL_REGISTRY::Dict{String, Type}

全局模型注册表。Key 是 model_type 字符串，Value 是对应的模型规格类型。
各包在 `__init__()` 中自行注册。Daemon 通过此注册表统一 dispatch。
"""
const MODEL_REGISTRY = Dict{String, Type}()

"""
    register_model(model_type::String, T::Type)

向注册表添加一个模型类型。幂等。
"""
function register_model(model_type::String, T::Type)
    MODEL_REGISTRY[model_type] = T
    return nothing
end

export MODEL_REGISTRY, register_model
export severity_to_string, warning_to_dict, error_to_payload
export capabilities_to_dict, dict_symbol_to_string
export build_glance_envelope, build_tidy_rows, build_messages
export build_augment_status, build_augment_preview, try_capabilities

include("serialize.jl")

end
