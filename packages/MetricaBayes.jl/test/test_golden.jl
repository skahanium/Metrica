using Test
using CSV
using DataFrames
using MetricaBase
using MetricaBayes

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

@testset "Golden bayes_linear conjugate" begin
    spec = load_golden_spec("bayes_linear_conjugate")
    df = CSV.read(golden_dataset_path(spec), DataFrame)
    result = fit_bayes_linear(
        df,
        String(spec.formula);
        bayes_sigma2_known = true,
        bayes_sigma2_value = 0.25,
        bayes_prior_scale = 10.0,
    )
    g = glance(result)
    @test String(g.model) == String(spec.expected.glance.model)
    @test g.nobs == Int(spec.expected.glance.nobs)
    tol = golden_tolerance_dict(spec)
    for expected_row in spec.expected.tidy
        row = only(r for r in tidy(result).rows if String(r.name) == String(expected_row.name))
        @test assert_golden_close(row.estimate, expected_row.estimate, tol["coefficient"])
    end
    for expected_metric in spec.expected.metrics
        key = Symbol(expected_metric.name)
        @test haskey(g.metrics, key)
        @test assert_golden_close(Float64(g.metrics[key]), expected_metric.value, tol["metric"])
    end
end
