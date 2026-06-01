using Test
using CSV
using DataFrames
using MetricaDuration

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

@testset "Golden Cox PH" begin
    spec = load_golden_spec("duration_cox")
    df = CSV.read(golden_dataset_path(spec), DataFrame)
    r = fit_duration_cox(
        df,
        String(spec.formula),
        String(spec.time_column),
        String(spec.event_column);
        ties = :efron,
    )
    @test r.n == Int(spec.expected.glance.nobs)
    tol = golden_tolerance_dict(spec)
    expected_row = only(spec.expected.tidy)
    @test assert_golden_close(r.beta[1], expected_row.estimate, tol["coefficient"])
    @test assert_golden_close(r.se[1], expected_row.stderror, tol["stderror"])
    for expected_metric in spec.expected.metrics
        key = String(expected_metric.name)
        if key == "n_events"
            @test r.n_events == Int(expected_metric.value)
        elseif key == "loglik"
            @test assert_golden_close(r.loglik, expected_metric.value, tol["metric"])
        end
    end
end
