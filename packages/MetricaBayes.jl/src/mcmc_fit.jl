# === MCMC (Metropolis-Hastings) with R-hat, ESS, trace ============================

function fit_bayes_linear_mcmc(df::DataFrame, formula::AbstractString;
    bayes_seed::Union{Nothing, Int}=nothing, bayes_prior_scale::Float64=1.0,
    bayes_iter::Int=2000, bayes_warmup::Int=500, bayes_chains::Int=2)
    isnothing(bayes_seed) || Random.seed!(bayes_seed)
    parsed = MetricaBase.parse_metrica_formula(formula)
    parsed isa MetricaBase.ModelError && return parsed
    yname, xnames = parsed
    sub = select(df, Symbol.([yname; xnames])); dropmissing!(sub)
    n = nrow(sub); y = Float64.(sub[!, Symbol(yname)])
    X = hcat(ones(n), [Float64.(sub[!, Symbol(c)]) for c in xnames]...)
    p = size(X, 2)

    tau2 = bayes_prior_scale^2
    keep = bayes_iter - bayes_warmup; n_total = keep * bayes_chains
    all_samples = zeros(n_total, p); all_sigma2 = zeros(n_total)

    for chain in 1:bayes_chains
        beta_curr = X \ y; sigma2_curr = var(y) * 0.5
        fixed_idx = keep * (chain - 1)
        for iter in 1:bayes_iter
            # MH for beta
            beta_prop = beta_curr + randn(p) .* sqrt(sigma2_curr / n) .* 0.1
            ll_prop = -dot(y - X * beta_prop, y - X * beta_prop) / (2sigma2_curr) - dot(beta_prop, beta_prop) / (2tau2)
            ll_curr = -dot(y - X * beta_curr, y - X * beta_curr) / (2sigma2_curr) - dot(beta_curr, beta_curr) / (2tau2)
            if log(rand()) < ll_prop - ll_curr; beta_curr = beta_prop; end
            # Gibbs for sigma²
            resid = y - X * beta_curr
            alpha_post = 2.0 + n/2; beta_post = 1.0 + dot(resid, resid)/2
            sigma2_curr = rand(InverseGamma(alpha_post, beta_post))
            if iter > bayes_warmup
                idx = fixed_idx + iter - bayes_warmup
                all_samples[idx, :] = beta_curr; all_sigma2[idx] = sigma2_curr
            end
        end
    end

    post_mean = vec(mean(all_samples, dims=1)); post_sd = vec(std(all_samples, dims=1))
    ci_lo = [quantile(all_samples[:, j], 0.025) for j in 1:p]
    ci_hi = [quantile(all_samples[:, j], 0.975) for j in 1:p]

    # R-hat (split R-hat, Gelman-Rubin)
    rhat = fill(NaN, p)
    for j in 1:p
        c1 = all_samples[1:keep, j]; c2 = all_samples[keep+1:end, j]
        W = (var(c1) + var(c2)) / 2; B = keep * var(mean.([c1, c2]))
        V_hat = (keep - 1)/keep * W + B/keep; rhat[j] = sqrt(V_hat / max(W, 1e-18))
    end

    # ESS (effective sample size)
    ess_vec = fill(NaN, p)
    for j in 1:p
        x = all_samples[:, j] .- mean(all_samples[:, j])
        v = dot(x, x)
        max_lag = min(50, n_total - 1); rho_sum = 0.0
        for lag in 1:max_lag
            rho = dot(x[1:end-lag], x[lag+1:end]) / v
            rho > 0 || break; rho_sum += rho
        end
        ess_vec[j] = n_total / (1 + 2 * rho_sum)
    end

    # Trace summary
    trace_summary = Dict(:n_iter => bayes_iter, :n_warmup => bayes_warmup, :n_chains => bayes_chains, :n_kept => keep)

    coef_names = vcat([:intercept], Symbol.(xnames))
    diag = Dict{Symbol, Any}(
        :inference_mode => "mcmc", :seed_used => bayes_seed,
        :r_hat => rhat, :ess => ess_vec, :trace_summary => trace_summary,
        :sigma2_posterior_mean => mean(all_sigma2),
    )

    t_crit = quantile(Normal(), 0.975)
    return BayesFitResult(formula, post_mean, post_sd, post_mean .- t_crit .* post_sd, post_mean .+ t_crit .* post_sd,
        coef_names, "mcmc", "normal_independent", false, mean(all_sigma2), nothing, n, p, bayes_seed, diag, MetricaBase.ModelWarning[])
end
