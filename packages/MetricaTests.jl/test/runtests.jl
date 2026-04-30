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
end
