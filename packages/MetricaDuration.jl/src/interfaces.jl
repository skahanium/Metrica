# === MetricaBase 接口：glance / tidy / coef =================================

function MetricaBase.nobs(r::CoxFitResult)::Int
    return r.n
end

function MetricaBase.dof(r::CoxFitResult)::Int
    return length(r.beta)
end

function MetricaBase.coef(r::CoxFitResult)::Vector{Pair{Symbol, Float64}}
    return [nm => b for (nm, b) in zip(r.coef_names, r.beta)]
end

function MetricaBase.stderror(r::CoxFitResult)::Union{Nothing, Vector{Float64}}
    return r.se
end

function MetricaBase.glance(r::CoxFitResult)::MetricaBase.ModelGlance
    metrics = Dict{Symbol, MetricaBase.MetricValue}()
    metrics[:loglik] = r.loglik
    metrics[:n_events] = r.n_events
    metrics[:n_censored] = r.n_censored
    metrics[:censoring_fraction] = r.n_censored / max(r.n, 1)
    return MetricaBase.ModelGlance(:duration_cox, r.n, length(r.beta), metrics, r.warnings)
end

function MetricaBase.tidy(r::CoxFitResult)::MetricaBase.TidyTable
    rows = MetricaBase.CoefRow[]
    zcrit = 1.9599639845400536
    for i in eachindex(r.coef_names)
        nm = r.coef_names[i]
        β = r.beta[i]
        se = r.se[i]
        z = se > 0 ? β / se : nothing
        pv = if z === nothing
            nothing
        else
            2 * ccdf(Normal(0.0, 1.0), abs(z))
        end
        lo = se > 0 ? β - zcrit * se : nothing
        hi = se > 0 ? β + zcrit * se : nothing
        push!(
            rows,
            MetricaBase.CoefRow(nm, β, se, z, pv, lo, hi),
        )
    end
    return MetricaBase.TidyTable(rows, "cox_neg_loglik_finite_diff_hessian")
end

function MetricaBase.model_capabilities(r::CoxFitResult)::MetricaBase.ModelCapabilities
    return MetricaBase.ModelCapabilities(
        :implemented,
        :duration,
        [:duration_cox],
        ["Efron partial likelihood + Optim (Nelder-Mead) + FiniteDiff Hessian"],
        [:n_events, :n_censored, :censoring_fraction, :loglik, :aic, :bic,
         :baseline_hazard, :baseline_survival, :hazard_ratios,
         :schoenfeld_residuals, :ph_global_test, :ph_variable_tests,
         :strata, :cluster_se, :case_weights, :time_varying_covariates],
        Symbol[],
        [:hazard_ratios],
        false,
        String[],
    )
end
