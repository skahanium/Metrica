module MetricaDuration

using CSV
using DataFrames
using Distributions
using FiniteDiff
using LinearAlgebra: I, Symmetric, diag, dot, eigvals, inv, pinv, cor
using Optim
using MetricaBase
using Statistics
using Random

export CoxFitResult, AFTFitResult, fit_duration_cox, fit_aft, result_to_payload, error_to_payload

include("types.jl")
include("cox_fit.jl")
include("cox_diagnostics.jl")
include("aft_fit.jl")
include("interfaces.jl")
include("serialize.jl")

end # module
