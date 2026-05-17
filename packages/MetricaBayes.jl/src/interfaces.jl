MetricaBase.glance(r::BayesFitResult) = MetricaBase.ModelGlance(
    :bayes_linear, r.n_obs, r.n_obs - r.n_coef,
    Dict{Symbol, MetricaBase.MetricValue}(
        :prior_family => 1.0,
        :log_marginal_likelihood => isnothing(r.log_marginal_likelihood) ? NaN : r.log_marginal_likelihood,
    ), r.warnings)

MetricaBase.tidy(r::BayesFitResult) = MetricaBase.TidyTable(
    [MetricaBase.CoefRow(r.coef_names[i], r.posterior_mean[i], nothing, nothing, nothing, r.credible_lower[i], r.credible_upper[i]) for i in eachindex(r.coef_names)],
    "bayes_nig_conjugate")

MetricaBase.nobs(r::BayesFitResult) = r.n_obs

function MetricaBase.model_capabilities(r::BayesFitResult)::MetricaBase.ModelCapabilities
    return MetricaBase.ModelCapabilities(
        :partial,
        :bayes,
        [:bayes_linear],
        ["NIG conjugate (analytical)"],
        [:posterior_mean, :posterior_sd, :credible_interval, :log_marginal_likelihood],
        [:mcmc, :r_hat, :ess, :bayes_logistic, :hierarchical],
        Symbol[],
        false,
        ["首期仅支持共轭贝叶斯线性回归。MCMC、logistic、层级模型为后续功能。"],
    )
end
