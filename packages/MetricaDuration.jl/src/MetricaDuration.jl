module MetricaDuration

using CSV
using DataFrames
using Distributions
using FiniteDiff
using LinearAlgebra: I, Symmetric, diag, dot, eigvals, inv, pinv
using Optim
using MetricaBase
using Statistics
using Random

export CoxModel, AFTWeibullModel, AFTExponentialModel, AFTLognormalModel, AFTLoglogisticModel,
    CoxFitResult, AFTFitResult, fit_duration_cox, fit_aft, result_to_payload, error_to_payload

include("types.jl")
include("cox_fit.jl")
include("cox_diagnostics.jl")
include("aft_fit.jl")
include("interfaces.jl")
include("serialize.jl")

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}(
            "duration_cox" => CoxModel,
            "aft_weibull" => AFTWeibullModel,
            "aft_exponential" => AFTExponentialModel,
            "aft_lognormal" => AFTLognormalModel,
            "aft_loglogistic" => AFTLoglogisticModel,
        ))
    end
end

end # module
