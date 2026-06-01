#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaTimeSeries

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "timeseries_arima")

df = CSV.read("$(CASE).csv", DataFrame)
result = MetricaBase.fit(
    ARIMAModel(variable = :y, time_column = :time, order = (1, 0, 0), method = :css),
    df,
)
g = glance(result)
t = tidy(result)

tidy_rows = [
    tidy_dict(row.name, row.estimate, row.stderror, row.statistic)
    for row in t.rows
    if isfinite(row.estimate) && isfinite(row.stderror) && isfinite(row.statistic)
]
metrics = [metric_dict(k, g.metrics[k]) for k in sort(collect(keys(g.metrics))) if isfinite(g.metrics[k])]

spec = Dict(
    "id" => "timeseries_arima",
    "dataset" => "golden/timeseries_arima.csv",
    "model_type" => "arima",
    "formula" => "y ~ arima(1,0,0)",
    "reference" => Dict(
        "source" => "MetricaTimeSeries CSS ARIMA(1,0,0) on 20-obs deterministic series.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=scripts/golden scripts/golden/compute_timeseries_arima_reference.jl",
        "notes" => "Teaching-grade short series; not a Box-Jenkins benchmark.",
    ),
    "tolerances" => default_tolerances(),
    "expected" => Dict(
        "glance" => Dict("model" => string(g.model), "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
