# === 序列化 ==================================================================

function result_to_payload(result::LogitFitResult; include_augment::Bool=true)
    glance_table = result.glance_table
    tidy_table = result.tidy_table

    messages = [Dict(
        "level" => lowercase(String(Symbol(w.severity))),
        "code" => String(w.code),
        "text" => w.detail,
        "hint" => w.hint,
    ) for w in glance_table.warnings]

    ors = exp.(result.coefficient_values)
    se_log_or = result.stderror_values
    odds_ratios = [Dict(
        "term" => String(name),
        "odds_ratio" => ors[i],
        "ci_lower" => exp(result.coefficient_values[i] - 1.96 * se_log_or[i]),
        "ci_upper" => exp(result.coefficient_values[i] + 1.96 * se_log_or[i]),
    ) for (i, name) in enumerate(result.coefficient_names)]

    payload = Dict(
        "status" => "success",
        "messages" => messages,
        "result_payload" => Dict(
            "glance" => Dict(
                "model" => String(glance_table.model),
                "nobs" => glance_table.nobs,
                "dof" => glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in glance_table.metrics),
            ),
            "tidy" => [Dict(
                "term" => String(row.name),
                "estimate" => row.estimate,
                "std_error" => row.stderror,
                "statistic" => row.statistic,
                "p_value" => row.pvalue,
                "ci_lower" => row.ci_lower,
                "ci_upper" => row.ci_upper,
            ) for row in tidy_table.rows],
            "odds_ratios" => odds_ratios,
            "warnings" => [Dict(
                "code" => String(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint,
                "severity" => lowercase(String(Symbol(w.severity))),
            ) for w in glance_table.warnings],
            "summary_text" => "model=logit, nobs=$(glance_table.nobs), pseudo_r2=$(round(glance_table.metrics[:pseudo_r2], digits=4))",
            "loglikelihood" => result.loglikelihood,
            "aic" => glance_table.metrics[:aic],
            "bic" => glance_table.metrics[:bic],
            "iterations" => result.iterations,
            "converged" => result.converged,
        ),
        "artifacts" => [],
    )

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = min(100, at.nobs)
        payload["result_payload"]["augment_preview"] = Dict(
            String(k) => v[1:max_preview] for (k, v) in at.columns
        )
    end

    return payload
end

function result_to_payload(result::ProbitFitResult; include_augment::Bool=true)
    glance_table = result.glance_table
    tidy_table = result.tidy_table
    messages = [Dict("level" => lowercase(String(Symbol(w.severity))), "code" => String(w.code), "text" => w.detail, "hint" => w.hint) for w in glance_table.warnings]

    payload = Dict(
        "status" => "success",
        "messages" => messages,
        "result_payload" => Dict(
            "glance" => Dict("model" => String(glance_table.model), "nobs" => glance_table.nobs, "dof" => glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in glance_table.metrics)),
            "tidy" => [Dict("term" => String(row.name), "estimate" => row.estimate, "std_error" => row.stderror, "statistic" => row.statistic, "p_value" => row.pvalue, "ci_lower" => row.ci_lower, "ci_upper" => row.ci_upper) for row in tidy_table.rows],
            "warnings" => [Dict("code" => String(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint, "severity" => lowercase(String(Symbol(w.severity)))) for w in glance_table.warnings],
            "summary_text" => "model=probit, nobs=$(glance_table.nobs), pseudo_r2=$(round(glance_table.metrics[:pseudo_r2], digits=4))",
            "loglikelihood" => result.loglikelihood, "aic" => glance_table.metrics[:aic], "bic" => glance_table.metrics[:bic],
            "iterations" => result.iterations, "converged" => result.converged,
        ),
        "artifacts" => [],
    )

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = min(100, at.nobs)
        payload["result_payload"]["augment_preview"] = Dict(String(k) => v[1:max_preview] for (k, v) in at.columns)
    end

    return payload
end

function result_to_payload(result::PoissonFitResult; include_augment::Bool=true)
    glance_table = result.glance_table
    tidy_table = result.tidy_table
    messages = [Dict("level" => lowercase(String(Symbol(w.severity))), "code" => String(w.code), "text" => w.detail, "hint" => w.hint) for w in glance_table.warnings]

    irrs = [Dict("term" => String(name), "irr" => exp(result.coefficient_values[i])) for (i, name) in enumerate(result.coefficient_names)]

    payload = Dict(
        "status" => "success",
        "messages" => messages,
        "result_payload" => Dict(
            "glance" => Dict("model" => String(glance_table.model), "nobs" => glance_table.nobs, "dof" => glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in glance_table.metrics)),
            "tidy" => [Dict("term" => String(row.name), "estimate" => row.estimate, "std_error" => row.stderror, "statistic" => row.statistic, "p_value" => row.pvalue, "ci_lower" => row.ci_lower, "ci_upper" => row.ci_upper) for row in tidy_table.rows],
            "incidence_rate_ratios" => irrs,
            "warnings" => [Dict("code" => String(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint, "severity" => lowercase(String(Symbol(w.severity)))) for w in glance_table.warnings],
            "summary_text" => "model=poisson, nobs=$(glance_table.nobs), pseudo_r2=$(round(glance_table.metrics[:pseudo_r2], digits=4))",
            "loglikelihood" => result.loglikelihood, "aic" => glance_table.metrics[:aic], "bic" => glance_table.metrics[:bic],
            "iterations" => result.iterations, "converged" => result.converged,
        ),
        "artifacts" => [],
    )

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = min(100, at.nobs)
        payload["result_payload"]["augment_preview"] = Dict(String(k) => v[1:max_preview] for (k, v) in at.columns)
    end

    return payload
end

function result_to_payload(result::NegBinFitResult; include_augment::Bool=true)
    glance_table = result.glance_table
    tidy_table = result.tidy_table
    messages = [Dict("level" => lowercase(String(Symbol(w.severity))), "code" => String(w.code), "text" => w.detail, "hint" => w.hint) for w in glance_table.warnings]

    payload = Dict(
        "status" => "success",
        "messages" => messages,
        "result_payload" => Dict(
            "glance" => Dict("model" => String(glance_table.model), "nobs" => glance_table.nobs, "dof" => glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in glance_table.metrics)),
            "tidy" => [Dict("term" => String(row.name), "estimate" => row.estimate, "std_error" => row.stderror, "statistic" => row.statistic, "p_value" => row.pvalue, "ci_lower" => row.ci_lower, "ci_upper" => row.ci_upper) for row in tidy_table.rows],
            "warnings" => [Dict("code" => String(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint, "severity" => lowercase(String(Symbol(w.severity)))) for w in glance_table.warnings],
            "summary_text" => "model=negbin, nobs=$(glance_table.nobs), dispersion=$(round(result.dispersion, digits=4))",
            "loglikelihood" => result.loglikelihood, "aic" => glance_table.metrics[:aic], "bic" => glance_table.metrics[:bic],
            "dispersion" => result.dispersion,
            "iterations" => result.iterations, "converged" => result.converged,
        ),
        "artifacts" => [],
    )

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = min(100, at.nobs)
        payload["result_payload"]["augment_preview"] = Dict(String(k) => v[1:max_preview] for (k, v) in at.columns)
    end

    return payload
end

function result_to_payload(result::OrderedLogitFitResult; include_augment::Bool=true)
    glance_table = result.glance_table
    tidy_table = result.tidy_table
    messages = [Dict("level" => lowercase(String(Symbol(w.severity))), "code" => String(w.code), "text" => w.detail, "hint" => w.hint) for w in glance_table.warnings]

    ors = exp.(result.coefficient_values)
    se_log_or = result.stderror_values
    odds_ratios = [Dict(
        "term" => String(name),
        "odds_ratio" => ors[i],
        "ci_lower" => exp(result.coefficient_values[i] - 1.96 * se_log_or[i]),
        "ci_upper" => exp(result.coefficient_values[i] + 1.96 * se_log_or[i]),
    ) for (i, name) in enumerate(result.coefficient_names)]

    payload = Dict(
        "status" => "success",
        "messages" => messages,
        "result_payload" => Dict(
            "glance" => Dict("model" => String(glance_table.model), "nobs" => glance_table.nobs, "dof" => glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in glance_table.metrics)),
            "tidy" => [Dict("term" => String(row.name), "estimate" => row.estimate, "std_error" => row.stderror, "statistic" => row.statistic, "p_value" => row.pvalue, "ci_lower" => row.ci_lower, "ci_upper" => row.ci_upper) for row in tidy_table.rows],
            "odds_ratios" => odds_ratios,
            "thresholds" => result.thresholds,
            "n_categories" => result.n_categories,
            "warnings" => [Dict("code" => String(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint, "severity" => lowercase(String(Symbol(w.severity)))) for w in glance_table.warnings],
            "summary_text" => "model=ordered_logit, nobs=$(glance_table.nobs), categories=$(result.n_categories)",
            "loglikelihood" => result.loglikelihood, "aic" => glance_table.metrics[:aic], "bic" => glance_table.metrics[:bic],
            "iterations" => result.iterations, "converged" => result.converged,
        ),
        "artifacts" => [],
    )

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = min(100, at.nobs)
        payload["result_payload"]["augment_preview"] = Dict(String(k) => v[1:max_preview] for (k, v) in at.columns)
    end

    return payload
end

function result_to_payload(result::MultinomialLogitFitResult; include_augment::Bool=true)
    glance_table = result.glance_table
    tidy_table = result.tidy_table
    messages = [Dict("level" => lowercase(String(Symbol(w.severity))), "code" => String(w.code), "text" => w.detail, "hint" => w.hint) for w in glance_table.warnings]

    payload = Dict(
        "status" => "success",
        "messages" => messages,
        "result_payload" => Dict(
            "glance" => Dict("model" => String(glance_table.model), "nobs" => glance_table.nobs, "dof" => glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in glance_table.metrics)),
            "tidy" => [Dict("term" => String(row.name), "estimate" => row.estimate, "std_error" => row.stderror, "statistic" => row.statistic, "p_value" => row.pvalue, "ci_lower" => row.ci_lower, "ci_upper" => row.ci_upper) for row in tidy_table.rows],
            "categories" => result.categories,
            "reference" => result.reference,
            "warnings" => [Dict("code" => String(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint, "severity" => lowercase(String(Symbol(w.severity)))) for w in glance_table.warnings],
            "summary_text" => "model=multinomial_logit, nobs=$(glance_table.nobs), categories=$(length(result.categories))",
            "loglikelihood" => result.loglikelihood, "aic" => glance_table.metrics[:aic], "bic" => glance_table.metrics[:bic],
            "iterations" => result.iterations, "converged" => result.converged,
        ),
        "artifacts" => [],
    )

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = min(100, at.nobs)
        payload["result_payload"]["augment_preview"] = Dict(String(k) => v[1:max_preview] for (k, v) in at.columns)
    end

    return payload
end

result_to_payload(err::MetricaBase.ModelError) = Dict(
    "status" => "error",
    "messages" => [Dict("level" => "error", "code" => String(err.code), "text" => err.detail, "hint" => err.hint)],
)
