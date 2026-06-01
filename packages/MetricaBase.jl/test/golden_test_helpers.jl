# 供各 Core 包 golden 测试 include；非公开 API。
using JSON3

const _HELPERS_PKG_ROOT = normpath(joinpath(@__DIR__, ".."))
const GOLDEN_REPO_ROOT = normpath(joinpath(_HELPERS_PKG_ROOT, "..", ".."))
const GOLDEN_ROOT = joinpath(GOLDEN_REPO_ROOT, "datasets", "golden")
const GOLDEN_DATASETS_ROOT = joinpath(GOLDEN_REPO_ROOT, "datasets")

"""
    load_golden_spec(name) -> JSON3.Object

加载 `datasets/golden/<name>.json`。
"""
function load_golden_spec(name::AbstractString)
    path = joinpath(GOLDEN_ROOT, "$(name).json")
    isfile(path) || error("golden spec not found: $path")
    return JSON3.read(read(path, String))
end

"""
    golden_dataset_path(spec) -> String

将 spec.dataset（相对 `datasets/`）解析为绝对路径。
"""
function golden_dataset_path(spec)
    return joinpath(GOLDEN_DATASETS_ROOT, String(spec.dataset))
end

"""
    golden_tolerance_dict(spec) -> Dict{String, Float64}

从 spec.tolerances 构建名称 → atol 映射。
"""
function golden_tolerance_dict(spec)
    return Dict(String(row.name) => Float64(row.atol) for row in spec.tolerances)
end

"""
    assert_golden_close(actual, expected, atol; label="")

在 Test 宏上下文中使用：`@test assert_golden_close(...)`

失败时通过 `@test` 报告；返回 `Bool` 供链式使用。
"""
function assert_golden_close(actual, expected, atol::Real; label::AbstractString = "")
    return isapprox(Float64(actual), Float64(expected); atol = Float64(atol), rtol = 0.0)
end

"""
    list_golden_spec_ids() -> Vector{String}

列出 `datasets/golden/*.json` 的 id（文件名不含扩展名）。
"""
function list_golden_spec_ids()
    ids = String[]
    for entry in readdir(GOLDEN_ROOT)
        endswith(entry, ".json") || continue
        push!(ids, replace(entry, ".json" => ""))
    end
    sort!(ids)
    return ids
end

"""
    validate_golden_spec_schema!(spec; require_model_type=true)

校验 golden JSON 必填字段；测试与 `scripts/golden/check_golden_json.jl` 共用逻辑。
"""
function validate_golden_spec_schema!(spec; require_model_type::Bool = true)
    for key in ("id", "dataset", "reference", "tolerances", "expected")
        haskey(spec, key) || error("golden spec missing key: $key")
    end
    require_model_type && haskey(spec, "model_type") ||
        error("golden spec missing model_type")
    ref = spec.reference
    for key in ("source", "generated_on", "regenerate", "notes")
        haskey(ref, key) || error("golden reference missing key: $key")
    end
    exp = spec.expected
    haskey(exp, "glance") || error("golden expected missing glance")
    haskey(exp, "tidy") || error("golden expected missing tidy")
    return nothing
end
