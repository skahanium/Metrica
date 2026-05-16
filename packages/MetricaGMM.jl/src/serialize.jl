# === Runtime / JSON 载荷 ======================================================

function severity_to_string(severity::MetricaBase.Severity)
    return String(Symbol(severity))
end

function warning_to_dict(warning::MetricaBase.ModelWarning)
    return Dict(
        "code" => String(warning.code),
        "title" => warning.title,
        "detail" => warning.detail,
        "hint" => warning.hint,
        "severity" => severity_to_string(warning.severity),
    )
end

function error_to_payload(err::MetricaBase.ModelError)
    return Dict(
        "status" => "error",
        "messages" => [
            Dict(
                "level" => "error",
                "code" => String(err.code),
                "text" => err.detail,
                "hint" => err.hint,
            ),
        ],
    )
end

function _gmm_diagnostics_to_dict(d::Dict{Symbol, Any})
    out = Dict{String, Any}()
    for (k, v) in d
        if v isa Symbol
            out[String(k)] = String(v)
        elseif isnothing(v)
            out[String(k)] = nothing
        else
            out[String(k)] = v
        end
    end
    return out
end

function _compute_loglikelihood(result::GMMLinearFitResult)
    n = length(result.response_vector)
    rss = sum(abs2, result.residual_vector)
    sigma2 = rss / n
    return -n / 2 * (log(2π) + log(sigma2) + 1)
end

function _compute_k(result::GMMLinearFitResult)
    return length(result.coefficient_names)
end

function _compute_aic(result::GMMLinearFitResult)
    k = _compute_k(result)
    ll = _compute_loglikelihood(result)
    return 2 * k - 2 * ll
end

function _compute_bic(result::GMMLinearFitResult)
    n = length(result.response_vector)
    k = _compute_k(result)
    ll = _compute_loglikelihood(result)
    return k * log(n) - 2 * ll
end

function result_to_payload(result::GMMLinearFitResult; include_augment::Bool = true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)
    warnings = [warning_to_dict(w) for w in glance_table.warnings]

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    payload = Dict(
        "status" => "success",
        "messages" => [
            Dict(
                "level" => severity_to_string(w.severity),
                "code" => String(w.code),
                "text" => w.detail,
                "hint" => w.hint,
            )
            for w in glance_table.warnings
        ],
        "result_payload" => Dict(
            "glance" => Dict(
                "model" => String(glance_table.model),
                "nobs" => glance_table.nobs,
                "dof" => glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in glance_table.metrics),
                "warnings" => warnings,
            ),
            "vcov_label" => tidy_table.vcov_label,
            "tidy" => [
                Dict(
                    "name" => String(r.name),
                    "estimate" => r.estimate,
                    "stderror" => r.stderror,
                    "statistic" => r.statistic,
                    "pvalue" => r.pvalue,
                    "ci_lower" => r.ci_lower,
                    "ci_upper" => r.ci_upper,
                )
                for r in tidy_table.rows
            ],
            "first_stage_stats" => Dict(String(k) => v for (k, v) in result.first_stage_stats),
            "warnings" => warnings,
            "summary_text" => summary_text,
            "loglikelihood" => _compute_loglikelihood(result),
            "aic" => _compute_aic(result),
            "bic" => _compute_bic(result),
            "diagnostics" => _gmm_diagnostics_to_dict(result.gmm_diagnostics),
        ),
    )

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = min(100, at.nobs)
        payload["result_payload"]["augment_preview"] = [
            Dict(String(k) => v[i] for (k, v) in at.columns)
            for i in 1:max_preview
        ]
    end

    return payload
end

result_to_payload(err::MetricaBase.ModelError; include_augment::Bool = true) = error_to_payload(err)
