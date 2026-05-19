# === Runtime / MODEL_REGISTRY marker specs =================================

struct CoxModel <: MetricaBase.AbstractEconModel end
struct AFTWeibullModel <: MetricaBase.AbstractEconModel end
struct AFTExponentialModel <: MetricaBase.AbstractEconModel end
struct AFTLognormalModel <: MetricaBase.AbstractEconModel end
struct AFTLoglogisticModel <: MetricaBase.AbstractEconModel end

# === Cox PH 拟合结果 ========================================================

"""Cox 比例风险模型（Breslow 并列）拟合结果。"""
struct CoxFitResult
    model::Symbol
    coef_names::Vector{Symbol}
    """log 相对风险系数 β̂"""
    beta::Vector{Float64}
    """渐近标准误（log 尺度）"""
    se::Vector{Float64}
    loglik::Float64
    n::Int
    n_events::Int
    n_censored::Int
    converged::Bool
    iterations::Int
    """Breslow 基准累积风险在事件时间点上的预览（time, H0）"""
    baseline_preview::Vector{Pair{Float64, Float64}}
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
end
