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

export BayesLinearModel, BayesFitResult, fit_bayes_linear, fit_bayes_linear_mcmc,
    fit_bayes_logistic, fit_bayes_probit, fit_bayes_hierarchical,
    posterior_predictive, result_to_payload

include("types.jl")
include("conjugate_fit.jl")
include("predictive.jl")
include("mcmc_fit.jl")
include("logistic_fit.jl")
include("hierarchical.jl")
include("interfaces.jl")
include("serialize.jl")

end # module
