# === 类型定义 =================================================================

"""线性分位数回归模型占位（算法在 `fit` 中实现）。"""
struct QuantileModel <: MetricaBase.AbstractEconModel end

"""分位数回归拟合结果（单分位点 τ）。"""
struct QuantileFitResult <: MetricaBase.AbstractFittedModel
    formula_string::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    tau::Float64
    X::Matrix{Float64}
    y::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficients::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Union{Nothing, Float64}}
    fitted_values::Vector{Float64}
    residuals::Vector{Float64}
    """与 `serialize` 对齐的诊断字典（符号键，序列化时转字符串）。"""
    diagnostics::Dict{Symbol, Any}
end
