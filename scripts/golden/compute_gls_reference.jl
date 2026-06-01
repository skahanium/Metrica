#!/usr/bin/env julia
# 独立 GLS 参考（complete-case feasible GLS），当 Omega=I 时退化为 OLS。
# 与 R nlme::gls() 在相同设计上数值等价。
# 用法：julia scripts/golden/compute_gls_reference.jl

using DataFrames, CSV, LinearAlgebra, Statistics, Distributions, JSON3

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "linear_gls")

function gls_reference(path::AbstractString; omega_fn=nothing)
    df = dropmissing(CSV.read(path, DataFrame))
    y = Vector{Float64}(df.y)
    n = length(y)

    X = hcat(ones(n), Matrix(df[:, [:x1, :x2]]))
    k = size(X, 2)

    # Omega: if no function provided, use identity (GLS=OLS)
    if omega_fn === nothing
        omega_fn = r -> Matrix{Float64}(I, length(r), length(r))
    end
    Omega = omega_fn(y)
    chol_omega = cholesky(Symmetric(Omega))
    L = chol_omega.L
    L_inv = Matrix(L) \ I

    # Transform: X_gls = L^{-1} X, y_gls = L^{-1} y
    X_gls = L_inv * X
    y_gls = L_inv * y

    # OLS on transformed data
    β = X_gls \ y_gls

    # Residuals on original scale for fit statistics
    resid = y - X * β
    resid_gls = y_gls - X_gls * β
    rss_gls = sum(abs2, resid_gls)
    sigma2 = rss_gls / (n - k)
    vcov_β = sigma2 * inv(X_gls' * X_gls)
    se = sqrt.(diag(vcov_β))
    tstat = β ./ se

    # Fit statistics on original scale
    rss = sum(abs2, resid)
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
        Dict("name" => "wald_stat", "value" => f_stat),
        Dict("name" => "wald_pvalue", "value" => f_pvalue),
    ]
    return Dict(
        "glance" => Dict("model" => "gls", "nobs" => n, "dof" => n - k),
        "metrics" => metrics,
        "tidy" => tidy,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    expected = gls_reference("$(CASE).csv")
    println(JSON3.write(expected; indent=2))
end
