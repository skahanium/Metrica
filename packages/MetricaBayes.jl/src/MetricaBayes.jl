module MetricaBayes

using CSV
using DataFrames
using Distributions
using LinearAlgebra
using Random
using Statistics
using MetricaBase
using MetricaLinear
using MetricaOutput

export BayesLinearModel, BayesLogisticModel, BayesProbitModel, BayesHierarchicalModel,
    BayesFitResult, fit_bayes_linear, fit_bayes_linear_mcmc,
    fit_bayes_logistic, fit_bayes_probit, fit_bayes_hierarchical,
    posterior_predictive, result_to_payload, error_to_payload

include("types.jl")
include("conjugate_fit.jl")
include("predictive.jl")
include("mcmc_fit.jl")
include("logistic_fit.jl")
include("hierarchical.jl")
include("interfaces.jl")
include("serialize.jl")

# === 注册到 MetricaBase MODEL_REGISTRY ====================================

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}(
            "bayes_linear" => BayesLinearModel,
            "bayes_logistic" => BayesLogisticModel,
            "bayes_probit" => BayesProbitModel,
            "bayes_hierarchical" => BayesHierarchicalModel,
        ))
    end
end

end # module
