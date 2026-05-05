module MetricaPanel

using DataFrames
using Distributions
using LinearAlgebra
using MetricaBase
using MetricaLinear
using Statistics
using StatsModels

export PanelModel, PanelFitResult, PanelIVModel, PanelIVFitResult,
    fit_panel, fit_hdfde, fit_crea, fit_panel_iv,
    panel_diagnostics, result_to_payload,
    compute_dk_vcov, compute_iv_dk_vcov

"""
面板模型规格对象。

包含面板拟合所需的所有参数：公式、个体标识、时间标识和估计方法。
"""
struct PanelModel <: MetricaBase.AbstractPanelModel
    formula::String
    id_col::Symbol
    time_col::Symbol
    method::Symbol  # :fe, :re, :fd, :between
end

"""
面板模型的结构化拟合结果。

承载面板拟合后的所有结果载荷，包括摘要、系数表、拟合值和残差。
"""
struct PanelFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    panel_data::MetricaBase.PanelData
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
    method::Symbol
end

MetricaBase.glance(result::PanelFitResult) = result.glance_table
MetricaBase.tidy(result::PanelFitResult) = result.tidy_table

function MetricaBase.augment(result::PanelFitResult)
    nobs = length(result.fitted_values)
    cols = Dict{Symbol, Vector{Float64}}(
        :observation => collect(1.0:nobs),
        :fitted => result.fitted_values,
        :residual => result.residual_vector,
    )

    # 计算标准化残差（若自由度 > 0）
    k = length(result.coefficient_names)
    dof = nobs - k
    if dof > 0
        rss = sum(abs2, result.residual_vector)
        sigma = sqrt(rss / dof)
        if sigma > 0
            cols[:std_residual] = result.residual_vector ./ sigma
        end
    end

    return MetricaBase.AugmentTable(cols, nobs)
end

MetricaBase.coef(result::PanelFitResult) = [r.estimate for r in result.tidy_table.rows]
MetricaBase.stderror(result::PanelFitResult) = [r.stderror for r in result.tidy_table.rows]
MetricaBase.nobs(result::PanelFitResult) = result.glance_table.nobs
MetricaBase.dof(result::PanelFitResult) = result.glance_table.dof
MetricaBase.r2(result::PanelFitResult) = get(result.glance_table.metrics, :r2, NaN)
MetricaBase.fitted(result::PanelFitResult) = result.fitted_values
MetricaBase.residuals(result::PanelFitResult) = result.residual_vector

function MetricaBase.vcov(result::PanelFitResult)
    return MetricaBase.ModelError(
        :vcov_not_available,
        "Panel 模型未直接存储方差-协方差矩阵。",
        "PanelFitResult 未存储完整 vcov 矩阵。",
        "请使用 stderror() 获取标准误，或参考 Driscoll-Kraay 模块。",
    )
end

# === 共享 OLS 统计量计算 ======================================================

"""
    ols_statistics(X, y, coef_names, model_sym, extra_metrics)

对给定的设计矩阵 `X` 和响应向量 `y` 执行 OLS，返回系数、拟合值、残差、
`ModelGlance` 和 `TidyTable`。各面板估计器通过本函数复用统计量计算逻辑。
"""
function ols_statistics(X::Matrix{Float64}, y::Vector{Float64},
                         coef_names::Vector{Symbol}, model_sym::Symbol,
                         extra_metrics::Dict{Symbol, <:MetricaBase.MetricValue})
    nobs = length(y)
    k = size(X, 2)
    dof = nobs - k

    coefficients = X \ y
    fitted = X * coefficients
    residuals = y - fitted

    rss = sum(abs2, residuals)
    tss = sum(abs2, y .- mean(y))
    r2 = iszero(tss) ? 0.0 : 1.0 - rss / tss
    adj_r2 = dof > 0 ? 1.0 - (1.0 - r2) * (nobs - 1) / dof : NaN
    sigma = dof > 0 ? sqrt(rss / dof) : NaN

    metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :r2 => r2,
        :adj_r2 => adj_r2,
        :sigma => sigma,
        :rss => rss,
        :tss => tss,
    )
    merge!(metrics, extra_metrics)

    if dof > 0
        XtX_inv = inv(X' * X)
        std_errors = sqrt.(max.(diag(XtX_inv) .* sigma^2, 0.0))
        t_stats = coefficients ./ std_errors
        p_values = 2.0 .* (1.0 .- cdf.(TDist(dof), abs.(t_stats)))
    else
        std_errors = fill(NaN, k)
        t_stats = fill(NaN, k)
        p_values = fill(NaN, k)
    end

    tidy_rows = MetricaBase.CoefRow[
        MetricaBase.CoefRow(coef_names[i], coefficients[i], std_errors[i], t_stats[i], p_values[i])
        for i in 1:k
    ]

    glance_table = MetricaBase.ModelGlance(model_sym, nobs, dof, metrics, MetricaBase.ModelWarning[])
    tidy_table = MetricaBase.TidyTable(tidy_rows, "classical")

    return (; coefficients, fitted, residuals, glance_table, tidy_table)
end

include("fe.jl")
include("hdfde.jl")
include("dk.jl")
include("cre.jl")
include("panel_iv.jl")
include("re.jl")
include("fd.jl")
include("between.jl")
include("diagnostics.jl")
include("serialize.jl")

"""
    fit_panel(panel_data::PanelData, formula::String; method::Symbol=:fe)

面板模型拟合入口。

根据 `method` 参数选择估计方法：
- `:fe` — 固定效应（默认）
- `:re` — 随机效应
- `:fd` — 一阶差分
- `:between` — 组间估计

返回 `PanelFitResult`。
"""
const _PANEL_ESTIMATORS = Dict{Symbol, Function}(
    :fe => fit_fe,
    :re => fit_re,
    :fd => fit_fd,
    :between => fit_between,
    :cre => fit_crea,
)

function fit_panel(panel_data::MetricaBase.PanelData, formula::String; method::Symbol=:fe, fe_spec::Vector{Symbol}=Symbol[])
    if method === :hdfde
        isempty(fe_spec) && error("HDFE 方法需要指定 fe_spec 参数，如 fe_spec=[:firm, :year]")
        return fit_hdfde(panel_data, formula; fe_spec=fe_spec)
    end
    estimator = get(_PANEL_ESTIMATORS, method) do
        error("面板估计方法 :$method 尚未实现")
    end
    return estimator(panel_data, formula)
end

# === MODEL_REGISTRY 兼容的 fit 入口 ===========================================

function MetricaBase.fit(::Type{PanelModel}, formula::AbstractString, data;
                          panel_id::Symbol, panel_time::Symbol,
                          panel_method::Symbol=:fe, fe_spec::Vector{Symbol}=Symbol[],
                          instruments::Union{Nothing,Vector{String}}=nothing,
                          endog::Union{Nothing,Vector{String}}=nothing,
                          vcov::Symbol=:classical, cluster_column=nothing, weights=nothing)
    df = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end
    panel_data = MetricaBase.PanelData(df, panel_id, panel_time)

    if panel_method === :panel_iv
        isnothing(instruments) && return MetricaBase.ModelError(:missing_instruments,
            "Panel IV 需要 instruments 参数", "", "")
        isnothing(endog) && return MetricaBase.ModelError(:missing_endog,
            "Panel IV 需要 endog 参数", "", "")
        return fit_panel_iv(panel_data, formula; instruments=instruments, endog=endog)
    end

    fit_panel(panel_data, formula; method=panel_method, fe_spec=fe_spec)
end

function MetricaBase.fit(::Type{PanelIVModel}, formula::AbstractString, data;
                          panel_id::Symbol, panel_time::Symbol,
                          instruments::Vector{String}, endog::Vector{String},
                          panel_method::Symbol=:panel_iv, fe_spec::Vector{Symbol}=Symbol[],
                          vcov::Symbol=:classical, cluster_column=nothing, weights=nothing)
    df = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end
    panel_data = MetricaBase.PanelData(df, panel_id, panel_time)
    return fit_panel_iv(panel_data, formula; instruments=instruments, endog=endog)
end

# === MODEL_REGISTRY 注册 =====================================================

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}(
            "panel" => PanelModel,
            "panel_iv" => PanelIVModel,
        ))
    end
end

end
