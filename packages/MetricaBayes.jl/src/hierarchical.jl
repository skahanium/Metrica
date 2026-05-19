# === 层级线性模型 (Random Intercepts, Gibbs Sampler) =============================

function fit_bayes_hierarchical(df::DataFrame, formula::AbstractString, group_col::Symbol;
    bayes_seed::Union{Nothing, Int}=nothing, bayes_prior_scale::Float64=10.0,
    bayes_iter::Int=3000, bayes_warmup::Int=750, bayes_chains::Int=1)
    isnothing(bayes_seed) || Random.seed!(bayes_seed)
    parsed = MetricaBase.parse_metrica_formula(formula)
    parsed isa MetricaBase.ModelError && return parsed
    yname, xnames = parsed
    sub = select(df, Symbol.([yname; xnames; group_col])); dropmissing!(sub)
    n = nrow(sub); y = Float64.(sub[!, Symbol(yname)])
    X = hcat(ones(n), [Float64.(sub[!, Symbol(c)]) for c in xnames]...)
    p = size(X, 2)

    gids = sub[!, group_col]; ug = unique(gids); G = length(ug)
    gidx = [findfirst(x -> x == g, ug) for g in gids]

    tau2 = bayes_prior_scale^2; keep = bayes_iter - bayes_warmup; n_total = keep * bayes_chains
    beta_samples = zeros(n_total, p)
    sigma2_samples = zeros(n_total); sigma_alpha2_samples = zeros(n_total)

    for chain in 1:bayes_chains
        beta = X \ y; sigma2 = var(y) * 0.5; sigma_alpha2 = sigma2 * 0.1
        alpha = zeros(G); fixed_idx = keep * (chain - 1)
        for iter in 1:bayes_iter
            # α | β, σ², σ_α² (per group posterior)
            for g in 1:G
                mg = findall(gidx .== g); ng = length(mg)
                yg = y[mg]; Xg = X[mg, :]; resid_g = yg .- Xg * beta
                post_var = 1 / (ng / sigma2 + 1 / sigma_alpha2)
                post_mu = post_var * (sum(resid_g) / sigma2)
                alpha[g] = rand(Normal(post_mu, sqrt(post_var)))
            end
            # β | α, σ²
            y_adj = y .- alpha[gidx]
            post_prec = X' * X / sigma2 + I(p)/tau2
            post_cov = Symmetric(post_prec) \ Matrix{Float64}(I, p, p)
            post_mu = post_cov * (X' * y_adj / sigma2)
            beta = rand(MvNormal(post_mu, Symmetric(post_cov)))
            # σ²
            resid = y_adj - X * beta
            sigma2 = rand(InverseGamma(2.0 + n/2, 1.0 + dot(resid, resid)/2))
            # σ_α²
            sigma_alpha2 = rand(InverseGamma(2.0 + G/2, 1.0 + dot(alpha, alpha)/2))

            if iter > bayes_warmup
                idx = fixed_idx + iter - bayes_warmup
                beta_samples[idx, :] = beta; sigma2_samples[idx] = sigma2; sigma_alpha2_samples[idx] = sigma_alpha2
            end
        end
    end

    post_mean = vec(mean(beta_samples, dims=1)); post_sd = vec(std(beta_samples, dims=1))
    ci_lo = [quantile(beta_samples[:, j], 0.025) for j in 1:p]; ci_hi = [quantile(beta_samples[:, j], 0.975) for j in 1:p]
    diag = Dict{Symbol, Any}(:inference_mode => "mcmc", :seed_used => bayes_seed,
        :sigma2_mean => mean(sigma2_samples), :sigma_alpha2_mean => mean(sigma_alpha2_samples),
        :n_groups => G, :r_hat => nothing, :ess => nothing,
        :trace_summary => Dict(:n_iter => bayes_iter, :n_warmup => bayes_warmup, :n_chains => bayes_chains))
    coef_names = vcat([:intercept], Symbol.(xnames))
    return BayesFitResult(formula, post_mean, post_sd, ci_lo, ci_hi,
        coef_names, "mcmc", "normal_independent", false, NaN, nothing, n, p, bayes_seed, diag, MetricaBase.ModelWarning[])
end
