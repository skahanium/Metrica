#!/usr/bin/env julia
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, Dates
using MetricaBase: PanelData
using MetricaPanel: fit_dynamic_panel_gmm

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "panel_dynamic_gmm")
const DATA = joinpath(ROOT, "datasets", "demo", "dynamic_panel_gmm_golden.csv")

df = CSV.read(DATA, DataFrame)
pd = PanelData(df, :firm, :year)
r = fit_dynamic_panel_gmm(pd, "y ~ x"; instrument_lags = (2, 4), gmm_weight = "two_step")

γ_idx = findfirst(n -> n == :L1Dy, r.coefficient_names)
β_idx = findfirst(n -> n == :D_x, r.coefficient_names)
γ_hat = r.coefficient_values[γ_idx]
β_hat = r.coefficient_values[β_idx]

tidy_rows = [
    tidy_dict("L1Dy", γ_hat, 0.0, 0.0),
    tidy_dict("D_x", β_hat, 0.0, 0.0),
]
metrics = [
    metric_dict("n_obs_diff", r.n_obs_diff),
    metric_dict("treat_effect_proxy", β_hat),
]

spec = Dict(
    "id" => "panel_dynamic_gmm",
    "dataset" => "demo/dynamic_panel_gmm_golden.csv",
    "model_type" => "dynamic_panel_gmm",
    "formula" => "y ~ x",
    "panel_id" => "firm",
    "panel_time" => "year",
    "instrument_lags" => [2, 4],
    "reference" => Dict(
        "source" => "MetricaPanel difference GMM two-step on deterministic demo fixture; aligns with package test S5.2.",
        "generated_on" => string(Dates.today()),
        "regenerate" => "julia --project=packages/MetricaPanel.jl scripts/golden/compute_panel_dynamic_gmm_reference.jl",
        "notes" => "Locks L1Dy and D_x coefficients; SE not in golden yet.",
    ),
    "tolerances" => [
        Dict("name" => "coefficient", "atol" => 1.0e-10),
        Dict("name" => "metric", "atol" => 1.0e-10),
    ],
    "expected" => Dict(
        "glance" => Dict("model" => "dynamic_panel_gmm", "nobs" => r.n_obs_diff, "dof" => 0),
        "metrics" => metrics,
        "tidy" => tidy_rows,
    ),
)
write_golden_json(resolve_golden_json_path(CASE), spec)
