module MetricaSpatial

using CSV
using DataFrames
using Distributions
using LinearAlgebra
using Optim
using Statistics
using MetricaBase
using MetricaOutput

export SpatialFitResult, fit_spatial, result_to_payload, error_to_payload
export lm_lag_test, lm_error_test, robust_lm_lag_test, robust_lm_error_test
export build_knn_weights, build_distance_band_weights
export euclidean_distance, haversine_distance

include("types.jl")
include("weights_io.jl")
include("weights_knn.jl")
include("weights_distance.jl")
include("moran.jl")
include("lm_tests.jl")
include("sar_fit.jl")
include("sem_fit.jl")
include("slx_fit.jl")
include("sdm_fit.jl")
include("sdem_fit.jl")
include("sac_fit.jl")
include("effects.jl")
include("interfaces.jl")
include("fit_spatial.jl")
include("serialize.jl")

end # module
