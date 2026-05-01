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

@testset "White 检验" begin
    fit = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    wt = white_test(fit)
    @test wt isa NamedTuple
    @test haskey(wt, :statistic)
    @test haskey(wt, :pvalue)
    @test haskey(wt, :dof)
    @test wt.statistic >= 0
    @test 0 <= wt.pvalue <= 1
    @test wt.dof >= 1
end

@testset "Durbin-Watson 检验" begin
    fit = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    dw = durbin_watson(fit)
    @test dw isa NamedTuple
    @test haskey(dw, :statistic)
    @test haskey(dw, :pvalue)
    @test 0 <= dw.statistic <= 4  # DW 应在 [0, 4] 范围内
end

@testset "Breusch-Godfrey 检验" begin
    fit = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    bg = breusch_godfrey(fit; p=2)
    @test bg isa NamedTuple
    @test haskey(bg, :statistic)
    @test haskey(bg, :pvalue)
    @test haskey(bg, :dof)
    @test bg.dof == 2
    @test bg.statistic >= 0
    @test 0 <= bg.pvalue <= 1

    # 默认 p=2
    bg_default = breusch_godfrey(fit)
    @test bg_default.dof == 2
end

@testset "RESET 检验" begin
    fit = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    reset = reset_test(fit)
    @test reset isa NamedTuple
    @test haskey(reset, :statistic)
    @test haskey(reset, :pvalue)
    @test haskey(reset, :df_num)
    @test haskey(reset, :df_den)
    @test reset.df_num == 2  # ŷ² + ŷ³
    @test reset.df_den >= 1

    # 自定义幂次
    reset_custom = reset_test(fit; power=2:2)
    @test reset_custom.df_num == 1
end

@testset "Jarque-Bera 检验" begin
    fit = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    jb = jarque_bera(fit)
    @test jb isa NamedTuple
    @test haskey(jb, :statistic)
    @test haskey(jb, :pvalue)
    @test haskey(jb, :skewness)
    @test haskey(jb, :kurtosis)
    @test jb.statistic >= 0
    @test 0 <= jb.pvalue <= 1
end

@testset "全诊断覆盖" begin
    fit = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")

    for fn in [vif, breusch_pagan, white_test, durbin_watson, breusch_godfrey, reset_test, jarque_bera]
        result = fn(fit)
        @test result isa Union{Vector, NamedTuple}
    end
end
