# === 后验预测分布 ===============================================================

function posterior_predictive(r::BayesFitResult, X_new::Matrix{Float64}; n_draws::Int=1000)
    n = size(X_new, 1); p = size(X_new, 2)
    p == r.n_coef || error("X_new 列数须与拟合系数数一致")
    if r.sigma2_known
        σ = sqrt(r.sigma2_value)
        Σ = σ^2 * inv(Symmetric(r.diagnostics[:post_prec]))
        draws = rand(MvNormal(r.posterior_mean, Symmetric(Σ)), n_draws)
    else
        α_n = r.diagnostics[:alpha_n]; β_n = r.diagnostics[:beta_n]
        Σ_n = r.diagnostics[:Sigma_n]
        scale = sqrt(β_n / α_n)
        draws = zeros(p, n_draws)
        for i in 1:n_draws
            σ2_draw = rand(InverseGamma(α_n, β_n))
            draws[:, i] = rand(MvNormal(r.posterior_mean, Symmetric(Σ_n .* σ2_draw)))
        end
    end
    n_new = size(X_new, 1)
    preds = zeros(n_new, n_draws)
    for j in 1:n_draws
        preds[:, j] = X_new * draws[:, j]
    end
    pred_mean = vec(mean(preds, dims=2))
    pred_lo = [quantile(view(preds, i, :), 0.025) for i in 1:n_new]
    pred_hi = [quantile(view(preds, i, :), 0.975) for i in 1:n_new]
    return Dict{Symbol, Any}(:mean => pred_mean, :ci_lower => pred_lo, :ci_upper => pred_hi)
end
