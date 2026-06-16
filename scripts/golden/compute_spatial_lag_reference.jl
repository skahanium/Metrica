#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaSpatial

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "spatial_lag")
const W_PATH = joinpath(ROOT, "datasets", "golden", "spatial_lag_W.csv")

df = CSV.read("$(CASE).csv", DataFrame)
spec_params = Dict{String, Any}(
    "spatial_weights_path" => W_PATH,
    "spatial_id_column" => "region",
    "spatial_row_standardize" => true,
    "vcov" => "classical",
)
result = MetricaSpatial.fit_spatial("spatial_lag", "y ~ x1", df, spec_params, ROOT)
g = glance(result)
t = tidy(result)

tidy_rows = [
    tidy_dict(row.name, row.estimate, row.stderror, row.statistic)
    for row in t.rows
    if isfinite(row.estimate) && isfinite(row.stderror) && isfinite(row.statistic)
]
metrics = [metric_dict("rho", result.diagnostics[:rho])]
if haskey(result.diagnostics, :moran_i) && result.diagnostics[:moran_i] !== nothing
    push!(metrics, metric_dict("moran_i", result.diagnostics[:moran_i]))
end

spec = Dict(
    "id" => "spatial_lag",
    "dataset" => "golden/spatial_lag.csv",
    "model_type" => "spatial_lag",
    "formula" => "y ~ x1",
    "spatial_weights_path" => "golden/spatial_lag_W.csv",
    "spatial_id_column" => "region",
    "spatial_row_standardize" => true,
    "reference" => Dict(
        "source" => "MetricaSpatial SAR (spatial_lag) on 5-region demo with bundled W matrix.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=scripts/golden scripts/golden/compute_spatial_lag_reference.jl",
        "notes" => "Weights resolved relative to repo datasets/golden/ at test time.",
    ),
    "tolerances" => [
        Dict("name" => "coefficient", "atol" => 1.0e-6),
        Dict("name" => "stderror", "atol" => 1.0e-5),
        Dict("name" => "statistic", "atol" => 1.0e-5),
        Dict("name" => "metric", "atol" => 1.0e-5),
    ],
    "expected" => Dict(
        "glance" => Dict("model" => string(g.model), "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
