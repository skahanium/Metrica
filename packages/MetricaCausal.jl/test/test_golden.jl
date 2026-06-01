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
