module MetricaData

using DataFrames

include("transform.jl")
include("reshape.jl")
include("combine.jl")
include("join.jl")
include("serialize.jl")

export generate, replace, rename, drop, keep
export filter, sort
export merge, reshape_long, reshape_wide, collapse
export result_to_dict, operate, operate_chain

end # module MetricaData
