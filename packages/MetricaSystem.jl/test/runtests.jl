using Test
using MetricaBase
using MetricaSystem

@testset "SUR 主路径" begin
    path = joinpath(@__DIR__, "..", "..", "..", "datasets", "demo", "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ x1 + x2", "y2 ~ x1 + x2"])
    @test r isa SystemEquationsFitResult
    @test length(r.equation_glances) == 2
    @test length(r.tidy_table.rows) > 2
    @test length(r.tidy_equation_labels) == length(r.tidy_table.rows)
    Σ = r.diagnostics[:sigma_residual]
    @test size(Σ, 1) == size(Σ, 2) == 2
    @test sqrt(sum(abs2, Σ .- Σ')) < 1e-8
    p = result_to_payload(r)
    @test p["status"] == "success"
    @test haskey(p["result_payload"], "equation_glances")
    @test haskey(p["result_payload"]["diagnostics"], "sigma_residual")
end

@testset "system_2sls 小样本" begin
    path = joinpath(@__DIR__, "..", "..", "..", "datasets", "demo", "system_2sls_demo.csv")
    r = fit(
        System2SLSModel, "", path;
        equations = ["y1 ~ x1 + x2"],
        system_endogenous = [["x1"]],
        system_instruments = [["z1"]],
    )
    @test r isa SystemEquationsFitResult
    @test r.system_method == "2sls"
end

@testset "方程数过多" begin
    path = joinpath(@__DIR__, "..", "..", "..", "datasets", "demo", "sur_system_demo.csv")
    eqs = ["y1 ~ x1" for _ in 1:9]
    r = fit(SURModel, "", path; equations = eqs)
    @test r isa MetricaBase.ModelError
    @test r.code == :too_many_equations
end
