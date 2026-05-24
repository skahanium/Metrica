using Test
using LinearAlgebra: issymmetric
using MetricaBase
using MetricaQuantile
using Random
using Statistics

const DEMO = joinpath(@__DIR__, "..", "..", "..", "datasets", "demo")

@testset "分位数回归主路径" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau=0.5)
    @test r isa QuantileFitResult
    @test r.tau == 0.5
    @test length(r.coefficients) == 3
    g = glance(r)
    @test g.nobs > 10
    @test haskey(g.metrics, :tau)
    @test haskey(g.metrics, :pseudo_r2)
    pr2 = g.metrics[:pseudo_r2]
    @test pr2 === nothing || (pr2 >= 0 && pr2 <= 1)
    p = result_to_payload(r)
    @test p["status"] == "success"
    @test haskey(p["result_payload"]["diagnostics"], "tau")
    @test haskey(p["result_payload"]["diagnostics"], "inference_kind")
end

@testset "多 τ 估计" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    taus = [0.25, 0.5, 0.75]
    slopes = Float64[]
    for τ in taus
        r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau=τ)
        @test r isa QuantileFitResult
        push!(slopes, r.coefficients[end])
    end
    @test all(isfinite, slopes)
    @test length(unique(slopes)) > 1
end

@testset "系数回收（合成 DGP）" begin
    Random.seed!(99)
    tmp = joinpath(@__DIR__, "dgp_q.csv")
    n = 80
    x = randn(n)
    y = 1.0 .+ 2.0 .* x .+ randn(n) .* 0.5
    open(tmp, "w") do io
        println(io, "y,x")
        for i in 1:n
            println(io, "$(y[i]),$(x[i])")
        end
    end
    r = fit(QuantileModel, "y ~ x", tmp; quantile_tau=0.5)
    rm(tmp; force=true)
    @test r isa QuantileFitResult
    slope = r.coefficients[end]
    @test slope ≈ 2.0 atol=0.8
end

@testset "augment 列与长度" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau=0.5)
    at = augment(r)
    @test at.nobs == length(r.fitted_values)
    @test haskey(at.columns, :fitted)
    @test haskey(at.columns, :residual)
    @test length(at.columns[:fitted]) == at.nobs
    @test length(at.columns[:residual]) == at.nobs
end

@testset "极端 τ 在 demo 数据上可能拟合失败" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau=0.04)
    @test r isa QuantileFitResult || r isa MetricaBase.ModelError
end

@testset "非法 τ" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1", path; quantile_tau=1.0)
    @test r isa MetricaBase.ModelError
    @test r.code == :invalid_quantile_tau
end

@testset "设计矩阵奇异" begin
    tmp = joinpath(@__DIR__, "singular_q.csv")
    write(tmp, "y,x1,x2\n1,1,1\n2,2,2\n3,3,3\n4,4,4\n5,5,5\n")
    r = fit(QuantileModel, "y ~ x1 + x2", tmp; quantile_tau=0.5)
    @test r isa MetricaBase.ModelError
    rm(tmp; force=true)
end

@testset "result_to_payload augment 预览" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1", path; quantile_tau=0.5)
    p = result_to_payload(r; include_augment=true)
    @test haskey(p["result_payload"], "augment_status")
    @test p["result_payload"]["augment_status"]["available"] === true
    @test haskey(p["result_payload"], "augment_preview")
    p2 = result_to_payload(r; include_augment=false)
    @test !haskey(p2["result_payload"], "augment_preview")
end

@testset "tidy 与 glance 一致性" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau=0.5)
    t = tidy(r)
    g = glance(r)
    @test length(t.rows) == length(r.coefficients)
    @test g.metrics[:tau] == r.tau
end

@testset "公式解析失败" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~", path; quantile_tau=0.5)
    @test r isa MetricaBase.ModelError
end

@testset "Quantile model_capabilities" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1", path; quantile_tau=0.5)
    caps = model_capabilities(r)
    @test caps.model_family == :quantile
    @test :pseudo_r2 in caps.diagnostics_available
    @test caps.prediction_available === false
end

@testset "Quantile vcov 与标准误" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau=0.5)
    @test size(r.vcov_matrix) == (length(r.coefficients), length(r.coefficients))
    @test isapprox(r.vcov_matrix, r.vcov_matrix'; atol=1e-8)
    @test length(r.stderror_values) == length(r.coefficients)
    @test all(se -> se === nothing || (se > 0 && isfinite(se)), r.stderror_values)
end

@testset "Quantile fitted 与 residual" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau=0.5)
    @test length(r.fitted_values) == length(r.y)
    @test r.residuals ≈ r.y .- r.fitted_values
    t = tidy(r)
    @test all(row.name isa Symbol for row in t.rows)
end

@testset "Quantile diagnostics 数值诊断" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau=0.5)
    @test haskey(r.diagnostics, :rank_X)
    @test haskey(r.diagnostics, :cond_X)
    @test r.diagnostics[:rank_X] >= 2
    @test r.diagnostics[:cond_X] > 0
    @test r.diagnostics[:inference_kind] isa String
end

@testset "Quantile τ 网格与伪 R²" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    pr2_vals = Float64[]
    for τ in (0.25, 0.5, 0.75)
        r = fit(QuantileModel, "y ~ x1", path; quantile_tau=τ)
        @test r isa QuantileFitResult
        pr2 = glance(r).metrics[:pseudo_r2]
        pr2 !== nothing && push!(pr2_vals, Float64(pr2))
    end
    @test !isempty(pr2_vals)
    @test all(0 .<= pr2_vals .<= 1)
end

@testset "Quantile 缺失自变量" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ not_here", path; quantile_tau=0.5)
    @test r isa MetricaBase.ModelError
end

@testset "Quantile 系数名含截距" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1", path; quantile_tau=0.5)
    @test :intercept in r.coefficient_names || Symbol("(Intercept)") in r.coefficient_names ||
          any(n -> occursin("Intercept", String(n)), r.coefficient_names)
end

@testset "Quantile payload capabilities" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau=0.5)
    p = result_to_payload(r; include_augment=false)
    @test haskey(p["result_payload"], "model_capabilities")
    @test p["result_payload"]["model_capabilities"]["model_family"] == "quantile"
end

@testset "Quantile 样本过少" begin
    tmp = joinpath(@__DIR__, "tiny_q.csv")
    write(tmp, "y,x\n1,1\n2,2\n")
    r = fit(QuantileModel, "y ~ x", tmp; quantile_tau=0.5)
    rm(tmp; force=true)
    @test r isa QuantileFitResult || r isa MetricaBase.ModelError
end

@testset "Quantile tidy 行与系数对齐" begin
    path = joinpath(DEMO, "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1", path; quantile_tau=0.5)
    rows = tidy(r).rows
    @test length(rows) == length(r.coefficients)
    @test all(row.estimate isa Float64 for row in rows)
end
