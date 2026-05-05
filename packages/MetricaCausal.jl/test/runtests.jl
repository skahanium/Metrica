using MetricaCausal, MetricaBase, MetricaPanel, MetricaDiscrete
using DataFrames, Distributions, Random, Statistics, Test, LinearAlgebra

Random.seed!(42)

# === TWFE ====================================================================

@testset "TWFE" begin
    n = 100
    ids = repeat(1:10, inner=10)
    times = repeat(1:10, outer=10)
    x = randn(n)
    y = 1.0 .+ 0.5 .* x .+ randn(n) .* 0.05
    X = hcat(ones(n), x)
    twfe = fit_twfe(X, y, ids, times)
    @test length(twfe.coefficients) == 1
    @test abs(twfe.coefficients[1] - 0.5) < 0.2
    @test twfe.dof > 0
    @test size(twfe.vcov) == (1, 1)
end

# === DID =====================================================================

@testset "DID" begin
    # Deterministic DID data: true effect = 2.0
    n = 40
    df = DataFrame(
        id = repeat(1:10, inner=4),
        time = repeat(1:4, outer=10),
        treated = Float64.(repeat([0, 0, 1, 1], inner=10)),
        x1 = ones(n),
    )
    df.post = Float64.(df.time .>= 3)
    df.y = 3.0 .+ 0.5 .* df.treated .+ 0.3 .* df.post .+ 2.0 .* df.treated .* df.post .+ 0.1 .* df.x1

    result = MetricaBase.fit(DIDModel, "y ~ treated * post + x1", df;
        panel_id=:id, panel_time=:time, treated_column=:treated, post_column=:post)
    @test result isa DIDFitResult
    @test abs(result.treat_effect - 2.0) < 1.0
    @test result.treat_effect_se > 0
    @test result.n_treated + result.n_control == 40

    g = MetricaBase.glance(result)
    @test g.model == :did

    t = MetricaBase.tidy(result)
    @test length(t.rows) >= 1

    # 序列化
    payload = MetricaCausal.result_to_payload(result)
    @test payload["status"] == "success"
    @test haskey(payload["result_payload"], "treat_effect")

    # 协议方法
    @test MetricaBase.nobs(result) == 40
    @test length(MetricaBase.coef(result)) >= 1
    @test size(MetricaBase.vcov(result), 1) >= 1
end

# === Event Study =============================================================

@testset "EventStudy" begin
    n = 60
    df = DataFrame(
        id = repeat(1:10, inner=6),
        time = repeat(1:6, outer=10),
        treated = Float64.(repeat([0, 0, 1, 1], inner=15)),
        event_time = repeat([4, 4, 4, 4], inner=15),
        x1 = ones(n),
    )
    df.y = 2.0 .+ 1.0 .* df.treated .* Float64.(df.time .>= 4) .+ 0.1 .* df.x1

    result = MetricaBase.fit(EventStudyModel, "y ~ treated + x1", df;
        panel_id=:id, panel_time=:time, treated_column=:treated,
        event_time_column=:event_time, pre_periods=2, post_periods=2)
    @test result isa EventStudyFitResult
    @test length(result.period_coefficients) >= 1
    @test result.pre_trend_pvalue isa Float64

    g = MetricaBase.glance(result)
    @test g.model == :event_study

    payload = MetricaCausal.result_to_payload(result)
    @test haskey(payload["result_payload"], "period_coefficients")
end

# === IPW =====================================================================

@testset "IPW" begin
    n = 500
    x1 = randn(n); x2 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8*x1 .- 0.3*x2)))
    treat = Float64.(rand(n) .< ps)
    y0 = 2.0 .+ 0.5*x1 .+ 0.2*x2 .+ randn(n)*0.3
    y1 = y0 .+ 1.5
    y = treat.*y1 .+ (1 .- treat).*y0
    df = DataFrame(treat=treat, y=y, x1=x1, x2=x2)

    result = MetricaBase.fit(IPWModel, "", df;
        treatment_column=:treat, outcome_column=:y, propensity_formula="treat ~ x1 + x2")
    @test result isa IPWFitResult
    @test abs(result.ate - 1.5) < 0.5
    @test result.ate_se > 0
end

# === PSM =====================================================================

@testset "PSM" begin
    n = 500
    x1 = randn(n); x2 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8*x1 .- 0.3*x2)))
    treat = Float64.(rand(n) .< ps)
    y0 = 2.0 .+ 0.5*x1 .+ 0.2*x2 .+ randn(n)*0.3
    y1 = y0 .+ 1.5
    y = treat.*y1 .+ (1 .- treat).*y0
    df = DataFrame(treat=treat, y=y, x1=x1, x2=x2)

    result = MetricaBase.fit(PSMModel, "", df;
        treatment_column=:treat, outcome_column=:y, propensity_formula="treat ~ x1 + x2")
    @test result isa PSMFitResult
    @test result.n_matched > 0
    @test abs(result.att - 1.5) < 0.5
    @test nrow(result.balance_table) > 0

    payload = MetricaCausal.result_to_payload(result)
    @test haskey(payload["result_payload"], "balance_table")
end

# === AIPW ====================================================================

@testset "AIPW" begin
    n = 500
    x1 = randn(n); x2 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8*x1 .- 0.3*x2)))
    treat = Float64.(rand(n) .< ps)
    y0 = 2.0 .+ 0.5*x1 .+ 0.2*x2 .+ randn(n)*0.3
    y1 = y0 .+ 1.5
    y = treat.*y1 .+ (1 .- treat).*y0
    df = DataFrame(treat=treat, y=y, x1=x1, x2=x2)

    result = MetricaBase.fit(AIPWModel, "", df;
        treatment_column=:treat, outcome_column=:y,
        outcome_formula="y ~ x1 + x2", propensity_formula="treat ~ x1 + x2")
    @test result isa AIPWFitResult
    @test abs(result.ate - 1.5) < 0.8
    @test result.ate_se > 0
end

# === TreatmentEffectSummary ==================================================

@testset "TreatmentEffectSummary" begin
    n = 300
    x1 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8*x1)))
    treat = Float64.(rand(n) .< ps)
    y0 = 2.0 .+ 0.5*x1 .+ randn(n)*0.3
    y1 = y0 .+ 1.5
    y = treat.*y1 .+ (1 .- treat).*y0
    df = DataFrame(treat=treat, y=y, x1=x1)

    ipw_r = MetricaBase.fit(IPWModel, "", df;
        treatment_column=:treat, outcome_column=:y, propensity_formula="treat ~ x1")
    aipw_r = MetricaBase.fit(AIPWModel, "", df;
        treatment_column=:treat, outcome_column=:y,
        outcome_formula="y ~ x1", propensity_formula="treat ~ x1")

    summaries = compare_estimates(Dict(:ipw => ipw_r, :aipw => aipw_r))
    @test length(summaries) == 2
    @test all(s -> abs(s.ate - 1.5) < 0.8, summaries)
end

# === MODEL_REGISTRY ==========================================================

@testset "MODEL_REGISTRY" begin
    @test haskey(MetricaBase.MODEL_REGISTRY, "did")
    @test haskey(MetricaBase.MODEL_REGISTRY, "event_study")
    @test haskey(MetricaBase.MODEL_REGISTRY, "ipw")
    @test haskey(MetricaBase.MODEL_REGISTRY, "psm")
    @test haskey(MetricaBase.MODEL_REGISTRY, "aipw")
end
