# === 空间计量拟合结果类型 =====================================================

"""
截面 SAR / SEM 拟合结果，供 `glance` / `tidy` 与 `result_to_payload` 消费。
"""
struct SpatialFitResult
    model_kind::Symbol
    """系数 `(符号 => 值)`，顺序：`ρ` 或 `λ` 在前，其后为 `X` 列（含截距）。"""
    coef::Vector{Pair{Symbol, Float64}}
    stderror::Union{Nothing, Vector{Float64}}
    vcov_label::String
    residual::Vector{Float64}
    fitted::Vector{Float64}
    nobs::Int
    dof::Int
    spatial_param::Float64
    spatial_param_name::Symbol
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
    loglik::Union{Nothing, Float64}
end
