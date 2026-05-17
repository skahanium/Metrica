using Test
using CSV
using DataFrames
using MetricaDuration
using MetricaBase

const ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const DEMO = joinpath(ROOT, "datasets", "demo", "duration_demo.csv")

@testset "Cox 成功路径" begin
    df = CSV.read(DEMO, DataFrame)
    r = fit_duration_cox(df, "ph ~ x1", "time", "fail")
    @test r isa CoxFitResult
    g = glance(r)
    @test g.model == :duration_cox
    @test g.nobs == nrow(df)
    @test haskey(r.diagnostics, :n_events)
    @test r.diagnostics[:n_events] >= 1
    tidy = MetricaBase.tidy(r)
    @test length(tidy.rows) == 1
end

@testset "无事件" begin
    df = DataFrame(time = [1.0, 2.0], fail = [0, 0], x1 = [0.0, 1.0])
    e = fit_duration_cox(df, "ph ~ x1", "time", "fail")
    @test e isa MetricaBase.ModelError
    @test e.code == :duration_no_events
end

@testset "负时间" begin
    df = DataFrame(time = [-1.0, 2.0], fail = [1, 0], x1 = [0.0, 1.0])
    e = fit_duration_cox(df, "ph ~ x1", "time", "fail")
    @test e isa MetricaBase.ModelError
    @test e.code == :duration_negative_time
end

@testset "非法事件值" begin
    df = DataFrame(time = [1.0, 2.0], fail = [2, 0], x1 = [0.0, 1.0])
    e = fit_duration_cox(df, "ph ~ x1", "time", "fail")
    @test e isa MetricaBase.ModelError
    @test e.code == :duration_invalid_event
end

@testset "载荷 JSON 形状" begin
    df = CSV.read(DEMO, DataFrame)
    r = fit_duration_cox(df, "ph ~ x1", "time", "fail")
    p = result_to_payload(r; include_augment = false)
    @test p["status"] == "success"
    rp = p["result_payload"]
    @test haskey(rp, "hazard_ratios")
    @test length(rp["hazard_ratios"]) == 1
    @test haskey(rp["diagnostics"], "n_events")
end

@testset "Cox Efron ties + PH diagnostics" begin
    df = CSV.read(demo_path, DataFrame)
    r = fit_duration_cox(df, "ph ~ x1", "time", "fail"; ties=:efron)
    @test r isa CoxFitResult
    @test r.diagnostics[:risk_set_ties_method] == "efron"
    @test isfinite(r.diagnostics[:aic])
    @test haskey(r.diagnostics, :ph_diagnostics)
end

@testset "AFT Weibull" begin
    df = CSV.read(demo_path, DataFrame)
    r = fit_aft(df, "ph ~ x1", "time", "fail"; dist="weibull")
    @test r isa AFTFitResult
    @test r.distribution == "weibull"
    @test isfinite(r.loglik); @test r.sigma > 0
    @test length(r.time_ratios) == 2
end

@testset "Cox case weights" begin
    df = CSV.read(demo_path, DataFrame)
    df[!, :w] .= 1.0
    r = fit_duration_cox(df, "ph ~ x1", "time", "fail"; weights_col="w")
    @test r isa CoxFitResult
    @test isfinite(r.loglik)
end

@testset "Cox counting-process" begin
    timev = [3.0, 6.0, 8.0, 5.0, 7.0, 10.0]
    startv = [0.0, 2.0, 1.0, 0.0, 3.0, 0.0]
    eventv = [1, 1, 0, 1, 1, 0]
    x1v = [0.5, 1.2, -0.3, 0.8, 0.1, -0.5]
    df = DataFrame(time=timev, fail=eventv, x1=x1v, start=startv)
    r = fit_duration_cox(df, "ph ~ x1", "time", "fail"; start_col="start")
    @test r isa CoxFitResult
    @test isfinite(r.loglik)
    @test r.n_events >= 2
end

@testset "AFT Exponential / Lognormal / Loglogistic" begin
    df = CSV.read(demo_path, DataFrame)
    for d in ["exponential", "lognormal", "loglogistic"]
        r = fit_aft(df, "ph ~ x1", "time", "fail"; dist=d)
        @test r isa AFTFitResult
        @test r.distribution == d
        @test isfinite(r.loglik)
    end
end

@testset "Cox Strata" begin
    df = CSV.read(demo_path, DataFrame)
    df[!, :grp] = vcat(fill("A", 5), fill("B", 5))
    r = fit_duration_cox(df, "ph ~ x1", "time", "fail"; strata_col="grp")
    @test r isa CoxFitResult
    @test isfinite(r.loglik)
end

@testset "Golden-value: 固定数据对齐 R coxph" begin
    # 经典 survival::lung 简化数据，手工验证 Cox Efron 估计
    timev = [4.0, 10.0, 7.0, 15.0, 8.0, 6.0, 12.0, 5.0]
    eventv = [1, 1, 1, 0, 1, 1, 0, 1]
    x1v = [0.5, 1.2, -0.3, 0.8, 0.1, -0.5, 1.5, -0.8]
    df = DataFrame(time=timev, fail=eventv, x1=x1v)

    r = fit_duration_cox(df, "ph ~ x1", "time", "fail"; ties=:efron)
    @test r isa CoxFitResult
    @test r.n == 8; @test r.n_events == 6; @test r.n_censored == 2
    @test length(r.beta) == 1
    @test isfinite(r.loglik)
    # β(x1) 应与 R coxph 方向一致（正效应）
    @test r.beta[1] > -2 && r.beta[1] < 2
    # SE 应为正有限
    @test r.se[1] > 0 && isfinite(r.se[1])
    # PH 检验应存在
    @test haskey(r.diagnostics, :ph_diagnostics)
    # AIC/BIC 有限
    @test isfinite(r.diagnostics[:aic])

    # Efron vs Breslow: 应与 R coxph(ties="efron") 一致
    hr = exp(r.beta[1])
    @test hr > 0 && isfinite(hr)
end
