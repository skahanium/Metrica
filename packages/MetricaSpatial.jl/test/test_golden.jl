using Test
using CSV
using DataFrames
using MetricaBase
using MetricaSpatial

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

@testset "Golden spatial_lag" begin
    spec = load_golden_spec("spatial_lag")
    repo_root = normpath(joinpath(@__DIR__, "..", "..", ".."))
    data_path = golden_dataset_path(spec)
    df = CSV.read(data_path, DataFrame)
    w_path = joinpath(dirname(data_path), "spatial_lag_W.csv")
    params = Dict{String, Any}(
        "spatial_weights_path" => w_path,
        "spatial_id_column" => String(spec.spatial_id_column),
        "spatial_row_standardize" => Bool(spec.spatial_row_standardize),
        "vcov" => "classical",
    )
    result = fit_spatial("spatial_lag", String(spec.formula), df, params, repo_root)
    g = glance(result)
    @test String(g.model) == String(spec.expected.glance.model)
    @test g.nobs == Int(spec.expected.glance.nobs)
    tol = golden_tolerance_dict(spec)
    for expected_row in spec.expected.tidy
        row = only(r for r in tidy(result).rows if String(r.name) == String(expected_row.name))
        @test assert_golden_close(row.estimate, expected_row.estimate, tol["coefficient"])
        @test assert_golden_close(row.stderror, expected_row.stderror, tol["stderror"])
        @test assert_golden_close(row.statistic, expected_row.statistic, tol["statistic"])
    end
    for expected_metric in spec.expected.metrics
        key = String(expected_metric.name)
        if key == "rho"
            @test assert_golden_close(result.diagnostics[:rho], expected_metric.value, tol["metric"])
        elseif key == "moran_i"
            @test assert_golden_close(result.diagnostics[:moran_i], expected_metric.value, tol["metric"])
        end
    end
end
