using Test
using MetricaBase
using MetricaGMM

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

@testset "Golden gmm_linear" begin
    spec = load_golden_spec("gmm_linear")
    data_path = golden_dataset_path(spec)
    r = MetricaBase.fit(
        GMMLinearModel,
        String(spec.formula),
        data_path;
        instruments = String.(spec.instruments),
        endog = String.(spec.endog_columns),
        gmm_weight = "two_step",
    )
    g = glance(r)
    @test String(g.model) == String(spec.expected.glance.model)
    @test g.nobs == Int(spec.expected.glance.nobs)
    tol = golden_tolerance_dict(spec)
    trows = tidy(r).rows
    @test length(trows) == length(spec.expected.tidy)
    for (i, expected_row) in enumerate(spec.expected.tidy)
        row = trows[i]
        @test String(row.name) == String(expected_row.name)
        @test assert_golden_close(row.estimate, expected_row.estimate, tol["coefficient"])
        @test assert_golden_close(row.stderror, expected_row.stderror, tol["stderror"])
        @test assert_golden_close(row.statistic, expected_row.statistic, tol["statistic"])
    end
    for expected_metric in spec.expected.metrics
        key = String(expected_metric.name)
        if key == "j_statistic"
            @test assert_golden_close(r.gmm_diagnostics[:j_statistic], expected_metric.value, tol["metric"])
        elseif key == "j_df"
            @test r.gmm_diagnostics[:j_df] == Int(expected_metric.value)
        end
    end
end
