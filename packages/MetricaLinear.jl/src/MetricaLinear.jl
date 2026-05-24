module MetricaLinear

using CSV
using DataFrames
using Distributions
using JSON3
using LinearAlgebra

"""
Bread 矩阵是否数值可逆（用于杠杆值）。

Julia 标准库无 `rcond`；此处用 `1/cond(bread)` 作为逆条件数近似（与 `rcond` 同阶判定）。
"""
function _invertible_bread(bread::AbstractMatrix{<:AbstractFloat})
    n = size(bread, 1)
    n == 0 && return false
    inv_cond = 1 / cond(bread)
    return isfinite(inv_cond) && inv_cond > n * eps(eltype(bread))
end
using Statistics
using StatsModels
using MetricaBase
using MetricaOutput
using MetricaData

export OLSModel, OLSFitResult, IVModel, IVFitResult, GLSModel, GLSFitResult,
    PHASE_1_MODELS, fit, inspect_dataset, result_to_payload

const PHASE_1_MODELS = (:OLS, :IV, :GLS)

"""
第一条参考线性模型的规格对象。
"""
struct OLSModel <: MetricaBase.AbstractLinearModel
    formula::String
end

"""
第一条真实 OLS 链路的结构化拟合结果。
"""
struct OLSFitResult <: MetricaBase.AbstractLinearFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    bread_matrix::Matrix{Float64}
end

MetricaBase.glance(result::OLSFitResult) = result.glance_table
MetricaBase.tidy(result::OLSFitResult) = result.tidy_table

function MetricaBase.augment(result::OLSFitResult)
    nobs = length(result.response_vector)
    X = result.design_matrix
    residuals = result.residual_vector
    fitted = result.fitted_values

    # 计算标准化残差
    sigma = sqrt(sum(abs2, residuals) / (nobs - size(X, 2)))
    std_residuals = sigma > 0 ? residuals ./ sigma : zeros(nobs)

    # 计算杠杆值（hat matrix 对角线）
    # WLS: H = X(X'WX)^{-1}X'W，杠杆值 h_ii 使用 bread 矩阵
    bread = result.bread_matrix
    if _invertible_bread(bread)
        leverage = [dot(X[i, :], bread * X[i, :]) for i in 1:nobs]
    else
        leverage = fill(NaN, nobs)
    end

    # 计算 Cook's D
    k = size(X, 2)
    cooks_d = fill(NaN, nobs)
    for i in 1:nobs
        if leverage[i] < 1.0 && sigma > 0
            cooks_d[i] = (std_residuals[i]^2 * leverage[i]) / (k * (1.0 - leverage[i])^2)
        end
    end

    return MetricaBase.AugmentTable(
        Dict(
            :observation => collect(1.0:nobs),
            :fitted => fitted,
            :residual => residuals,
            :std_residual => std_residuals,
            :leverage => leverage,
            :cooks_d => cooks_d,
        ),
        nobs,
    )
end

MetricaBase.coef(result::OLSFitResult) = result.coefficient_names .=> result.coefficient_values
MetricaBase.vcov(result::OLSFitResult) = result.vcov_matrix
MetricaBase.stderror(result::OLSFitResult) = result.stderror_values
MetricaBase.nobs(result::OLSFitResult) = length(result.response_vector)
MetricaBase.dof(result::OLSFitResult) = length(result.response_vector) - length(result.coefficient_names)
MetricaBase.r2(result::OLSFitResult) = result.glance_table.metrics[:r2]
MetricaBase.fitted(result::OLSFitResult) = result.fitted_values
MetricaBase.residuals(result::OLSFitResult) = result.residual_vector
MetricaBase.design_matrix(result::OLSFitResult) = result.design_matrix
MetricaBase.response(result::OLSFitResult) = result.response_vector
MetricaBase.coefficient_names(result::OLSFitResult) = result.coefficient_names

function MetricaBase.predict(result::OLSFitResult;
                             newdata::Union{Nothing,Matrix{Float64}}=nothing,
                             interval::Symbol=:none, level::Float64=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    predictions = X * result.coefficient_values

    interval === :none && return predictions

    n = length(result.response_vector)
    k = length(result.coefficient_names)
    dof_val = n - k
    t_crit = quantile(TDist(dof_val), 1 - (1 - level) / 2)
    sigma = result.glance_table.metrics[:sigma]
    bread = result.bread_matrix

    if interval === :confidence
        se_pred = [sqrt(sigma^2 * dot(X[i, :], bread * X[i, :])) for i in 1:size(X, 1)]
    else
        se_pred = [sqrt(sigma^2 * (1 + dot(X[i, :], bread * X[i, :]))) for i in 1:size(X, 1)]
    end

    lower = predictions .- t_crit .* se_pred
    upper = predictions .+ t_crit .* se_pred
    return (predictions=predictions, lower=lower, upper=upper)
end

include("io.jl")
include("ols.jl")
include("iv.jl")
include("gls.jl")
include("serialize.jl")

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}(
            "ols" => OLSModel,
            "iv" => IVModel,
            "gls" => GLSModel,
        ))
    end
end

end
