#!/usr/bin/env julia
# 独立 GLS 参考（complete-case feasible GLS），当 Omega=I 时退化为 OLS。
include(joinpath(@__DIR__, "_write_golden_json.jl"))
using DataFrames, CSV, LinearAlgebra, Statistics, Distributions, Dates

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "linear_gls")

function gls_reference(path::AbstractString; omega_fn=nothing)
    df = dropmissing(CSV.read(path, DataFrame))
    y = Vector{Float64}(df.y)
    n = length(y)

    X = hcat(ones(n), Matrix(df[:, [:x1, :x2]]))
    k = size(X, 2)

    if omega_fn === nothing
        omega_fn = function (residuals)
            m = length(residuals)
            Ω = zeros(Float64, m, m)
            @inbounds for i in 1:m
                Ω[i, i] = 1.0
            end
            return Ω
        end
    end
    Omega = omega_fn(y)
    chol_omega = cholesky(Symmetric(Omega))
    L = chol_omega.L
    L_inv = Matrix(L) \ I

    X_gls = L_inv * X
    y_gls = L_inv * y

    β = X_gls \ y_gls

    resid = y - X * β
    resid_gls = y_gls - X_gls * β
    rss_gls = sum(abs2, resid_gls)
    sigma2 = rss_gls / (n - k)
    vcov_β = sigma2 * inv(X_gls' * X_gls)
    se = sqrt.(diag(vcov_β))
    tstat = β ./ se

    rss = sum(abs2, resid)
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
        metric_dict("wald_stat", f_stat),
        metric_dict("wald_pvalue", f_pvalue),
    ]
    return Dict(
        "glance" => Dict("model" => "gls", "nobs" => n, "dof" => n - k),
        "metrics" => metrics,
        "tidy" => tidy,
    )
end

function build_linear_gls_spec()
    expected = gls_reference("$(CASE).csv")
    return Dict(
        "id" => "linear_gls",
        "dataset" => "golden/linear_gls.csv",
        "model_type" => "gls",
        "formula" => "y ~ x1 + x2",
        "omega_fn" => "identity",
        "reference" => Dict(
            "source" => "Independent complete-case GLS reference; with identity Omega, numerically equivalent to OLS and R stats::lm() on the same design.",
            "generated_on" => string(Dates.today()),
            "regenerate" => "julia --project=scripts/golden scripts/golden/compute_gls_reference.jl",
            "notes" => "With identity Omega, GLS(Omega=I) estimates match the deterministic OLS-equivalent path on this fixture.",
        ),
        "tolerances" => default_tolerances(),
        "expected" => expected,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    write_golden_json(resolve_golden_json_path(CASE), build_linear_gls_spec())
end
