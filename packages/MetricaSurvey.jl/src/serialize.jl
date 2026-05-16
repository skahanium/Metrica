# === 序列化：result_to_payload ==================================================

function build_survey_payload(
    result::AbstractSurveyFitResult,
    model_label::AbstractString;
    include_augment::Bool=true,
)
    g = result.glance_table
    t = result.tidy_table

    messages = [Dict(
        "level" => lowercase(String(Symbol(w.severity))),
        "code" => String(w.code),
        "text" => w.detail,
        "hint" => w.hint,
    ) for w in g.warnings]

    de = design_effect(result)
    design_effects_payload = [
        Dict(
            "term" => de.coefficient[i],
            "deff" => de.deff[i],
            "n_eff" => de.n_eff[i],
            "srs_se" => de.srs_se[i],
            "survey_se" => de.survey_se[i],
        ) for i in eachindex(de.coefficient)
    ]

    result_dict = Dict{String, Any}(
        "glance" => Dict(
            "model" => model_label,
            "nobs" => g.nobs,
            "dof" => g.dof,
            "metrics" => Dict(String(k) => v for (k, v) in g.metrics),
        ),
        "tidy" => [Dict(
            "term" => String(row.name),
            "estimate" => row.estimate,
            "std_error" => row.stderror,
            "statistic" => row.statistic,
            "p_value" => row.pvalue,
            "ci_lower" => row.ci_lower,
            "ci_upper" => row.ci_upper,
        ) for row in t.rows],
        "design_effects" => design_effects_payload,
        "warnings" => [Dict(
            "code" => String(w.code), "title" => w.title, "detail" => w.detail,
            "hint" => w.hint, "severity" => lowercase(String(Symbol(w.severity))),
        ) for w in g.warnings],
        "summary_text" => "model=$model_label, nobs=$(g.nobs), mean_deff=$(round(get(g.metrics, :mean_deff, 1.0), digits=3))",
        "vcov_label" => "Taylor linearization (survey design)",
    )

    payload = Dict{String, Any}(
        "status" => "success",
        "messages" => messages,
        "result_payload" => result_dict,
        "artifacts" => [],
    )

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = min(100, MetricaBase.nobs(result))
        payload["result_payload"]["augment_preview"] = Dict(
            String(k) => v[1:max_preview] for (k, v) in at.columns
        )
    end

    return payload
end

# ---- 各类型 result_to_payload -------------------------------------------------

function result_to_payload(result::SurveyOLSFitResult; include_augment::Bool=true)
    return build_survey_payload(result, "survey_ols"; include_augment=include_augment)
end

function result_to_payload(result::SurveyLogitFitResult; include_augment::Bool=true)
    p = build_survey_payload(result, "survey_logit"; include_augment=include_augment)
    # 附加 OR
    ors = exp.(result.coefficient_values)
    se_log = result.survey_se
    p["result_payload"]["odds_ratios"] = [
        Dict(
            "term" => String(result.coefficient_names[i]),
            "odds_ratio" => ors[i],
            "ci_lower" => exp(result.coefficient_values[i] - 1.96 * se_log[i]),
            "ci_upper" => exp(result.coefficient_values[i] + 1.96 * se_log[i]),
        ) for i in eachindex(result.coefficient_names)
    ]
    # 附加离散模型诊断
    dr = result.discrete_result
    p["result_payload"]["loglikelihood"] = dr.loglikelihood
    p["result_payload"]["iterations"] = dr.iterations
    p["result_payload"]["converged"] = dr.converged
    return p
end

function result_to_payload(result::SurveyProbitFitResult; include_augment::Bool=true)
    p = build_survey_payload(result, "survey_probit"; include_augment=include_augment)
    dr = result.discrete_result
    p["result_payload"]["loglikelihood"] = dr.loglikelihood
    p["result_payload"]["iterations"] = dr.iterations
    p["result_payload"]["converged"] = dr.converged
    return p
end

function result_to_payload(result::SurveyPoissonFitResult; include_augment::Bool=true)
    p = build_survey_payload(result, "survey_poisson"; include_augment=include_augment)
    # 附加 IRR
    p["result_payload"]["incidence_rate_ratios"] = [
        Dict("term" => String(result.coefficient_names[i]), "irr" => exp(result.coefficient_values[i]))
        for i in eachindex(result.coefficient_names)
    ]
    dr = result.discrete_result
    p["result_payload"]["loglikelihood"] = dr.loglikelihood
    p["result_payload"]["iterations"] = dr.iterations
    p["result_payload"]["converged"] = dr.converged
    return p
end

# 错误载荷
result_to_payload(err::MetricaBase.ModelError) = Dict(
    "status" => "error",
    "messages" => [Dict(
        "level" => "error",
        "code" => String(err.code),
        "text" => err.detail,
        "hint" => err.hint,
    )],
)
