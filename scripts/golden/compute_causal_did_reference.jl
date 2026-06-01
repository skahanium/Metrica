#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaCausal

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "causal_did")

df = CSV.read("$(CASE).csv", DataFrame)
result = MetricaBase.fit(
    DIDModel,
    "y ~ treated * post + x1",
    df;
    panel_id = :id,
    panel_time = :time,
    treated_column = :treated,
    post_column = :post,
)
g = glance(result)

metrics = [
    metric_dict("treat_effect", result.treat_effect),
    metric_dict("treat_effect_se", result.treat_effect_se),
]
tidy_rows = [tidy_dict("treat_effect", result.treat_effect, result.treat_effect_se, result.treat_effect / result.treat_effect_se)]

spec = Dict(
    "id" => "causal_did",
    "dataset" => "golden/causal_did.csv",
    "model_type" => "did",
    "formula" => "y ~ treated * post + x1",
    "reference" => Dict(
        "source" => "MetricaCausal DID TWFE on deterministic 40-obs panel; true interaction effect 2.0 in DGP.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=packages/MetricaCausal.jl scripts/golden/compute_causal_did_reference.jl",
        "notes" => "treat_effect is the reported ATT-style summary.",
    ),
    "tolerances" => [
        Dict("name" => "coefficient", "atol" => 0.05),
        Dict("name" => "stderror", "atol" => 0.05),
        Dict("name" => "statistic", "atol" => 0.05),
        Dict("name" => "metric", "atol" => 0.05),
    ],
    "expected" => Dict(
        "glance" => Dict("model" => "did", "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
