module MetricaGMM

using CSV
using DataFrames
using Distributions: TDist, FDist, Chisq, cdf, quantile
using LinearAlgebra: Symmetric, cholesky, inv, dot, rank, diag, I, tr
using Statistics
using StatsModels
using MetricaBase
using MetricaOutput

export GMMLinearModel, GMMLinearFitResult, result_to_payload, linear_iv_gmm_stack

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
