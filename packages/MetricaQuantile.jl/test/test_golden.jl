using Test
using MetricaBase
using MetricaQuantile

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

function _coef_row(fit, name::Symbol)
    return only(row for row in tidy(fit).rows if row.name === name)
end

@testset "Golden quantile median (τ=0.5)" begin
    spec = load_golden_spec("quantile_median")
    τ = Float64(get(spec, :quantile_tau, 0.5))
    result = MetricaBase.fit(
        QuantileModel,
        String(spec.formula),
        golden_dataset_path(spec);
        quantile_tau = τ,
    )
    g = glance(result)
    @test String(g.model) == String(spec.expected.glance.model)
    @test g.nobs == Int(spec.expected.glance.nobs)
    tol = golden_tolerance_dict(spec)
    for expected_row in spec.expected.tidy
        row = _coef_row(result, Symbol(expected_row.name))
        @test assert_golden_close(row.estimate, expected_row.estimate, tol["coefficient"])
        if !isnothing(row.stderror) && isfinite(expected_row.stderror)
            @test assert_golden_close(row.stderror, expected_row.stderror, tol["stderror"])
            @test assert_golden_close(row.statistic, expected_row.statistic, tol["statistic"])
        end
    end
    for expected_metric in spec.expected.metrics
        key = Symbol(expected_metric.name)
        @test haskey(g.metrics, key)
        @test assert_golden_close(Float64(g.metrics[key]), expected_metric.value, tol["metric"])
    end
end
