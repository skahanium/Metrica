#!/usr/bin/env julia
# 独立 OLS 参考（complete-case X\\y），与 R stats::lm 在相同设计上数值等价。
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, LinearAlgebra, Statistics, Dates

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "linear_ols")

function ols_reference(path::AbstractString)
    df = dropmissing(CSV.read(path, DataFrame))
    y = Vector{Float64}(df.y)
    X = hcat(ones(length(y)), Matrix(df[:, [:x1, :x2]]))
    β = X \ y
    n, k = size(X)
    resid = y - X * β
    rss = sum(abs2, resid)
    tss = sum(abs2, y .- mean(y))
    r2 = 1 - rss / tss
    adj = 1 - (1 - r2) * (n - 1) / (n - k)
    σ = sqrt(rss / (n - k))
    se = σ .* sqrt.(diag(inv(X' * X)))
    tstat = β ./ se
    names = ["(Intercept)", "x1", "x2"]
    tidy = [
        tidy_dict(names[i], β[i], se[i], tstat[i])
        for i in 1:k
    ]
    metrics = [
        metric_dict("r2", r2),
        metric_dict("adj_r2", adj),
        metric_dict("rss", rss),
        metric_dict("tss", tss),
        metric_dict("sigma", σ),
    ]
    return Dict(
        "glance" => Dict("model" => "ols", "nobs" => n, "dof" => n - k),
        "metrics" => metrics,
        "tidy" => tidy,
    )
end

function build_linear_ols_spec()
    expected = ols_reference("$(CASE).csv")
    return Dict(
        "id" => "linear_ols",
        "dataset" => "golden/linear_ols.csv",
        "model_type" => "ols",
        "formula" => "y ~ x1 + x2",
        "reference" => Dict(
            "source" => "Independent complete-case OLS (X\\\\y + classical SE); numerically equivalent to R stats::lm() on the same design.",
            "generated_on" => string(Dates.today()),
            "regenerate" => "julia --project=scripts/golden scripts/golden/compute_ols_reference.jl",
            "notes" => "Rows with missing model variables are dropped before fitting (7 obs). MetricaLinear must match within tolerances.",
        ),
        "tolerances" => default_tolerances(),
        "expected" => expected,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    write_golden_json(resolve_golden_json_path(CASE), build_linear_ols_spec())
end
