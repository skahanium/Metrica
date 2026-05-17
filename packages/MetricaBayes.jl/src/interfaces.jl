MetricaBase.glance(r::BayesFitResult) = MetricaBase.ModelGlance(
    :bayes_linear, r.n_obs, r.n_obs - r.n_coef,
    Dict{Symbol, MetricaBase.MetricValue}(
        :prior_family => 1.0,
        :log_marginal_likelihood => isnothing(r.log_marginal_likelihood) ? NaN : r.log_marginal_likelihood,
    ), r.warnings)

MetricaBase.tidy(r::BayesFitResult) = MetricaBase.TidyTable(
    [MetricaBase.CoefRow(r.coef_names[i], r.posterior_mean[i], nothing, nothing, nothing, r.credible_lower[i], r.credible_upper[i]) for i in eachindex(r.coef_names)],
    "bayes")

MetricaBase.nobs(r::BayesFitResult) = r.n_obs

function MetricaBase.model_capabilities(r::BayesFitResult)::MetricaBase.ModelCapabilities
    return MetricaBase.ModelCapabilities(
        :partial,
        :bayes,
        [:bayes_linear],
        ["NIG conjugate (analytical)", "MCMC (Metropolis-Hastings + Gibbs)"],
        [:posterior_mean, :posterior_sd, :credible_interval, :posterior_predictive,
         :log_marginal_likelihood, :r_hat, :ess, :trace_summary],
        Symbol[],
        Symbol[],
        false,
        ["Bayesian logistic/probit 与层级模型已可用。MCMC 默认不启用（需显式调用 fit_bayes_linear_mcmc）。"],
    )
end
