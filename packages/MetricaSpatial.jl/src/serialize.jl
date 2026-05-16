# === JSON 载荷 ================================================================

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

function _diag_to_dict(d::Dict{Symbol, Any})
    out = Dict{String, Any}()
    for (k, v) in d
        if v isa Symbol
            out[String(k)] = String(v)
        elseif v === nothing
            out[String(k)] = nothing
        elseif v isa Dict
            out[String(k)] = _diag_to_dict(v)
        else
            out[String(k)] = v
        end
    end
    return out
end

function result_to_payload(result::SpatialFitResult; include_augment::Bool = true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)
    warnings = [warning_to_dict(w) for w in glance_table.warnings]

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    tidy_rows = [
        let se = r.stderror
            se2 = se === nothing || (se isa Float64 && isnan(se)) ? nothing : se
            Dict(
                "name" => String(r.name),
                "estimate" => r.estimate,
                "stderror" => se2,
                "statistic" => r.statistic,
                "pvalue" => r.pvalue,
                "ci_lower" => r.ci_lower,
                "ci_upper" => r.ci_upper,
            )
        end
        for r in tidy_table.rows
    ]

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
            "tidy" => tidy_rows,
            "warnings" => warnings,
            "summary_text" => summary_text,
            "loglikelihood" => result.loglik,
            "aic" => nothing,
            "bic" => nothing,
            "diagnostics" => _diag_to_dict(result.diagnostics),
        ),
    )

    if include_augment
        aug = Dict{String, Vector{Float64}}(
            "fitted" => result.fitted,
            "residual" => result.residual,
        )
        payload["result_payload"]["augment"] = aug
    end

    return payload
end
