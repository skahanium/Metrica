#!/usr/bin/env julia
"""
    check_model_type_alignment.jl

CI script to verify that the list of supported model_type values is consistent
across:
  - Rust: `model_required_fields()` keys (HashMap in validation.rs)
  - Julia: `MODEL_REGISTRY` keys (populated by each package __init__)
  - README: model_type table entries

Exit code 0 if aligned, 1 with a diff if misaligned.
"""

using Test

# ----- Extract Rust model_type list from validation.rs -----
function parse_rust_model_types(filepath::String)::Vector{String}
    types = String[]
    open(filepath) do f
        for line in eachline(f)
            # Match lines like: ("ols", vec![]), or ("iv", vec!["instruments", ...]),
            m = match(r"""^\s*\(\s*"([^"]+)"\s*,.*\),?$""", line)
            if m !== nothing
                push!(types, m[1])
            end
        end
    end
    sort!(types)
    return types
end

# ----- Extract Julia MODEL_REGISTRY keys -----
function parse_julia_model_types(packages_dir::String)::Vector{String}
    # We cannot run Julia with full package loading in CI easily.
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

# ----- Main -----
repo_root = abspath(joinpath(@__FILE__, "..", ".."))
rust_file = joinpath(repo_root, "runtime", "metrica-runtime", "src", "validation.rs")
readme_file = joinpath(repo_root, "README.md")
packages_dir = joinpath(repo_root, "packages")

rust_types = parse_rust_model_types(rust_file)
julia_types = parse_julia_model_types(packages_dir)
readme_types = parse_readme_model_types(readme_file)

println("── model_type alignment check ──")
println("\nRust  validation.rs  entries:  ", length(rust_types))
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

if any_mismatch
    println("\n❌ model_type alignment check FAILED")
    exit(1)
else
    println("\n✅ model_type alignment check PASSED — all sources agree")
    exit(0)
end
