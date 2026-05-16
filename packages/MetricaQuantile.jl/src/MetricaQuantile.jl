module MetricaQuantile

using DataFrames
using MetricaBase
using MetricaLinear
using MetricaOutput
using QuantileRegressions

export QuantileModel, QuantileFitResult, result_to_payload

include("types.jl")
include("fit.jl")
include("serialize.jl")

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}("quantile" => QuantileModel))
    end
end

end
