#!/usr/bin/env julia
# 独立 OLS 参考（complete-case X\\y），与 R stats::lm 在相同设计上数值等价。
# 用法：julia --project=packages/MetricaLinear.jl scripts/golden/compute_ols_reference.jl

using DataFrames, CSV, LinearAlgebra, Statistics, JSON3

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CASE = joinpath(ROOT, "datasets", "golden", "linear_ols")

function ols_reference(path::AbstractString)
    df = dropmissing(CSV.read(path, DataFrame))
    y = Vector{Float64}(df.y)
    X = hcat(ones(length(y)), Matrix(df[:, [:x1, :x2]]))
    β = X \ y
    n, k = size(X)
    resid = y - X * β
    rss = sum(abs2, resid)
    tss = sum(abs2, y .- mean(y))
    r2 = 1 - rss / tss
    adj = 1 - (1 - r2) * (n - 1) / (n - k)
    σ = sqrt(rss / (n - k))
    se = σ .* sqrt.(diag(inv(X' * X)))
    tstat = β ./ se
    names = ["(Intercept)", "x1", "x2"]
    tidy = [
        Dict("name" => names[i], "estimate" => β[i], "stderror" => se[i], "statistic" => tstat[i])
        for i in 1:k
    ]
    metrics = [
        Dict("name" => "r2", "value" => r2),
        Dict("name" => "adj_r2", "value" => adj),
        Dict("name" => "rss", "value" => rss),
        Dict("name" => "tss", "value" => tss),
        Dict("name" => "sigma", "value" => σ),
    ]
    return Dict(
        "glance" => Dict("model" => "ols", "nobs" => n, "dof" => n - k),
        "metrics" => metrics,
        "tidy" => tidy,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    expected = ols_reference("$(CASE).csv")
    println(JSON3.write(expected; indent=2))
end
