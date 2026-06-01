using Test
using MetricaBase
using MetricaDiscrete

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

function _run_discrete_golden(id::AbstractString, model_type)
    spec = load_golden_spec(id)
    data_path = golden_dataset_path(spec)
    result = MetricaBase.fit(model_type, String(spec.formula), data_path)
    @test String(glance(result).model) == String(spec.expected.glance.model)
    @test glance(result).nobs == Int(spec.expected.glance.nobs)
    tol = golden_tolerance_dict(spec)
    for expected_row in spec.expected.tidy
        row = only([r for r in tidy(result).rows if String(r.name) == String(expected_row.name)])
        @test assert_golden_close(row.estimate, expected_row.estimate, tol["coefficient"])
        @test assert_golden_close(row.stderror, expected_row.stderror, tol["stderror"])
        @test assert_golden_close(row.statistic, expected_row.statistic, tol["statistic"])
    end
    for expected_metric in spec.expected.metrics
        key = Symbol(expected_metric.name)
        @test haskey(glance(result).metrics, key)
        @test assert_golden_close(glance(result).metrics[key], expected_metric.value, tol["metric"])
    end
    return result
end

@testset "Golden logit" begin
    _run_discrete_golden("discrete_logit", LogitModel)
end

@testset "Golden probit" begin
    _run_discrete_golden("discrete_probit", ProbitModel)
end

@testset "Golden poisson" begin
    _run_discrete_golden("discrete_poisson", PoissonModel)
end
