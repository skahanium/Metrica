module MetricaNonlinear

using MetricaBase
using MetricaLinear
using MetricaOutput

export NLSModel, ThresholdModel, NLSFitResult, ThresholdFitResult, result_to_payload

include("types.jl")
include("fit.jl")
include("serialize.jl")

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(
            MetricaBase.MODEL_REGISTRY,
            Dict{String, Type}("nls" => NLSModel, "threshold" => ThresholdModel),
        )
    end
end

end
