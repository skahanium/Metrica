using Test
using LinearAlgebra: I
using MetricaBase
using MetricaLinear

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

function _coef_row(fit, name::Symbol)
    return only(row for row in tidy(fit).rows if row.name === name)
end

function _run_linear_golden(id::AbstractString, fit_fn)
    spec = load_golden_spec(id)
    data_path = golden_dataset_path(spec)
    result = fit_fn(spec, data_path)
    @test String(glance(result).model) == String(spec.expected.glance.model)
    @test glance(result).nobs == Int(spec.expected.glance.nobs)
    @test glance(result).dof == Int(spec.expected.glance.dof)
    tol = golden_tolerance_dict(spec)
    for expected_row in spec.expected.tidy
        row = _coef_row(result, Symbol(expected_row.name))
        @test assert_golden_close(row.estimate, expected_row.estimate, tol["coefficient"])
        @test assert_golden_close(row.stderror, expected_row.stderror, tol["stderror"])
        @test assert_golden_close(row.statistic, expected_row.statistic, tol["statistic"])
    end
    for expected_metric in spec.expected.metrics
        metric_name = Symbol(expected_metric.name)
        @test haskey(glance(result).metrics, metric_name)
        @test assert_golden_close(
            glance(result).metrics[metric_name],
            expected_metric.value,
            tol["metric"],
        )
    end
    return result
end

@testset "Golden OLS reference" begin
    _run_linear_golden("linear_ols", (spec, data_path) ->
        MetricaBase.fit(OLSModel, String(spec.formula), data_path))
end

@testset "Golden IV reference" begin
    _run_linear_golden("linear_iv", (spec, data_path) ->
        MetricaBase.fit(
            IVModel,
            String(spec.formula),
            data_path;
            instruments = String.(spec.instruments),
            endog = String.(spec.endog_columns),
        ))
end

@testset "Golden GLS reference" begin
    _run_linear_golden("linear_gls", (spec, data_path) -> begin
        omega_fn = r -> Matrix{Float64}(I, length(r), length(r))
        MetricaBase.fit(GLSModel, String(spec.formula), data_path; omega_fn = omega_fn)
    end)
end
