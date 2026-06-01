#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaDiscrete

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "discrete_probit")

df = CSV.read("$(CASE).csv", DataFrame)
result = MetricaBase.fit(ProbitModel, "y ~ x1 + x2", df)
g = glance(result)
t = tidy(result)

tidy_rows = [
    tidy_dict(row.name, row.estimate, row.stderror, row.statistic)
    for row in t.rows
]
metrics = [metric_dict(k, g.metrics[k]) for k in sort(collect(keys(g.metrics)))]

spec = Dict(
    "id" => "discrete_probit",
    "dataset" => "golden/discrete_probit.csv",
    "model_type" => "probit",
    "formula" => "y ~ x1 + x2",
    "reference" => Dict(
        "source" => "MetricaDiscrete ProbitModel on fixed CSV.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=packages/MetricaDiscrete.jl scripts/golden/compute_discrete_probit_reference.jl",
        "notes" => "Complete-case fit on 20 obs.",
    ),
    "tolerances" => default_tolerances(),
    "expected" => Dict(
        "glance" => Dict("model" => "probit", "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
