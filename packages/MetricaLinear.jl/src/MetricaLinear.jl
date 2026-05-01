module MetricaLinear

using CSV
using DataFrames
using Distributions
using JSON3
using LinearAlgebra
using Statistics
using StatsModels
using MetricaBase
using MetricaOutput

export OLSModel, OLSFitResult, PHASE_1_MODELS, fit_ols_file, inspect_dataset, result_to_payload

const PHASE_1_MODELS = (:OLS,)

"""
第一条参考线性模型的规格对象。
"""
struct OLSModel <: MetricaBase.AbstractEconModel
    formula::String
end

"""
第一条真实 OLS 链路的结构化拟合结果。
"""
struct OLSFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
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
    # H = X(X'X)^{-1}X'，杠杆值 h_ii = diag(H)
    XtX = X' * X
    if det(XtX) > eps(Float64)
        XtX_inv = inv(XtX)
        leverage = [dot(X[i, :], XtX_inv * X[i, :]) for i in 1:nobs]
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

include("io.jl")
include("ols.jl")
include("serialize.jl")

end
