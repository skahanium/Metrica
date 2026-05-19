# === Bayesian Logistic Regression (MH sampler) ===================================

function fit_bayes_logistic(df::DataFrame, formula::AbstractString;
    bayes_seed::Union{Nothing, Int}=nothing, bayes_prior_scale::Float64=5.0,
    bayes_iter::Int=3000, bayes_warmup::Int=750, bayes_chains::Int=1)
    isnothing(bayes_seed) || Random.seed!(bayes_seed)
    parsed = MetricaBase.parse_metrica_formula(formula)
    parsed isa MetricaBase.ModelError && return parsed
    yname, xnames = parsed
    sub = select(df, Symbol.([yname; xnames])); dropmissing!(sub)
    n = nrow(sub); y = Int.(Float64.(sub[!, Symbol(yname)]))
    all(y .∈ ((0, 1),)) || return MetricaBase.ModelError(:logistic_binary, "y 必须为 0/1", "", "")
    X = hcat(ones(n), [Float64.(sub[!, Symbol(c)]) for c in xnames]...)
    p = size(X, 2); tau2 = bayes_prior_scale^2
    keep = bayes_iter - bayes_warmup; n_total = keep * bayes_chains
    all_samples = zeros(n_total, p)

    for chain in 1:bayes_chains
        beta_curr = X \ (Float64.(y) .- 0.5); fixed_idx = keep * (chain - 1)
        for iter in 1:bayes_iter
            beta_prop = beta_curr + randn(p) .* 0.1
            eta_curr = X * beta_curr; eta_prop = X * beta_prop
            ll_curr = sum(y .* eta_curr .- log.(1 .+ exp.(eta_curr))) - dot(beta_curr, beta_curr)/(2tau2)
            ll_prop = sum(y .* eta_prop .- log.(1 .+ exp.(eta_prop))) - dot(beta_prop, beta_prop)/(2tau2)
            if log(rand()) < ll_prop - ll_curr; beta_curr = beta_prop; end
            if iter > bayes_warmup
                all_samples[fixed_idx + iter - bayes_warmup, :] = beta_curr
            end
        end
    end

    post_mean = vec(mean(all_samples, dims=1)); post_sd = vec(std(all_samples, dims=1))
    ci_lo = [quantile(all_samples[:, j], 0.025) for j in 1:p]; ci_hi = [quantile(all_samples[:, j], 0.975) for j in 1:p]

    rhat = fill(NaN, p); ess_vec = fill(NaN, p)
    if bayes_chains >= 2
        for j in 1:p
            c1 = all_samples[1:keep, j]; c2 = all_samples[keep+1:end, j]
            W = (var(c1) + var(c2))/2; B = keep * var(mean.([c1, c2]))
            V_hat = (keep-1)/keep * W + B/keep; rhat[j] = sqrt(V_hat / max(W, 1e-18))
        end
    end
    for j in 1:p
        x = all_samples[:, j] .- mean(all_samples[:, j]); v = dot(x, x)
        max_lag = min(50, n_total - 1); rho_sum = 0.0
        for lag in 1:max_lag
            rho = dot(x[1:end-lag], x[lag+1:end]) / v; rho > 0 || break; rho_sum += rho end
        ess_vec[j] = n_total / (1 + 2 * rho_sum)
    end

    diag = Dict{Symbol, Any}(:inference_mode => "mcmc", :seed_used => bayes_seed,
        :r_hat => rhat, :ess => ess_vec, :model => "logistic",
        :trace_summary => Dict(:n_iter => bayes_iter, :n_warmup => bayes_warmup, :n_chains => bayes_chains))

    coef_names = vcat([:intercept], Symbol.(xnames))
    return BayesFitResult(formula, post_mean, post_sd, ci_lo, ci_hi,
        coef_names, "mcmc", "normal_independent", false, NaN, nothing, n, p, bayes_seed, diag, MetricaBase.ModelWarning[])
end

function fit_bayes_probit(df::DataFrame, formula::AbstractString;
    bayes_seed::Union{Nothing, Int}=nothing, bayes_prior_scale::Float64=5.0,
    bayes_iter::Int=3000, bayes_warmup::Int=750, bayes_chains::Int=1)
    # probit uses data augmentation (Albert-Chib): z ~ N(Xβ, 1), y = 1(z > 0)
    isnothing(bayes_seed) || Random.seed!(bayes_seed)
    parsed = MetricaBase.parse_metrica_formula(formula)
    parsed isa MetricaBase.ModelError && return parsed
    yname, xnames = parsed
    sub = select(df, Symbol.([yname; xnames])); dropmissing!(sub)
    n = nrow(sub); y = Int.(Float64.(sub[!, Symbol(yname)]))
    X = hcat(ones(n), [Float64.(sub[!, Symbol(c)]) for c in xnames]...)
    p = size(X, 2); tau2 = bayes_prior_scale^2
    keep = bayes_iter - bayes_warmup; n_total = keep * bayes_chains
    all_samples = zeros(n_total, p)

    for chain in 1:bayes_chains
        beta_curr = X \ (Float64.(y) .- 0.5); fixed_idx = keep * (chain - 1)
        z = zeros(n)
        for iter in 1:bayes_iter
            # data augmentation: z | β, y
            mu = X * beta_curr
            for i in 1:n
                z[i] = y[i] == 1 ? rand(Truncated(Normal(mu[i], 1.0), 0.0, Inf)) : rand(Truncated(Normal(mu[i], 1.0), -Inf, 0.0))
            end
            # β | z
            prec = X' * X + I(p)/tau2
            post_cov = Symmetric(prec) \ Matrix{Float64}(I, p, p)
            post_mu = post_cov * (X' * z)
            beta_curr = rand(MvNormal(post_mu, Symmetric(post_cov)))
            if iter > bayes_warmup
                all_samples[fixed_idx + iter - bayes_warmup, :] = beta_curr
            end
        end
    end

    post_mean = vec(mean(all_samples, dims=1)); post_sd = vec(std(all_samples, dims=1))
    ci_lo = [quantile(all_samples[:, j], 0.025) for j in 1:p]; ci_hi = [quantile(all_samples[:, j], 0.975) for j in 1:p]
    diag = Dict{Symbol, Any}(:inference_mode => "mcmc", :seed_used => bayes_seed,
        :r_hat => nothing, :ess => nothing, :model => "probit",
        :trace_summary => Dict(:n_iter => bayes_iter, :n_warmup => bayes_warmup, :n_chains => bayes_chains))
    coef_names = vcat([:intercept], Symbol.(xnames))
    return BayesFitResult(formula, post_mean, post_sd, ci_lo, ci_hi,
        coef_names, "mcmc", "normal_independent", false, NaN, nothing, n, p, bayes_seed, diag, MetricaBase.ModelWarning[])
end
