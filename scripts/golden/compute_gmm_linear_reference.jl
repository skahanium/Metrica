#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase, MetricaGMM

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "gmm_linear")

df = CSV.read("$(CASE).csv", DataFrame)
r = MetricaBase.fit(
    GMMLinearModel,
    "y ~ x1 + x2",
    df;
    instruments = ["z1", "z2"],
    endog = ["x1"],
    gmm_weight = "two_step",
)
g = glance(r)
t = tidy(r)

tidy_rows = [
    tidy_dict(row.name, row.estimate, row.stderror, row.statistic)
    for row in t.rows
    if isfinite(row.estimate) && isfinite(row.stderror) && isfinite(row.statistic)
]
d = r.gmm_diagnostics
metrics = [
    metric_dict("j_statistic", Float64(get(d, :j_statistic, 0.0))),
    metric_dict("j_df", Float64(get(d, :j_df, 0))),
]

spec = Dict(
    "id" => "gmm_linear",
    "dataset" => "golden/gmm_linear.csv",
    "model_type" => "gmm_linear",
    "formula" => "y ~ x1 + x2",
    "instruments" => ["z1", "z2"],
    "endog_columns" => ["x1"],
    "reference" => Dict(
        "source" => "MetricaGMM two-step GMM on fixed IV-GMM teaching fixture.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=scripts/golden scripts/golden/compute_gmm_linear_reference.jl",
        "notes" => "Over-identified; locks J statistic and core coefficients.",
    ),
    "tolerances" => default_tolerances(),
    "expected" => Dict(
        "glance" => Dict("model" => "gmm_linear", "nobs" => g.nobs, "dof" => g.dof),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
