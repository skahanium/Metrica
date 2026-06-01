#!/usr/bin/env julia
# 独立 2SLS 参考（complete-case two-stage least squares），在相同设计上与
# R ivreg::ivreg() 数值等价。
# 用法：julia scripts/golden/compute_iv_reference.jl

using DataFrames, CSV, LinearAlgebra, Statistics, Distributions, JSON3

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "linear_iv")

function iv_2sls_reference(path::AbstractString)
    df = dropmissing(CSV.read(path, DataFrame))
    y = Vector{Float64}(df.y)
    n = length(y)

    # Design matrix X = [1, x1, x2] (includes endogenous x2)
    X = hcat(ones(n), Matrix(df[:, [:x1, :x2]]))
    k = size(X, 2)

    # Instrument matrix Z = [1, x1, z1, z2] (x1 is its own instrument)
    Z = hcat(ones(n), Matrix(df[:, [:x1, :z1, :z2]]))

    # Stage 1: project endogenous x2 onto instruments Z
    x2 = Vector{Float64}(df.x2)
    Pi2 = Z \ x2
    x2_hat = Z * Pi2

    # First-stage F-statistic for x2
    ssr_restricted = sum(abs2, x2 .- mean(x2))
    ssr_full = sum(abs2, x2 - x2_hat)
    first_stage_f = ((ssr_restricted - ssr_full) / (size(Z, 2) - 1)) /
                    (ssr_full / max(1, n - size(Z, 2)))

    # Stage 2: replace x2 with x2_hat, run OLS
    X_hat = hcat(ones(n), Matrix(df[:, [:x1]]), x2_hat)
    β = X_hat \ y

    # Residuals use ORIGINAL X (not X_hat) — standard 2SLS
    resid = y - X * β
    rss = sum(abs2, resid)
    sigma2 = rss / (n - k)
    vcov_β = sigma2 * inv(X_hat' * X_hat)
    se = sqrt.(diag(vcov_β))
    tstat = β ./ se

    # Fit statistics
    tss = sum(abs2, y .- mean(y))
    r2 = 1 - rss / tss
    f_stat = ((tss - rss) / (k - 1)) / sigma2
    f_pvalue = ccdf(FDist(k - 1, n - k), f_stat)

    names = ["(Intercept)", "x1", "x2"]
    tidy = [
        Dict("name" => names[i], "estimate" => β[i], "stderror" => se[i], "statistic" => tstat[i])
        for i in 1:k
    ]
    metrics = [
        Dict("name" => "r2", "value" => r2),
        Dict("name" => "sigma", "value" => sqrt(sigma2)),
        Dict("name" => "f_stat", "value" => f_stat),
        Dict("name" => "f_pvalue", "value" => f_pvalue),
    ]
    return Dict(
        "glance" => Dict("model" => "iv", "nobs" => n, "dof" => n - k),
        "metrics" => metrics,
        "tidy" => tidy,
        "first_stage" => Dict("x2" => Dict("f_stat" => first_stage_f)),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    expected = iv_2sls_reference("$(CASE).csv")
    println(JSON3.write(expected; indent=2))
end
