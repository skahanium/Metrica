#!/usr/bin/env julia
"""
    check_model_type_alignment.jl

Script to verify that the list of supported model_type values is consistent
across:
  - Rust: `model_required_fields()` keys (HashMap in validation/required.rs)
  - Julia: `MODEL_REGISTRY` keys (populated by each package __init__)
  - README: model_type table entries

Exit code 0 if aligned, 1 with a diff if misaligned.
"""

using Test

# ----- Extract Rust model_type list from validation/required.rs -----
function parse_rust_model_types(filepath::String)::Vector{String}
    types = String[]
    content = read(filepath, String)
    for m in eachmatch(r"\(\"([^\"]+)\"\s*,\s*vec!", content)
        push!(types, m[1])
    end
    sort!(types)
    return types
end

# ----- Extract Julia MODEL_REGISTRY keys -----
function parse_julia_model_types(packages_dir::String)::Vector{String}
    # Keep this check lightweight enough to run without full package loading.
    # Instead, grep __init__() for register_model / MODEL_REGISTRY[...] = ...
    types = String[]
    for (root, dirs, files) in walkdir(packages_dir)
        for file in files
            if !endswith(file, ".jl")
                continue
            end
            path = joinpath(root, file)
            open(path) do f
                for line in eachline(f)
                    # Match: MODEL_REGISTRY["some_type"] = ... or register_model("some_type", ...)
                    matched = false
                    for m in eachmatch(r"""MODEL_REGISTRY\["([^"]+)"\]""", line)
                        push!(types, m[1])
                        matched = true
                    end
                    for m in eachmatch(r"""register_model\("([^"]+)"\s*,""", line)
                        push!(types, m[1])
                        matched = true
                    end
                    for m in eachmatch(r""""([a-z0-9_]+)"\s*=>\s*[A-Za-z0-9_]+Model\b""", line)
                        push!(types, m[1])
                        matched = true
                    end
                end
            end
        end
    end
    sort!(unique!(types))
    return types
end

# ----- Extract README model_type table entries -----
function parse_readme_model_types(filepath::String)::Vector{String}
    types = String[]
    in_table = false
    open(filepath) do f
        for line in eachline(f)
            if occursin(r"^\|\s*-+", strip(line))
                in_table = true
                continue
            end
            if in_table && startswith(strip(line), "|")
                # Row: | Linear | `ols`, `iv`, `gls`, `gmm_linear` | ... |
                for m in eachmatch(r"""`([^`]+)`""", line)
                    push!(types, strip(m[1]))
                end
            else
                in_table = false
            end
        end
    end
    sort!(unique!(types))
    return types
end

# ----- Extract Rust *Params struct field names -----
function parse_rust_params_fields(filepath::String)::Dict{String, Vector{String}}
    text = read(filepath, String)
    out = Dict{String, Vector{String}}()
    for m in eachmatch(r"pub struct (\w+Params)\s*\{([^}]*)\}"s, text)
        name = m.captures[1]
        body = m.captures[2]
        fields = String[]
        for fm in eachmatch(r"pub\s+(\w+)\s*:", body)
            push!(fields, fm.captures[1])
        end
        out[name] = sort!(fields)
    end
    return out
end

# ----- Extract TypeScript *Spec interface property names -----
function parse_ts_spec_fields(filepath::String)::Dict{String, Vector{String}}
    text = read(filepath, String)
    out = Dict{String, Vector{String}}()
    skip = Set(["model_type", "formula", "vcov", "weights", "cluster_column"])
    for m in eachmatch(r"export interface (\w+Spec) extends ModelSpecCore\s*\{([^}]*)\}"s, text)
        name = m.captures[1]
        body = m.captures[2]
        fields = String[]
        for fm in eachmatch(r"(\w+)\??:", body)
            f = fm.captures[1]
            f in skip && continue
            push!(fields, f)
        end
        out[name] = sort!(unique!(fields))
    end
    return out
end

const PARAM_SPEC_PAIRS = [
    ("LinearParams", "LinearSpec"),
    ("PanelParams", "PanelSpec"),
    ("CausalParams", "CausalSpec"),
    ("TimeSeriesParams", "TimeSeriesSpec"),
    ("SurveyParams", "SurveySpec"),
    ("SystemParams", "SystemSpec"),
    ("SpatialParams", "SpatialSpec"),
    ("DurationParams", "DurationSpec"),
    ("BayesParams", "BayesSpec"),
    ("NonlinearParams", "NonlinearSpec"),
    ("QuantileParams", "QuantileSpec"),
    ("DiscreteParams", "DiscreteSpec"),
]

# ----- Main -----
repo_root = abspath(joinpath(@__FILE__, "..", ".."))
rust_file = joinpath(repo_root, "runtime", "metrica-runtime", "src", "validation", "required.rs")
readme_file = joinpath(repo_root, "README.md")
packages_dir = joinpath(repo_root, "packages")

rust_types = parse_rust_model_types(rust_file)
julia_types = parse_julia_model_types(packages_dir)
readme_types = parse_readme_model_types(readme_file)

println("── model_type alignment check ──")
println("\nRust  validation/required.rs  entries:  ", length(rust_types))
println("Julia MODEL_REGISTRY entries:   ", length(julia_types))
println("README table entries:           ", length(readme_types))

any_mismatch = false

# Rust vs Julia
diff_rust_julia = setdiff(rust_types, julia_types)
if !isempty(diff_rust_julia)
    any_mismatch = true
    println("\n❌ In Rust but NOT in Julia MODEL_REGISTRY:")
    for t in diff_rust_julia
        println("   - $t")
    end
end

diff_julia_rust = setdiff(julia_types, rust_types)
if !isempty(diff_julia_rust)
    any_mismatch = true
    println("\n❌ In Julia MODEL_REGISTRY but NOT in Rust:")
    for t in diff_julia_rust
        println("   - $t")
    end
end

# Rust vs README
diff_rust_readme = setdiff(rust_types, readme_types)
if !isempty(diff_rust_readme)
    any_mismatch = true
    println("\n❌ In Rust but NOT in README table:")
    for t in diff_rust_readme
        println("   - $t")
    end
end

diff_readme_rust = setdiff(readme_types, rust_types)
if !isempty(diff_readme_rust)
    any_mismatch = true
    println("\n❌ In README table but NOT in Rust:")
    for t in diff_readme_rust
        println("   - $t")
    end
end

# ----- Rust Params vs TypeScript Spec field names -----
rust_params_file = joinpath(repo_root, "runtime", "metrica-runtime", "src", "model_params.rs")
ts_protocol_file = joinpath(repo_root, "apps", "metrica-desktop", "src-react", "types", "protocol.ts")
rust_fields = parse_rust_params_fields(rust_params_file)
ts_fields = parse_ts_spec_fields(ts_protocol_file)

println("\n── params field alignment (Rust ↔ TypeScript) ──")
global fields_mismatch = false
for (rust_name, ts_name) in PARAM_SPEC_PAIRS
    rf = get(rust_fields, rust_name, String[])
    tf = get(ts_fields, ts_name, String[])
    if rust_name == "CausalParams"
        panel_ts = get(ts_fields, "PanelSpec", String[])
        tf = union(tf, intersect(panel_ts, rf))
    end
    if isempty(rf) && isempty(tf)
        continue
    end
    only_rust = setdiff(rf, tf)
    only_ts = setdiff(tf, rf)
    if !isempty(only_rust) || !isempty(only_ts)
        global fields_mismatch = true
        println("\n❌ $rust_name ↔ $ts_name:")
        for f in only_rust
            println("   Rust only: $f")
        end
        for f in only_ts
            println("   TS only:   $f")
        end
    end
end

# Panel/DID fields live on PanelSpec in TS but also in Rust CausalParams — report as info only
causal_rust = get(rust_fields, "CausalParams", String[])
causal_ts = get(ts_fields, "CausalSpec", String[])
panel_ts = get(ts_fields, "PanelSpec", String[])
causal_only_rust = setdiff(causal_rust, union(causal_ts, panel_ts))
if !isempty(causal_only_rust)
    println("\nℹ️  CausalParams fields mapped to PanelSpec in TS (expected split):")
    for f in causal_only_rust
        println("   - $f")
    end
end

if any_mismatch || fields_mismatch
    println("\n❌ model_type alignment check FAILED")
    exit(1)
else
    println("\n✅ model_type alignment check PASSED — all sources agree")
    exit(0)
end
