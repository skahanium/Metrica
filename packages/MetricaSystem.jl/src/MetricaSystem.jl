module MetricaSystem

using DataFrames
using MetricaBase
using MetricaLinear
using MetricaOutput

export SURModel,
    System2SLSModel,
    System3SLSModel,
    SystemEquationsFitResult,
    result_to_payload

include("types.jl")
include("fit.jl")
include("serialize.jl")

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(
            MetricaBase.MODEL_REGISTRY,
            Dict{String, Type}(
                "sur" => SURModel,
                "system_2sls" => System2SLSModel,
                "system_3sls" => System3SLSModel,
            ),
        )
    end
end

end
