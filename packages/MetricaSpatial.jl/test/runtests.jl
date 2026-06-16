using Test
using DataFrames
using CSV
using MetricaSpatial
using MetricaBase

include("test_golden.jl")

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
    @test r.diagnostics[:moran_var] !== nothing
    @test r.diagnostics[:moran_z] !== nothing
    @test r.diagnostics[:moran_pvalue] !== nothing
    @test r.diagnostics[:direct_effects] !== nothing
    @test r.diagnostics[:indirect_effects] !== nothing
    @test r.diagnostics[:total_effects] !== nothing
    caps = MetricaBase.model_capabilities(r)
    @test caps.model_family == :spatial
    @test :spatial_lag in caps.supported_models
    @test :moran_z in caps.diagnostics_available
    @test :direct_effects in caps.effects_available
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

@testset "MetricaSpatial SLX 成功路径与效应分解" begin
    df = CSV.read(DEMO, DataFrame)
    spec = Dict{String, Any}(
        "spatial_weights_path" => WDEMO,
        "spatial_id_column" => "region",
        "spatial_row_standardize" => true,
    )
    r = fit_spatial("spatial_slx", "y ~ x1", df, spec, ROOT)
    @test r isa SpatialFitResult
    @test glance(r).model == :spatial_slx
    names = [p.first for p in coef(r)]
    @test :x1 in names
    @test :W_x1 in names
    @test r.diagnostics[:direct_effects] !== nothing
    @test r.diagnostics[:indirect_effects] !== nothing
    @test r.diagnostics[:total_effects] !== nothing
    @test r.diagnostics[:direct_effects][:x1] + r.diagnostics[:indirect_effects][:x1] ≈ r.diagnostics[:total_effects][:x1]
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

@testset "MetricaSpatial 结果载荷包含能力协议" begin
    df = CSV.read(DEMO, DataFrame)
    spec = Dict{String, Any}(
        "spatial_weights_path" => WDEMO,
        "spatial_id_column" => "region",
        "spatial_row_standardize" => true,
    )
    r = fit_spatial("spatial_slx", "y ~ x1", df, spec, ROOT)
    payload = result_to_payload(r)
    caps = payload["result_payload"]["model_capabilities"]
    @test caps["status"] == "implemented"
    @test caps["model_family"] == "spatial"
    @test "spatial_slx" in caps["supported_models"]
    @test "moran_z" in caps["diagnostics_available"]
    @test "direct_effects" in caps["effects_available"]
end

@testset "MetricaSpatial SDM 成功路径" begin
    df = CSV.read(DEMO, DataFrame)
    result = fit_spatial("spatial_sdm", "y ~ x1", df, Dict(
        "spatial_weights_path" => joinpath(ROOT, "datasets", "demo", "spatial_demo_W.csv"),
        "spatial_id_column" => "region",
        "spatial_row_standardize" => true,
    ), joinpath(ROOT, "datasets"))
    @test result isa SpatialFitResult
    @test result.model_kind == :spatial_sdm
    @test haskey(result.diagnostics, :rho)
    @test haskey(result.diagnostics, :lm_lag)
end

@testset "MetricaSpatial SAC 成功路径" begin
    df = CSV.read(DEMO, DataFrame)
    result = fit_spatial("spatial_sac", "y ~ x1", df, Dict(
        "spatial_weights_path" => joinpath(ROOT, "datasets", "demo", "spatial_demo_W.csv"),
        "spatial_id_column" => "region",
    ), joinpath(ROOT, "datasets"))
    @test result isa SpatialFitResult
    @test result.model_kind == :spatial_sac
    @test haskey(result.diagnostics, :lambda)
    @test haskey(result.diagnostics, :direct_effects)
    @test result.diagnostics[:direct_effects] !== nothing
end

@testset "MetricaSpatial GWR 小样本成功" begin
    coords = [0.0 0.0; 1.0 0.0; 0.0 1.0; 1.0 1.0; 0.5 0.5]
    y = [1.0, 2.0, 1.5, 2.5, 2.0]
    X = [ones(5) [0.5, 1.5, 0.5, 1.5, 1.0]]
    result = fit_gwr(y, X, coords; bandwidth=2.0, kernel="gaussian")
    @test result isa GWRFitResult
    @test size(result.local_coefficients) == (5, 2)
    @test length(result.fitted) == 5
    @test result.kernel == "gaussian"
end

@testset "MetricaSpatial 权重构造 (kNN / distance-band)" begin
    coords = [0.0 0.0; 1.0 0.0; 0.0 1.0; 1.0 1.0; 0.5 0.5]
    edges_knn, meta_knn = build_knn_weights(coords, 2; distance_metric=:euclidean)
    @test nrow(edges_knn) == 10  # 5 * 2
    @test meta_knn[:method] == "knn"

    edges_db, meta_db = build_distance_band_weights(coords, 2.0; distance_metric=:euclidean)
    @test nrow(edges_db) >= 2  # at minimum the closest pair
    @test meta_db[:method] == "distance_band"
end

@testset "MetricaSpatial GWR golden-value (固定数据)" begin
    coords = [0.0 0.0; 1.0 0.0; 0.0 1.0; 1.0 1.0; 0.5 0.5]
    y = [1.0, 2.0, 1.5, 2.5, 2.0]
    X = [1.0 0.5; 1.0 1.5; 1.0 0.5; 1.0 1.5; 1.0 1.0]
    result = fit_gwr(y, X, coords; bandwidth=2.0, kernel="gaussian")

    @test result isa GWRFitResult
    @test size(result.local_coefficients) == (5, 2)
    @test size(result.local_stderrors) == (5, 2)
    @test size(result.local_tvalues) == (5, 2)
    @test result.bandwidth ≈ 2.0
    @test result.kernel == "gaussian"
    @test !result.adaptive

    # 关键数值（手工 WLS）：点 5 (中心) 应有接近 OLS 的系数
    beta_ols = X \ y  # ≈ [0.9, 1.1]
    beta_center = result.local_coefficients[5, :]
    @test beta_center[1] ≈ beta_ols[1] atol=0.5  # 截距
    @test beta_center[2] ≈ beta_ols[2] atol=0.5  # 斜率

    # 所有 SE 应为有限正数
    se_center = result.local_stderrors[5, :]
    @test all(isfinite, se_center)
    @test all(>=(0), se_center)

    # 局部 R² 在 [0, 1]
    @test all(r -> 0 <= r <= 1, result.local_r2)

    # 有效参数和 AICc 为有限
    @test result.effective_parameters > 0
    @test isfinite(result.aicc)
end
