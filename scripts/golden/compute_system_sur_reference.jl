#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaSystem

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "system_sur")
const DATA = joinpath(ROOT, "datasets", "demo", "sur_system_demo.csv")

r = MetricaBase.fit(SURModel, "", DATA; equations = ["y1 ~ x1 + x2", "y2 ~ x1 + x2"])
g = glance(r)
t = tidy(r)

tidy_rows = [
    tidy_dict(row.name, row.estimate, row.stderror, row.statistic)
    for row in t.rows
    if isfinite(row.estimate) && isfinite(row.stderror) && isfinite(row.statistic)
]
metrics = [
    metric_dict(k, g.metrics[k])
    for k in sort(collect(keys(g.metrics)))
    if isfinite(Float64(g.metrics[k]))
]

spec = Dict(
    "id" => "system_sur",
    "dataset" => "demo/sur_system_demo.csv",
    "model_type" => "sur",
    "equations" => ["y1 ~ x1 + x2", "y2 ~ x1 + x2"],
    "reference" => Dict(
        "source" => "MetricaSystem SUR FGLS on demo/sur_system_demo.csv.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=packages/MetricaSystem.jl scripts/golden/compute_system_sur_reference.jl",
        "notes" => "Two-equation SUR; complete-case on demo CSV.",
    ),
    "tolerances" => default_tolerances(),
    "expected" => Dict(
        "glance" => Dict("model" => "sur", "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
