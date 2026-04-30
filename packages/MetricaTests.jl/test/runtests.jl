using Test
using MetricaLinear
using MetricaTests

const DEMO_CSV = joinpath(
    dirname(dirname(dirname(@__DIR__))),
    "apps",
    "metrica-desktop",
    "data",
    "demo.csv",
)

@testset "VIF 与 Breusch-Pagan 最小接口" begin
    fit = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    vif_table = vif(fit)
    bp = breusch_pagan(fit)

    @test vif_table isa Vector
    @test length(vif_table) == 2
    @test all(entry -> haskey(entry, :name) && haskey(entry, :vif), vif_table)
    @test bp isa NamedTuple
    @test haskey(bp, :statistic)
    @test haskey(bp, :pvalue)
    @test bp.dof == 2
    @test 0 <= bp.pvalue <= 1
end

@testset "诊断边界场景" begin
    no_intercept = fit_ols_file(DEMO_CSV, "y ~ 0 + x1")
    no_intercept_vif = vif(no_intercept)
    @test length(no_intercept_vif) == 1
    @test no_intercept_vif[1].name == "x1"
    @test no_intercept_vif[1].vif == 1.0

    intercept_only = fit_ols_file(DEMO_CSV, "y ~ 1")
    @test isempty(vif(intercept_only))

    bp = breusch_pagan(no_intercept)
    @test bp.dof == 1
    @test bp.statistic >= 0
    @test 0 <= bp.pvalue <= 1
end
