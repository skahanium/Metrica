module MetricaGMM

using CSV
using DataFrames
using Distributions: TDist, FDist, Chisq, cdf, quantile
using LinearAlgebra: Symmetric, cholesky, inv, dot, rank, diag, I, tr, eigvals, cond

"""与 MetricaLinear 相同：用 `1/cond` 近似 rcond 判定 bread 是否可逆。"""
function _invertible_bread(bread::AbstractMatrix{<:AbstractFloat})
    n = size(bread, 1)
    n == 0 && return false
    inv_cond = 1 / cond(bread)
    return isfinite(inv_cond) && inv_cond > n * eps(eltype(bread))
end
using Optim
using Statistics
using StatsModels
using MetricaBase
using MetricaOutput

export GMMLinearModel, GMMLinearFitResult, result_to_payload, linear_iv_gmm_stack
export gmm_c_stat, gmm_diff_hansen

include("gmm_algebra.jl")
include("formula.jl")
include("gmm.jl")
include("linear_iv_gmm_stack.jl")
include("serialize.jl")

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}(
            "gmm_linear" => GMMLinearModel,
        ))
    end
end

end
