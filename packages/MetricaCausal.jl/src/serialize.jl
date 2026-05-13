# === 序列化 ==================================================================

function result_to_payload(result::DIDFitResult; include_augment::Bool=true)
    payload = Dict(
        "status" => "success",
        "messages" => [],
        "result_payload" => Dict(
            "glance" => Dict(
                "model" => "did",
                "nobs" => result.glance_table.nobs,
                "dof" => result.glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in result.glance_table.metrics),
            ),
            "tidy" => [Dict(
                "term" => String(r.name), "estimate" => r.estimate,
                "std_error" => r.stderror, "statistic" => r.statistic, "p_value" => r.pvalue,
                "ci_lower" => r.ci_lower, "ci_upper" => r.ci_upper,
            ) for r in result.tidy_table.rows],
            "treat_effect" => result.treat_effect,
            "treat_effect_se" => result.treat_effect_se,
            "treat_effect_pvalue" => result.treat_effect_pvalue,
            "n_treated" => result.n_treated,
            "n_control" => result.n_control,
            "n_pre" => result.n_pre,
            "n_post" => result.n_post,
            "warnings" => [Dict("code" => String(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint) for w in result.glance_table.warnings],
            "summary_text" => "DID 处理效应=$(round(result.treat_effect, digits=4)), p=$(round(result.treat_effect_pvalue, digits=4))",
        ),
        "artifacts" => [],
    )
    return payload
end

function result_to_payload(result::EventStudyFitResult; include_augment::Bool=true)
    payload = Dict(
        "status" => "success",
        "messages" => [],
        "result_payload" => Dict(
            "glance" => Dict(
                "model" => "event_study",
                "nobs" => result.glance_table.nobs,
                "dof" => result.glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in result.glance_table.metrics),
            ),
            "tidy" => [Dict(
                "term" => String(r.name), "estimate" => r.estimate,
                "std_error" => r.stderror, "statistic" => r.statistic, "p_value" => r.pvalue,
                "ci_lower" => r.ci_lower, "ci_upper" => r.ci_upper,
            ) for r in result.tidy_table.rows],
            "period_coefficients" => result.period_coefficients,
            "period_stderrors" => result.period_stderrors,
            "period_labels" => result.period_labels,
            "pre_trend_pvalue" => result.pre_trend_pvalue,
            "parallel_trends_supported" => result.parallel_trends_supported,
            "warnings" => [Dict("code" => String(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint) for w in result.glance_table.warnings],
            "summary_text" => "事件研究，平行趋势 p=$(round(result.pre_trend_pvalue, digits=4))",
        ),
        "artifacts" => [],
    )
    return payload
end

# 占位分派（IPW/PSM/AIPW 的序列化在 Phase 4-5 实现）
function result_to_payload(result::IPWFitResult; include_augment::Bool=true)
    n = length(result.weights)
    z_crit = quantile(Normal(), 0.975)
    return Dict("status" => "success", "messages" => [], "result_payload" => Dict(
        "glance" => Dict("model" => "ipw", "nobs" => n, "dof" => n-1, "metrics" => Dict(
            "ate" => result.ate, "att" => result.att, "atu" => result.atu,
        )),
        "ate" => result.ate, "ate_se" => result.ate_se,
        "att" => result.att, "att_se" => result.att_se,
        "tidy" => [Dict("term" => "ATE", "estimate" => result.ate, "std_error" => result.ate_se,
            "statistic" => result.ate/result.ate_se, "p_value" => 2*(1-cdf(Normal(), abs(result.ate/result.ate_se))),
            "ci_lower" => result.ate - z_crit * result.ate_se, "ci_upper" => result.ate + z_crit * result.ate_se)],
        "summary_text" => "IPW ATE=$(round(result.ate, digits=4))",
    ), "artifacts" => [])
end

function result_to_payload(result::PSMFitResult; include_augment::Bool=true)
    balance_rows = [Dict(
        "variable" => row[:variable], "mean_treated" => get(row, :mean_treated, NaN),
        "mean_control" => get(row, :mean_control, NaN), "std_bias" => get(row, :std_bias, NaN),
    ) for row in eachrow(result.balance_table)]
    z_crit = quantile(Normal(), 0.975)
    return Dict("status" => "success", "messages" => [], "result_payload" => Dict(
        "glance" => Dict("model" => "psm", "nobs" => result.n_matched*2, "dof" => result.n_matched-1,
            "metrics" => Dict("att" => result.att)),
        "att" => result.att, "att_se" => result.att_se,
        "n_matched" => result.n_matched,
        "tidy" => [Dict("term" => "ATT", "estimate" => result.att, "std_error" => result.att_se,
            "statistic" => result.att/result.att_se, "p_value" => 2*(1-cdf(Normal(), abs(result.att/result.att_se))),
            "ci_lower" => result.att - z_crit * result.att_se, "ci_upper" => result.att + z_crit * result.att_se)],
        "balance_table" => balance_rows,
        "summary_text" => "PSM ATT=$(round(result.att, digits=4))",
    ), "artifacts" => [])
end

function result_to_payload(result::AIPWFitResult; include_augment::Bool=true)
    z_crit = quantile(Normal(), 0.975)
    return Dict("status" => "success", "messages" => [], "result_payload" => Dict(
        "glance" => Dict("model" => "aipw", "nobs" => result.glance_table.nobs, "dof" => result.glance_table.dof,
            "metrics" => Dict("ate" => result.ate, "att" => result.att)),
        "ate" => result.ate, "ate_se" => result.ate_se,
        "att" => result.att, "att_se" => result.att_se,
        "tidy" => [Dict("term" => "ATE", "estimate" => result.ate, "std_error" => result.ate_se,
            "statistic" => result.ate/result.ate_se, "p_value" => 2*(1-cdf(Normal(), abs(result.ate/result.ate_se))),
            "ci_lower" => result.ate - z_crit * result.ate_se, "ci_upper" => result.ate + z_crit * result.ate_se)],
        "summary_text" => "AIPW ATE=$(round(result.ate, digits=4))",
    ), "artifacts" => [])
end

result_to_payload(err::MetricaBase.ModelError) = Dict(
    "status" => "error",
    "messages" => [Dict("level" => "error", "code" => String(err.code), "text" => err.detail, "hint" => err.hint)],
)
