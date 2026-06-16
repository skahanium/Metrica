using Test
using CSV
using DataFrames
using MetricaBase
using MetricaCausal

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

@testset "Golden DID" begin
    spec = load_golden_spec("causal_did")
    df = CSV.read(golden_dataset_path(spec), DataFrame)
    result = MetricaBase.fit(
        DIDModel,
        String(spec.formula),
        df;
        panel_id = :id,
        panel_time = :time,
        treated_column = :treated,
        post_column = :post,
    )
    g = glance(result)
    @test String(g.model) == String(spec.expected.glance.model)
    @test g.nobs == Int(spec.expected.glance.nobs)
    tol = golden_tolerance_dict(spec)
    for expected_metric in spec.expected.metrics
        key = String(expected_metric.name)
        if key == "treat_effect"
            @test assert_golden_close(result.treat_effect, expected_metric.value, tol["metric"])
        elseif key == "treat_effect_se"
            @test assert_golden_close(result.treat_effect_se, expected_metric.value, tol["metric"])
        end
    end
end

@testset "Golden IPW" begin
    spec = load_golden_spec("causal_ipw")
    df = CSV.read(golden_dataset_path(spec), DataFrame)
    result = MetricaBase.fit(
        IPWModel,
        "",
        df;
        treatment_column = Symbol(spec.treatment_column),
        outcome_column = Symbol(spec.outcome_column),
        propensity_formula = String(spec.propensity_formula),
    )
    g = glance(result)
    @test String(g.model) == String(spec.expected.glance.model)
    @test g.nobs == Int(spec.expected.glance.nobs)
    tol = golden_tolerance_dict(spec)
    for expected_metric in spec.expected.metrics
        key = String(expected_metric.name)
        val = if key == "ate"
            result.ate
        elseif key == "att"
            result.att
        else
            result.atu
        end
        @test assert_golden_close(val, expected_metric.value, tol["metric"])
    end
    for expected_row in spec.expected.tidy
        row = only(r for r in tidy(result).rows if String(r.name) == String(expected_row.name))
        @test assert_golden_close(row.estimate, expected_row.estimate, tol["coefficient"])
        @test assert_golden_close(row.stderror, expected_row.stderror, tol["stderror"])
    end
end
