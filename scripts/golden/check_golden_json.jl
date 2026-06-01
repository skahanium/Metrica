#!/usr/bin/env julia
# 校验所有 golden JSON schema；CI nightly / 本地维护用。
# 用法：julia --project=scripts/golden scripts/golden/check_golden_json.jl

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
using JSON3
include(joinpath(ROOT, "packages", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

function main()
    ids = list_golden_spec_ids()
    isempty(ids) && error("no golden specs found")
    for id in ids
        spec = load_golden_spec(id)
        validate_golden_spec_schema!(spec)
        golden_dataset_path(spec)
        @info "ok" id
    end
    println("✅ $(length(ids)) golden spec(s) validated")
end

main()
