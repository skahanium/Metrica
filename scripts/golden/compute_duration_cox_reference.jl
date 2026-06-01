#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaDuration: fit_duration_cox

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "duration_cox")

df = CSV.read("$(CASE).csv", DataFrame)
r = fit_duration_cox(df, "ph ~ x1", "time", "fail"; ties = :efron)

tidy_rows = [tidy_dict("x1", r.beta[1], r.se[1], r.beta[1] / r.se[1])]
metrics = [
    metric_dict("n_events", r.n_events),
    metric_dict("loglik", r.loglik),
]

spec = Dict(
    "id" => "duration_cox",
    "dataset" => "golden/duration_cox.csv",
    "model_type" => "cox_ph",
    "formula" => "ph ~ x1",
    "time_column" => "time",
    "event_column" => "fail",
    "reference" => Dict(
        "source" => "MetricaDuration Cox Efron on 8-obs fixture; directionally consistent with R coxph.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=packages/MetricaDuration.jl scripts/golden/compute_duration_cox_reference.jl",
        "notes" => "Small-sample survival teaching fixture.",
    ),
    "tolerances" => default_tolerances(),
    "expected" => Dict(
        "glance" => Dict("model" => "cox_ph", "nobs" => r.n, "dof" => 1),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
