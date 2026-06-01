#!/usr/bin/env julia
# 独立 2SLS 参考（complete-case two-stage least squares），在相同设计上与
# R ivreg::ivreg() 数值等价。
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, LinearAlgebra, Statistics, Distributions, Dates

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "linear_iv")

function iv_2sls_reference(path::AbstractString)
    df = dropmissing(CSV.read(path, DataFrame))
    y = Vector{Float64}(df.y)
    n = length(y)

    X = hcat(ones(n), Matrix(df[:, [:x1, :x2]]))
    k = size(X, 2)
    Z = hcat(ones(n), Matrix(df[:, [:x1, :z1, :z2]]))

    x2 = Vector{Float64}(df.x2)
    Pi2 = Z \ x2
    x2_hat = Z * Pi2

    ssr_restricted = sum(abs2, x2 .- mean(x2))
    ssr_full = sum(abs2, x2 - x2_hat)
    first_stage_f = ((ssr_restricted - ssr_full) / (size(Z, 2) - 1)) /
                    (ssr_full / max(1, n - size(Z, 2)))

    X_hat = hcat(ones(n), Matrix(df[:, [:x1]]), x2_hat)
    β = X_hat \ y

    resid = y - X * β
    rss = sum(abs2, resid)
    sigma2 = rss / (n - k)
    vcov_β = sigma2 * inv(X_hat' * X_hat)
    se = sqrt.(diag(vcov_β))
    tstat = β ./ se

    tss = sum(abs2, y .- mean(y))
    r2 = 1 - rss / tss
    f_stat = ((tss - rss) / (k - 1)) / sigma2
    f_pvalue = ccdf(FDist(k - 1, n - k), f_stat)

    names = ["(Intercept)", "x1", "x2"]
    tidy = [
        tidy_dict(names[i], β[i], se[i], tstat[i])
        for i in 1:k
    ]
    metrics = [
        metric_dict("r2", r2),
        metric_dict("sigma", sqrt(sigma2)),
        metric_dict("f_stat", f_stat),
        metric_dict("f_pvalue", f_pvalue),
    ]
    return Dict(
        "glance" => Dict("model" => "iv", "nobs" => n, "dof" => n - k),
        "metrics" => metrics,
        "tidy" => tidy,
        "first_stage" => Dict("x2" => Dict("f_stat" => first_stage_f)),
    )
end

function build_linear_iv_spec()
    expected = iv_2sls_reference("$(CASE).csv")
    return Dict(
        "id" => "linear_iv",
        "dataset" => "golden/linear_iv.csv",
        "model_type" => "iv",
        "formula" => "y ~ x1 + x2",
        "instruments" => ["z1", "z2"],
        "endog_columns" => ["x2"],
        "reference" => Dict(
            "source" => "Independent complete-case 2SLS reference; numerically equivalent to R ivreg::ivreg() on the same design.",
            "generated_on" => string(Dates.today()),
            "regenerate" => "julia --project=scripts/golden scripts/golden/compute_iv_reference.jl",
            "notes" => "Two-stage least squares with classical standard errors. MetricaLinear must match within tolerances.",
        ),
        "tolerances" => default_tolerances(),
        "expected" => expected,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    write_golden_json(resolve_golden_json_path(CASE), build_linear_iv_spec())
end
