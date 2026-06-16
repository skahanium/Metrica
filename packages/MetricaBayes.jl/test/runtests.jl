using MetricaBayes, MetricaBase, Test, CSV, DataFrames, Statistics, Distributions, Random

include("test_golden.jl")

const DEMO = joinpath(@__DIR__, "..", "..", "..", "datasets", "demo")

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

@testset "Bayes linear coefficient recovery" begin
    Random.seed!(42)
    n = 100
    x = randn(n)
    y = 2.0 .+ 3.0 .* x .+ randn(n) .* 0.4
    df = DataFrame(x=x, y=y)
    r = fit_bayes_linear(
        df, "y ~ x";
        bayes_sigma2_known=true,
        bayes_sigma2_value=0.16,
        bayes_prior_scale=50.0,
    )
    @test r isa BayesFitResult
    @test r.posterior_mean[1] ≈ 2.0 atol=0.6
    @test r.posterior_mean[2] ≈ 3.0 atol=0.6
end

@testset "Bayes logistic MCMC" begin
    Random.seed!(7)
    n = 60
    x = randn(n)
    p = 1 ./ (1 .+ exp.(-(0.5 .+ 1.2 .* x)))
    y = Float64.(rand.(Bernoulli.(p)))
    df = DataFrame(y=y, x=x)
    r = fit_bayes_logistic(
        df, "y ~ x";
        bayes_seed=7,
        bayes_iter=400,
        bayes_warmup=150,
        bayes_chains=1,
    )
    @test r isa BayesFitResult
    @test r.inference_mode == "mcmc"
    @test length(r.posterior_mean) == 2
    fitted_prob = [1 / (1 + exp(-(r.posterior_mean[1] + r.posterior_mean[2] * xi))) for xi in x]
    acc = mean((fitted_prob .> 0.5) .== (df.y .> 0.5))
    @test acc > 0.55
    pl = result_to_payload(r; include_augment=false)
    @test pl["status"] == "success"
    @test haskey(pl["result_payload"]["diagnostics"], "model")
end

@testset "Bayes probit MCMC" begin
    Random.seed!(11)
    n = 50
    x = randn(n)
    y = Float64.(randn(n) .< (0.3 .+ 0.9 .* x))
    df = DataFrame(y=y, x=x)
    r = fit_bayes_probit(
        df, "y ~ x";
        bayes_seed=11,
        bayes_iter=350,
        bayes_warmup=120,
    )
    @test r isa BayesFitResult
    @test all(isfinite, r.posterior_mean)
    @test all(r.posterior_sd .> 0)
end

@testset "Bayes hierarchical with group column" begin
    Random.seed!(3)
    G = 4
    rows = DataFrame(group=Int[], x=Float64[], y=Float64[])
    for g in 1:G
        x = randn(15)
        y = (1.0 + 0.5 * g) .+ 2.0 .* x .+ randn(15) .* 0.3
        append!(rows, DataFrame(group=fill(g, 15), x=x, y=y))
    end
    r = fit_bayes_hierarchical(
        rows, "y ~ x", :group;
        bayes_seed=3,
        bayes_iter=400,
        bayes_warmup=150,
    )
    @test r isa BayesFitResult
    @test r.inference_mode == "mcmc"
    @test length(r.posterior_mean) >= 2
    pl = result_to_payload(r; include_augment=false)
    @test pl["status"] == "success"
end

@testset "Bayes augment empty table" begin
    y = [1.0, 2.0]; x1 = [0.5, 1.0]
    df = DataFrame(y=y, x1=x1)
    r = fit_bayes_linear(df, "y ~ x1"; bayes_sigma2_known=true, bayes_sigma2_value=1.0)
    at = augment(r)
    @test at isa AugmentTable
    @test at.nobs == 0
end

@testset "Bayes capabilities" begin
    y = [1.0, 2.0]; x1 = [0.5, 1.0]
    df = DataFrame(y=y, x1=x1)
    r = fit_bayes_linear(df, "y ~ x1"; bayes_sigma2_known=true, bayes_sigma2_value=1.0)
    caps = MetricaBase.model_capabilities(r)
    @test caps.model_family == :bayes
    @test :posterior_mean in caps.diagnostics_available
end

@testset "Bayes boundaries" begin
    df1 = DataFrame(y=[1.0], x1=[1.0])
    r1 = fit_bayes_linear(df1, "y ~ x1")
    @test r1 isa BayesFitResult || r1 isa ModelError

    df_bad = DataFrame(y=[2.0, 3.0], x1=[1.0, 2.0])
    r_log = fit_bayes_logistic(df_bad, "y ~ x1"; bayes_iter=50, bayes_warmup=20)
    @test r_log isa ModelError

    df_col = DataFrame(y=[1.0, 2.0, 3.0], x1=[1.0, 2.0, 3.0])
    r_col = fit_bayes_linear(df_col, "y ~ x1")
    @test r_col isa ModelError || r_col isa BayesFitResult
end

@testset "Bayes formula parse errors" begin
    df = DataFrame(y=[1.0, 2.0], x1=[1.0, 2.0])
    @test fit_bayes_linear(df, "y ~") isa ModelError
    @test fit_bayes_logistic(df, "") isa ModelError
end

@testset "Bayes tidy 与 glance 接口" begin
    Random.seed!(21)
    n = 40
    x = randn(n)
    y = 1.0 .+ 0.8 .* x .+ randn(n) .* 0.5
    df = DataFrame(y=y, x=x)
    r = fit_bayes_linear(df, "y ~ x"; bayes_sigma2_known=true, bayes_sigma2_value=0.25)
    t = tidy(r)
    @test length(t.rows) == length(r.coef_names)
    @test all(row.ci_lower <= row.ci_upper for row in t.rows)
    g = glance(r)
    @test g.model == :bayes_linear
    @test MetricaBase.nobs(r) == n
    @test r.n_obs - r.n_coef == n - r.n_coef
end

@testset "Bayes 后验预测" begin
    y = [1.0, 2.0, 2.5]; x1 = [0.5, 1.0, 1.2]
    df = DataFrame(y=y, x1=x1)
    r = fit_bayes_linear(df, "y ~ x1"; bayes_sigma2_known=true, bayes_sigma2_value=0.5)
    X_new = [1.0 1.5; 1.0 2.0]
    pp = posterior_predictive(r, X_new; n_draws=100)
    @test length(pp[:mean]) == 2
    @test all(isfinite, pp[:mean])
    @test all(pp[:ci_lower] .<= pp[:ci_upper])
end

@testset "Bayes linear MCMC" begin
    Random.seed!(5)
    n = 30
    x = randn(n)
    y = 0.5 .+ 1.1 .* x .+ randn(n) .* 0.3
    df = DataFrame(y=y, x=x)
    r = fit_bayes_linear_mcmc(
        df, "y ~ x";
        bayes_seed=5,
        bayes_iter=180,
        bayes_warmup=60,
        bayes_chains=2,
    )
    @test r isa BayesFitResult
    @test r.inference_mode == "mcmc"
    @test haskey(r.diagnostics, :r_hat)
    pl = result_to_payload(r; include_augment=false)
    @test pl["status"] == "success"
    @test !isempty(pl["result_payload"]["tidy"])
end

@testset "Bayes payload 结构" begin
    df = DataFrame(y=[1.0, 2.0, 3.0], x1=[0.5, 1.0, 1.5])
    r = fit_bayes_linear(df, "y ~ x1"; bayes_sigma2_known=true, bayes_sigma2_value=1.0)
    pl = result_to_payload(r; include_augment=false)
    rp = pl["result_payload"]
    @test haskey(rp, "glance")
    @test haskey(rp, "tidy")
    @test rp["tidy"][1]["name"] isa String
    @test haskey(rp, "model_capabilities")
end

@testset "Bayes 层级缺失 group 列" begin
    df = DataFrame(y=[1.0, 2.0], x=[1.0, 2.0])
    @test_throws ArgumentError fit_bayes_hierarchical(df, "y ~ x", :group; bayes_iter=50, bayes_warmup=20)
end

@testset "Bayes MCMC 缺列" begin
    df = DataFrame(y=[1.0, 2.0], x1=[1.0, 2.0])
    @test_throws Exception fit_bayes_linear_mcmc(df, "y ~ missing"; bayes_iter=50, bayes_warmup=20)
end

@testset "Bayes linear 单观测可拟合" begin
    df = DataFrame(y=[2.0], x1=[1.0])
    r = fit_bayes_linear(df, "y ~ x1"; bayes_sigma2_known=true, bayes_sigma2_value=1.0)
    @test r isa BayesFitResult
    @test r.n_obs == 1
end

@testset "Bayes linear 全缺失行后无有效样本" begin
    df = DataFrame(y=[missing, missing], x1=[missing, 1.0])
    r = fit_bayes_linear(df, "y ~ x1"; bayes_sigma2_known=true, bayes_sigma2_value=1.0)
    @test r isa MetricaBase.ModelError || r isa BayesFitResult
    if r isa MetricaBase.ModelError
        @test r.code == :bayes_empty_sample
    end
end
