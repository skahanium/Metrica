using Test
using MetricaBase
using MetricaQuantile

@testset "分位数回归主路径" begin
    path = joinpath(@__DIR__, "..", "..", "..", "datasets", "demo", "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1 + x2", path; quantile_tau = 0.5)
    @test r isa QuantileFitResult
    @test r.tau == 0.5
    @test length(r.coefficients) == 3
    g = glance(r)
    @test g.nobs > 10
    @test haskey(g.metrics, :tau)
    @test haskey(g.metrics, :pseudo_r2)
    p = result_to_payload(r)
    @test p["status"] == "success"
    @test haskey(p["result_payload"]["diagnostics"], "tau")
    @test haskey(p["result_payload"]["diagnostics"], "inference_kind")
end

@testset "非法 τ" begin
    path = joinpath(@__DIR__, "..", "..", "..", "datasets", "demo", "quantile_demo.csv")
    r = fit(QuantileModel, "y ~ x1", path; quantile_tau = 1.0)
    @test r isa MetricaBase.ModelError
    @test r.code == :invalid_quantile_tau
end

@testset "设计矩阵奇异" begin
    tmp = joinpath(@__DIR__, "singular_q.csv")
    write(tmp, "y,x1,x2\n1,1,1\n2,2,2\n3,3,3\n4,4,4\n5,5,5\n")
    r = fit(QuantileModel, "y ~ x1 + x2", tmp; quantile_tau = 0.5)
    @test r isa MetricaBase.ModelError
    rm(tmp; force = true)
end
