#!/usr/bin/env julia
# 再生 golden JSON 并与已提交文件比对（忽略 reference.generated_on）。
# 独立参考（OLS/IV/GLS）仅比对 expected 段，不依赖 Metrica 拟合。
# 用法：REGENERATE_GOLDEN=check julia --project=scripts/golden scripts/golden/check_golden_drift.jl

const SCRIPT_DIR = @__DIR__
const ROOT = normpath(joinpath(SCRIPT_DIR, "..", ".."))
const GOLDEN_ROOT = joinpath(ROOT, "datasets", "golden")

using JSON3
include(joinpath(ROOT, "packages", "MetricaBase.jl", "test", "golden_test_helpers.jl"))
include(joinpath(SCRIPT_DIR, "_expected_compare.jl"))

const REGEN_SCRIPTS = [
    "compute_gmm_linear_reference.jl",
    "compute_timeseries_arima_reference.jl",
    "compute_discrete_logit_reference.jl",
    "compute_discrete_probit_reference.jl",
    "compute_discrete_poisson_reference.jl",
    "compute_panel_dynamic_gmm_reference.jl",
    "compute_duration_cox_reference.jl",
    "compute_causal_did_reference.jl",
    "compute_system_sur_reference.jl",
]

const INDEPENDENT_CHECKS = [
    ("linear_ols", "compute_ols_reference.jl", :ols_reference),
    ("linear_iv", "compute_iv_reference.jl", :iv_2sls_reference),
    ("linear_gls", "compute_gls_reference.jl", :gls_reference),
]

function strip_generated_on!(obj)
    if obj isa AbstractDict
        if haskey(obj, "reference") && obj["reference"] isa AbstractDict
            delete!(obj["reference"], "generated_on")
        end
        for v in values(obj)
            strip_generated_on!(v)
        end
    elseif obj isa AbstractVector
        for v in obj
            strip_generated_on!(v)
        end
    end
    return obj
end

function load_json_object(path::AbstractString)
    return JSON3.read(read(path, String), Dict{String, Any})
end

function compare_golden_json(committed_path::AbstractString, fresh_path::AbstractString)
    a = load_json_object(committed_path)
    b = load_json_object(fresh_path)
    strip_generated_on!(a)
    strip_generated_on!(b)
    if a != b
        error("golden drift: $(committed_path) differs from regenerated $(fresh_path)")
    end
end

function check_independent_reference!(id::AbstractString, fn_sym::Symbol)
    spec = load_golden_spec(id)
    csv_path = golden_dataset_path(spec)
    fresh_expected = Base.invokelatest(getfield(Main, fn_sym), csv_path)
    compare_spec_expected_to_fresh!(spec, fresh_expected)
    @info "independent drift ok" id fn_sym
end

function load_independent_reference_functions!()
    seen = Set{String}()
    for (_, script, _) in INDEPENDENT_CHECKS
        script in seen && continue
        push!(seen, script)
        include(joinpath(SCRIPT_DIR, script))
    end
end

function main()
    get(ENV, "REGENERATE_GOLDEN", "") == "check" ||
        error("set REGENERATE_GOLDEN=check to run drift detection")

    load_independent_reference_functions!()
    for (id, _, fn_sym) in INDEPENDENT_CHECKS
        check_independent_reference!(id, fn_sym)
    end

    for script in REGEN_SCRIPTS
        tmp = mktempdir()
        ENV["GOLDEN_JSON_OUTPUT_DIR"] = tmp
        try
            include(joinpath(SCRIPT_DIR, script))
        finally
            pop!(ENV, "GOLDEN_JSON_OUTPUT_DIR", nothing)
        end
        json_files = filter(f -> endswith(f, ".json"), readdir(tmp))
        length(json_files) == 1 ||
            error("expected one JSON from $script, got $(json_files)")
        id = replace(first(json_files), ".json" => "")
        committed = joinpath(GOLDEN_ROOT, "$(id).json")
        isfile(committed) || error("committed golden missing: $committed")
        compare_golden_json(committed, joinpath(tmp, first(json_files)))
        @info "metrica drift ok" script id
    end

    n = length(INDEPENDENT_CHECKS) + length(REGEN_SCRIPTS)
    println("✅ golden drift check passed ($n checks: $(length(INDEPENDENT_CHECKS)) independent + $(length(REGEN_SCRIPTS)) Metrica regenerators)")
end

main()
