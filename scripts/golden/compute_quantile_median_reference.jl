#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaQuantile

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "quantile_median")

result = MetricaBase.fit(
    QuantileModel,
    "y ~ x1 + x2",
    "$(CASE).csv";
    quantile_tau = 0.5,
)
g = glance(result)
t = tidy(result)

tidy_rows = [
    tidy_dict(row.name, row.estimate, row.stderror, row.statistic)
    for row in t.rows
    if !isnothing(row.stderror) && isfinite(row.estimate) && isfinite(row.stderror) && isfinite(row.statistic)
]
metrics = [
    metric_dict(k, g.metrics[k])
    for k in (:tau, :pseudo_r2)
    if haskey(g.metrics, k) && g.metrics[k] !== nothing && isfinite(Float64(g.metrics[k]))
]

spec = Dict(
    "id" => "quantile_median",
    "dataset" => "golden/quantile_median.csv",
    "model_type" => "quantile",
    "formula" => "y ~ x1 + x2",
    "quantile_tau" => 0.5,
    "reference" => Dict(
        "source" => "MetricaQuantile median regression (τ=0.5) on datasets/demo/quantile_demo copy.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=scripts/golden scripts/golden/compute_quantile_median_reference.jl",
        "notes" => "Hall–Sheather asymptotic SE; tolerances allow minor solver drift.",
    ),
    "tolerances" => [
        Dict("name" => "coefficient", "atol" => 1.0e-6),
        Dict("name" => "stderror", "atol" => 1.0e-5),
        Dict("name" => "statistic", "atol" => 1.0e-5),
        Dict("name" => "metric", "atol" => 1.0e-6),
    ],
    "expected" => Dict(
        "glance" => Dict("model" => string(g.model), "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
