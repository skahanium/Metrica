using Test
using DataFrames
using CSV
using MetricaSpatial
using MetricaBase

const ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const DEMO = joinpath(ROOT, "datasets", "demo", "spatial_demo.csv")
const WDEMO = joinpath(ROOT, "datasets", "demo", "spatial_demo_W.csv")

@testset "MetricaSpatial SAR 成功路径" begin
    df = CSV.read(DEMO, DataFrame)
    spec = Dict{String, Any}(
        "spatial_weights_path" => WDEMO,
        "spatial_id_column" => "region",
        "spatial_row_standardize" => true,
        "vcov" => "classical",
    )
    r = fit_spatial("spatial_lag", "y ~ x1", df, spec, ROOT)
    @test r isa SpatialFitResult
    g = glance(r)
    @test g.model == :spatial_lag
    @test g.nobs == 5
    @test haskey(r.diagnostics, :rho)
    @test haskey(r.diagnostics, :moran_i)
end

@testset "MetricaSpatial SEM 成功路径" begin
    df = CSV.read(DEMO, DataFrame)
    spec = Dict{String, Any}(
        "spatial_weights_path" => WDEMO,
        "spatial_id_column" => "region",
        "spatial_row_standardize" => true,
    )
    r = fit_spatial("spatial_error", "y ~ x1", df, spec, ROOT)
    @test r isa SpatialFitResult
    @test glance(r).model == :spatial_error
    @test r.loglik !== nothing
end

@testset "MetricaSpatial 孤立/缺失权重文件" begin
    df = CSV.read(DEMO, DataFrame)
    bad = fit_spatial(
        "spatial_lag",
        "y ~ x1",
        df,
        Dict{String, Any}(
            "spatial_weights_path" => joinpath(ROOT, "datasets", "demo", "nonexistent_W.csv"),
            "spatial_id_column" => "region",
        ),
        ROOT,
    )
    @test bad isa ModelError
end
