# === 类型定义 =================================================================

"""非线性最小二乘（受控白名单族）。"""
struct NLSModel <: MetricaBase.AbstractEconModel end

"""单门限双区制线性回归。"""
struct ThresholdModel <: MetricaBase.AbstractEconModel end

"""NLS 拟合结果。"""
struct NLSFitResult <: MetricaBase.AbstractFittedModel
    formula_string::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    nls_family::String
    coefficients::Vector{Float64}
    residual_sum_squares::Float64
    converged::Bool
    iterations::Int
    optimizer::String
    failure_code::Union{Nothing, Symbol}
    diagnostics::Dict{Symbol, Any}
    z::Vector{Float64}
    y::Vector{Float64}
    fitted_values::Vector{Float64}
    residuals::Vector{Float64}
end

"""门限回归拟合结果。"""
struct ThresholdFitResult <: MetricaBase.AbstractFittedModel
    formula_string::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    gamma_hat::Float64
    n_below::Int
    n_above::Int
    rss_piecewise::Float64
    diagnostics::Dict{Symbol, Any}
    fitted_values::Vector{Float64}
    residuals::Vector{Float64}
end
