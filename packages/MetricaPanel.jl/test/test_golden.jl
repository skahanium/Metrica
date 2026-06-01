using Test
using CSV
using DataFrames
using MetricaBase: PanelData
using MetricaPanel: fit_dynamic_panel_gmm

include(joinpath(@__DIR__, "..", "..", "MetricaBase.jl", "test", "golden_test_helpers.jl"))

@testset "Golden dynamic_panel_gmm" begin
    spec = load_golden_spec("panel_dynamic_gmm")
    df = CSV.read(golden_dataset_path(spec), DataFrame)
    pd = PanelData(df, Symbol(spec.panel_id), Symbol(spec.panel_time))
    lags = Tuple(Int.(spec.instrument_lags))
    r = fit_dynamic_panel_gmm(pd, String(spec.formula); instrument_lags = lags, gmm_weight = "two_step")
    @test r.n_obs_diff == Int(spec.expected.glance.nobs)
    tol = golden_tolerance_dict(spec)
    for expected_row in spec.expected.tidy
        idx = findfirst(n -> String(n) == String(expected_row.name), r.coefficient_names)
        @test idx !== nothing
        @test assert_golden_close(r.coefficient_values[idx], expected_row.estimate, tol["coefficient"])
    end
    for expected_metric in spec.expected.metrics
        if String(expected_metric.name) == "n_obs_diff"
            @test r.n_obs_diff == Int(expected_metric.value)
        end
    end
end
