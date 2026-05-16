using Test
using MetricaBase
using MetricaNonlinear

const DEMO = joinpath(@__DIR__, "..", "..", "..", "datasets", "demo", "nls_threshold_demo.csv")

@testset "NLS 主路径与载荷" begin
    r = fit(NLSModel, "y ~ x", DEMO; nls_family = "exp_growth", nls_start = [0.5, 0.5, 0.05])
    @test r isa NLSFitResult
    @test r.nls_family == "exp_growth"
    @test length(r.coefficients) == 3
    g = glance(r)
    @test g.nobs > 10
    @test haskey(g.metrics, :rss)
    p = result_to_payload(r)
    @test p["status"] == "success"
    @test haskey(p["result_payload"]["diagnostics"], "objective_final")
    @test haskey(p["result_payload"]["diagnostics"], "start_used")
end

@testset "NLS 缺少初值" begin
    r = fit(NLSModel, "y ~ x", DEMO; nls_family = "exp_growth")
    @test r isa MetricaBase.ModelError
    @test r.code == :missing_nls_start
end

@testset "NLS 初值长度错误" begin
    r = fit(NLSModel, "y ~ x", DEMO; nls_family = "exp_growth", nls_start = [1.0, 2.0])
    @test r isa MetricaBase.ModelError
    @test r.code == :invalid_nls_start
end

@testset "NLS 强限制迭代（未收敛路径）" begin
    r = fit(
        NLSModel, "y ~ x", DEMO;
        nls_family = "exp_growth",
        nls_start = [1.0, 1.0, 0.1],
        nls_max_iter = 1,
    )
    @test r isa NLSFitResult
    @test r.converged == false
    @test any(w -> w.code == :nls_not_converged, r.glance_table.warnings)
end

@testset "门限主路径" begin
    gvec = collect(range(-1.0; stop = 1.0, length = 21))
    r = fit(
        ThresholdModel, "y ~ x + q", DEMO;
        threshold_variable = "q",
        threshold_grid = gvec,
        threshold_trim_frac = 0.1,
    )
    @test r isa ThresholdFitResult
    @test r.n_below >= 10
    @test r.n_above >= 10
    p = result_to_payload(r)
    @test p["status"] == "success"
    @test haskey(p["result_payload"]["diagnostics"], "gamma_hat")
    @test haskey(p["result_payload"]["diagnostics"], "search_grid_meta")
end

@testset "门限网格过长" begin
    gvec = collect(range(-1.0; stop = 1.0, length = 501))
    r = fit(
        ThresholdModel, "y ~ x + q", DEMO;
        threshold_variable = "q",
        threshold_grid = gvec,
    )
    @test r isa MetricaBase.ModelError
    @test r.code == :invalid_threshold_grid
end

@testset "门限搜索失败（区制样本不足）" begin
    tmp = joinpath(@__DIR__, "thr_tiny.csv")
    open(tmp, "w") do io
        println(io, "y,x,q")
        for i in 1:25
            println(io, "$(i),$(i),$(i)")
        end
    end
    # 候选 γ 在数据范围内，但分割后总有一侧少于 10 个观测
    r = fit(
        ThresholdModel, "y ~ x + q", tmp;
        threshold_variable = "q",
        threshold_grid = [5.0, 8.0],
        threshold_trim_frac = 0.0,
    )
    @test r isa MetricaBase.ModelError
    @test r.code == :threshold_fit_failed
    rm(tmp; force = true)
end

@testset "门限网格非单调" begin
    r = fit(
        ThresholdModel, "y ~ x + q", DEMO;
        threshold_variable = "q",
        threshold_grid = [0.1, 0.2, 0.15],
    )
    @test r isa MetricaBase.ModelError
    @test r.code == :invalid_threshold_grid
end
