# 内部：将 glance/tidy 指标写入 golden JSON（供 compute_*_reference.jl include）
using JSON3

function _finite_json_float(x)
    v = Float64(x)
    isfinite(v) || error("non-finite value for golden JSON: $x")
    return v
end

function metric_dict(name, value)
    return Dict("name" => String(name), "value" => _finite_json_float(value))
end

function tidy_dict(name, estimate, stderror, statistic)
    return Dict(
        "name" => String(name),
        "estimate" => _finite_json_float(estimate),
        "stderror" => _finite_json_float(stderror),
        "statistic" => _finite_json_float(statistic),
    )
end

function default_tolerances()
    return [
        Dict("name" => "coefficient", "atol" => 1.0e-8),
        Dict("name" => "stderror", "atol" => 1.0e-8),
        Dict("name" => "statistic", "atol" => 1.0e-8),
        Dict("name" => "metric", "atol" => 1.0e-8),
    ]
end

"""
    resolve_golden_json_path(case_prefix) -> String

`case_prefix` 为不含扩展名的用例路径（通常 `.../datasets/golden/<id>`）。
当 `ENV["GOLDEN_JSON_OUTPUT_DIR"]` 存在时，仅 JSON 写入该目录（供 drift 检查）；CSV 仍从原路径读取。
"""
function resolve_golden_json_path(case_prefix::AbstractString)
    if haskey(ENV, "GOLDEN_JSON_OUTPUT_DIR")
        id = basename(case_prefix)
        return joinpath(ENV["GOLDEN_JSON_OUTPUT_DIR"], "$(id).json")
    end
    return "$(case_prefix).json"
end

function write_golden_json(path::AbstractString, spec::AbstractDict)
    open(path, "w") do io
        JSON3.pretty(io, spec)
    end
    println("Wrote ", path)
    return nothing
end
