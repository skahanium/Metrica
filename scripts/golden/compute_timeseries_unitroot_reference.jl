#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates, Random
using MetricaBase, MetricaTimeSeries

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "timeseries_unitroot")

function write_unitroot_csv(path::AbstractString)
    n = 80
    Random.seed!(1234)
    y = zeros(n)
    y[1] = randn()
    for t in 2:n
        y[t] = 0.5 * y[t - 1] + randn()
    end
    CSV.write(path, DataFrame(time = 1:n, y = y))
end

isfile("$(CASE).csv") || write_unitroot_csv("$(CASE).csv")
df = CSV.read("$(CASE).csv", DataFrame)

result = MetricaBase.fit(
    UnitRootModel(variable = :y, time_column = :time, deterministic = :constant),
    df,
)
g = glance(result)
t = tidy(result)

tidy_rows = [
    begin
        se = something(row.stderror, 0.0)
        stat = something(row.statistic, 0.0)
        tidy_dict(row.name, row.estimate, se, stat)
    end
    for row in t.rows
    if isfinite(row.estimate)
]
metrics = [metric_dict("n_tests", Float64(length(t.rows)))]

spec = Dict(
    "id" => "timeseries_unitroot",
    "dataset" => "golden/timeseries_unitroot.csv",
    "model_type" => "unitroot",
    "formula" => "y ~ unitroot",
    "time_column" => "time",
    "variable" => "y",
    "reference" => Dict(
        "source" => "MetricaTimeSeries ADF/PP/KPSS bundle; AR(1) φ=0.5, seed 1234, n=80.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=scripts/golden scripts/golden/compute_timeseries_unitroot_reference.jl",
        "notes" => "Locks test statistics in tidy rows (ADF, PP, KPSS).",
    ),
    "tolerances" => default_tolerances(),
    "expected" => Dict(
        "glance" => Dict("model" => string(g.model), "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
