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
