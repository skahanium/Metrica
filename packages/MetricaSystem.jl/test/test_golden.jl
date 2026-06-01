using Test
using MetricaBase
using MetricaSystem

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

@testset "Golden SUR" begin
    spec = load_golden_spec("system_sur")
    data_path = golden_dataset_path(spec)
    eqs = [String(e) for e in spec.equations]
    r = fit(SURModel, "", data_path; equations = eqs)
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
        key = Symbol(expected_metric.name)
        @test haskey(g.metrics, key)
        @test assert_golden_close(g.metrics[key], expected_metric.value, tol["metric"])
    end
end
