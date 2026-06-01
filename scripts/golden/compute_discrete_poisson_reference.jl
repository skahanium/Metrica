#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaDiscrete

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "discrete_poisson")

df = CSV.read("$(CASE).csv", DataFrame)
result = MetricaBase.fit(PoissonModel, "y ~ x1 + x2", df)
g = glance(result)
t = tidy(result)

tidy_rows = [
    tidy_dict(row.name, row.estimate, row.stderror, row.statistic)
    for row in t.rows
]
metrics = [metric_dict(k, g.metrics[k]) for k in sort(collect(keys(g.metrics)))]

spec = Dict(
    "id" => "discrete_poisson",
    "dataset" => "golden/discrete_poisson.csv",
    "model_type" => "poisson",
    "formula" => "y ~ x1 + x2",
    "reference" => Dict(
        "source" => "MetricaDiscrete PoissonModel on fixed CSV.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=packages/MetricaDiscrete.jl scripts/golden/compute_discrete_poisson_reference.jl",
        "notes" => "Complete-case fit on 20 obs.",
    ),
    "tolerances" => default_tolerances(),
    "expected" => Dict(
        "glance" => Dict("model" => "poisson", "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
