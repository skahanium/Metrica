module MetricaDuration

using CSV
using DataFrames
using Distributions
using FiniteDiff
using LinearAlgebra: I, Symmetric, diag, dot, eigvals, inv
using Optim
using MetricaBase
using MetricaOutput

export CoxFitResult, fit_duration_cox, result_to_payload, error_to_payload

include("types.jl")
include("cox_fit.jl")
include("interfaces.jl")
include("serialize.jl")

end # module
