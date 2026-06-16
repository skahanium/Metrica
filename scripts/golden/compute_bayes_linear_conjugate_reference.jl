#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaBayes

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "bayes_linear_conjugate")

df = CSV.read("$(CASE).csv", DataFrame)
result = MetricaBayes.fit_bayes_linear(
    df,
    "y ~ x1";
    bayes_sigma2_known = true,
    bayes_sigma2_value = 0.25,
    bayes_prior_scale = 10.0,
)
g = glance(result)
t = tidy(result)

tidy_rows = [
    Dict(
        "name" => String(row.name),
        "estimate" => _finite_json_float(row.estimate),
        "stderror" => 0.0,
        "statistic" => 0.0,
    )
    for row in t.rows
]
metrics = [
    metric_dict("prior_family", g.metrics[:prior_family]),
]
if haskey(g.metrics, :log_marginal_likelihood) && isfinite(Float64(g.metrics[:log_marginal_likelihood]))
    push!(metrics, metric_dict("log_marginal_likelihood", g.metrics[:log_marginal_likelihood]))
end

spec = Dict(
    "id" => "bayes_linear_conjugate",
    "dataset" => "golden/bayes_linear_conjugate.csv",
    "model_type" => "bayes_linear",
    "formula" => "y ~ x1",
    "reference" => Dict(
        "source" => "MetricaBayes NIG conjugate with known σ²=0.25; deterministic 8-obs teaching set.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=scripts/golden scripts/golden/compute_bayes_linear_conjugate_reference.jl",
        "notes" => "Summary-level golden (posterior means); not MCMC trace.",
    ),
    "tolerances" => default_tolerances(),
    "expected" => Dict(
        "glance" => Dict("model" => string(g.model), "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
