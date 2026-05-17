using MetricaBayes, MetricaBase, Test, CSV, DataFrames, Statistics, Distributions

@testset "Bayes linear σ² known" begin
    y = [1.0, 2.0, 3.0]; x1 = [0.5, 1.0, 1.5]
    df = DataFrame(y=y, x1=x1)
    r = fit_bayes_linear(df, "y ~ x1"; bayes_sigma2_known=true, bayes_sigma2_value=0.5, bayes_prior_scale=10.0)
    @test r isa BayesFitResult
    @test r.inference_mode == "analytical"
    @test r.sigma2_known
    @test length(r.posterior_mean) == 2
    @test all(isfinite, r.posterior_mean)
    @test all(isfinite, r.posterior_sd)
    @test all(r.posterior_sd .> 0)
    @test r.log_marginal_likelihood !== nothing
    @test isfinite(r.log_marginal_likelihood)
    pl = result_to_payload(r; include_augment=false)
    @test pl["status"] == "success"
    @test haskey(pl["result_payload"], "log_marginal_likelihood")
end

@testset "Bayes linear σ² unknown (NIG)" begin
    y = [1.0, 2.0, 3.0, 2.5, 1.5]; x1 = [0.5, 1.0, 1.5, 1.2, 0.8]
    df = DataFrame(y=y, x1=x1)
    r = fit_bayes_linear(df, "y ~ x1"; bayes_ig_alpha=2.0, bayes_ig_beta=1.0, bayes_prior_scale=10.0)
    @test r isa BayesFitResult
    @test length(r.posterior_mean) == 2
    @test r.credible_lower[1] < r.credible_upper[1]
    @test r.log_marginal_likelihood === nothing
    pl = result_to_payload(r; include_augment=false)
    @test haskey(pl["result_payload"], "log_marginal_likelihood_not_available_reason")
end

@testset "Bayes capabilities" begin
    y = [1.0, 2.0]; x1 = [0.5, 1.0]
    df = DataFrame(y=y, x1=x1)
    r = fit_bayes_linear(df, "y ~ x1"; bayes_sigma2_known=true, bayes_sigma2_value=1.0)
    caps = MetricaBase.model_capabilities(r)
    @test caps.model_family == :bayes
    @test :posterior_mean in caps.diagnostics_available
end
