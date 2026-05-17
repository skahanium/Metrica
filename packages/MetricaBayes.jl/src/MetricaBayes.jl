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

export BayesLinearModel, BayesFitResult, fit_bayes_linear, result_to_payload

include("types.jl")
include("conjugate_fit.jl")
include("interfaces.jl")
include("serialize.jl")

end # module
