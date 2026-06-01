# spatial_probit.jl — 空间 Probit (Bayesian Gibbs 采样)
# y* = ρWy* + Xβ + ε, ε ~ N(0, I_n), y_i = 1(y*_i > 0)

function fit_spatial_probit(y::Vector{Int}, X::Matrix{Float64}, W::Matrix{Float64};
                            n_iter::Int=2000, n_warmup::Int=500,
                            n_chains::Int=1,
                            prior_scale::Float64=10.0,
                            seed::Union{Nothing, Int}=nothing)
    n = length(y)
    p = size(X, 2)
    n > 1000 && return MetricaBase.ModelError(:probit_too_large,
        "空间 Probit 当前限 n ≤ 1000", "n=$n", "请抽样。")
    all(x -> x in (0, 1), y) || return MetricaBase.ModelError(:probit_binary,
        "y 必须为 0/1", "", "")

    isnothing(seed) || Random.seed!(seed)
    prior_prec = 1.0 / prior_scale^2 * I(p)

    n_keep = n_iter - n_warmup
    beta_samples = Matrix{Float64}(undef, n_keep, p)
    rho_samples = Vector{Float64}(undef, n_keep)

    beta = X \ (y .- 0.5)
    rho = 0.0
    y_star = zeros(n)
    rho_proposal_sd = 0.05
    rho_accept = 0

    for iter in 1:n_iter
        # 1. 潜变量 y_star (截断正态)
        Wy_star = W * y_star
        for i in 1:n
            mu_i = dot(X[i, :], beta) + rho * Wy_star[i]
            if y[i] == 1
                y_star[i] = rand(truncated(Normal(mu_i, 1.0), 0.0, Inf))
            else
                y_star[i] = rand(truncated(Normal(mu_i, 1.0), -Inf, 0.0))
            end
        end

        # 2. β (多元正态后验)
        A = I - rho * W
        y_star_star = A * y_star
        posterior_cov = inv(X' * X + prior_prec)
        posterior_mean = posterior_cov * (X' * y_star_star)
        beta = rand(MvNormal(posterior_mean, Symmetric(posterior_cov)))

        # 3. ρ (Metropolis-Hastings)
        rho_prop = rand(Normal(rho, rho_proposal_sd))
        if -0.99 < rho_prop < 0.99
            A_prop = I - rho_prop * W
            logdet_prop = log(abs(det(A_prop)))
            logdet_curr = log(abs(det(A)))
            if isfinite(logdet_prop) && isfinite(logdet_curr)
                y_star_prop = A_prop * y_star - X * beta
                y_star_curr = A * y_star - X * beta
                loglike_prop = -0.5 * dot(y_star_prop, y_star_prop)
                loglike_curr = -0.5 * dot(y_star_curr, y_star_curr)
                log_ratio = loglike_prop + logdet_prop - loglike_curr - logdet_curr
                if log(rand()) < log_ratio
                    rho = rho_prop
                    rho_accept += 1
                end
            end
        end

        if iter > n_warmup
            idx = iter - n_warmup
            beta_samples[idx, :] = beta
            rho_samples[idx] = rho
        end
    end

    beta_mean = vec(mean(beta_samples, dims=1))
    beta_sd = vec(std(beta_samples, dims=1))
    beta_lo = [quantile(beta_samples[:, j], 0.025) for j in 1:p]
    beta_hi = [quantile(beta_samples[:, j], 0.975) for j in 1:p]
    rho_m = mean(rho_samples)
    rho_s = std(rho_samples)
    rho_lo = quantile(rho_samples, 0.025)
    rho_hi = quantile(rho_samples, 0.975)

    coef_names = vcat([:rho], [Symbol("beta_$i") for i in 0:(p-1)])
    post_mean = vcat([rho_m], beta_mean)
    post_sd = vcat([rho_s], beta_sd)
    post_lo = vcat([rho_lo], beta_lo)
    post_hi = vcat([rho_hi], beta_hi)

    diag = Dict{Symbol, Any}(
        :rho_accept_rate => rho_accept / n_iter,
        :n_iter => n_iter,
        :n_warmup => n_warmup,
        :n_chains => n_chains,
        :inference_mode => "mcmc",
    )

    return ProbitFitResult("spatial_probit", n, p + 1, coef_names,
                           post_mean, post_sd, post_lo, post_hi,
                           rho_m, rho_s, rho_lo, rho_hi,
                           n_iter, n_warmup, n_chains, nothing, nothing,
                           diag, MetricaBase.ModelWarning[])
end
