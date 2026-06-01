#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaDiscrete

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "discrete_logit")

df = CSV.read("$(CASE).csv", DataFrame)
result = MetricaBase.fit(LogitModel, "y ~ x1 + x2", df)
g = glance(result)
t = tidy(result)

tidy_rows = [
    tidy_dict(row.name, row.estimate, row.stderror, row.statistic)
    for row in t.rows
]
metrics = [metric_dict(k, g.metrics[k]) for k in sort(collect(keys(g.metrics)))]

spec = Dict(
    "id" => "discrete_logit",
    "dataset" => "golden/discrete_logit.csv",
    "model_type" => "logit",
    "formula" => "y ~ x1 + x2",
    "reference" => Dict(
        "source" => "MetricaDiscrete LogitModel on fixed CSV; independent check against R glm(..., family=binomial) planned for L3.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=packages/MetricaDiscrete.jl scripts/golden/compute_discrete_logit_reference.jl",
        "notes" => "Complete-case fit on 20 obs.",
    ),
    "tolerances" => default_tolerances(),
    "expected" => Dict(
        "glance" => Dict("model" => "logit", "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
