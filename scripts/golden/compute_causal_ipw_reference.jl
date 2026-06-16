#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates, Random
using MetricaBase, MetricaCausal

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "causal_ipw")

function write_ipw_csv(path::AbstractString)
    Random.seed!(2024)
    n = 200
    x1 = randn(n)
    x2 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8 * x1 .- 0.3 * x2)))
    treat = Float64.(rand(n) .< ps)
    y0 = 2.0 .+ 0.5 * x1 .+ 0.2 * x2 .+ randn(n) * 0.3
    y1 = y0 .+ 1.5
    y = treat .* y1 .+ (1 .- treat) .* y0
    df = DataFrame(treat = treat, y = y, x1 = x1, x2 = x2)
    CSV.write(path, df)
    return df
end

isfile("$(CASE).csv") || write_ipw_csv("$(CASE).csv")
df = CSV.read("$(CASE).csv", DataFrame)

result = MetricaBase.fit(
    IPWModel,
    "",
    df;
    treatment_column = :treat,
    outcome_column = :y,
    propensity_formula = "treat ~ x1 + x2",
)
g = glance(result)
t = tidy(result)

tidy_rows = [
    tidy_dict(row.name, row.estimate, row.stderror, row.statistic)
    for row in t.rows
    if isfinite(row.estimate) && isfinite(row.stderror) && isfinite(row.statistic)
]
metrics = [
    metric_dict("ate", result.ate),
    metric_dict("att", result.att),
    metric_dict("atu", result.atu),
]

spec = Dict(
    "id" => "causal_ipw",
    "dataset" => "golden/causal_ipw.csv",
    "model_type" => "ipw",
    "propensity_formula" => "treat ~ x1 + x2",
    "treatment_column" => "treat",
    "outcome_column" => "y",
    "reference" => Dict(
        "source" => "MetricaCausal IPW with logit PS; DGP ATE=1.5, seed 2024, n=200.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=scripts/golden scripts/golden/compute_causal_ipw_reference.jl",
        "notes" => "CSV created on first regenerate if missing; delete CSV to force rewrite.",
    ),
    "tolerances" => [
        Dict("name" => "coefficient", "atol" => 0.15),
        Dict("name" => "stderror", "atol" => 0.15),
        Dict("name" => "statistic", "atol" => 0.15),
        Dict("name" => "metric", "atol" => 0.15),
    ],
    "expected" => Dict(
        "glance" => Dict("model" => string(g.model), "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
