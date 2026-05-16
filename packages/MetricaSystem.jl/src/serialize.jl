# === Runtime JSON 载荷 ========================================================

function _severity_to_string(severity::MetricaBase.Severity)
    return String(Symbol(severity))
end

function _warning_to_dict(warning::MetricaBase.ModelWarning)
    return Dict(
        "code" => String(warning.code),
        "title" => warning.title,
        "detail" => warning.detail,
        "hint" => warning.hint,
        "severity" => _severity_to_string(warning.severity),
    )
end

function _glance_to_dict(g::MetricaBase.ModelGlance)
    warnings = [_warning_to_dict(w) for w in g.warnings]
    return Dict(
        "model" => String(g.model),
        "nobs" => g.nobs,
        "dof" => g.dof,
        "metrics" => Dict(String(k) => v for (k, v) in g.metrics),
        "warnings" => warnings,
    )
end

function _matrix_to_nested(m::AbstractMatrix{<:Real})
    return [collect(Float64.(m[i, :])) for i in 1:size(m, 1)]
end

function _diagnostics_to_jsonable(d::Dict{Symbol, Any})
    out = Dict{String, Any}()
    for (k, v) in pairs(d)
        sk = String(k)
        if v isa AbstractMatrix{<:Real}
            out[sk] = Dict("dim" => size(v, 1), "matrix" => _matrix_to_nested(v))
        else
            out[sk] = v isa Symbol ? String(v) : v
        end
    end
    return out
end

function result_to_payload(result::SystemEquationsFitResult; include_augment::Bool = true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)
    warnings = [_warning_to_dict(w) for w in glance_table.warnings]

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    tidy_payload = [
        let row = tidy_table.rows[i]
            Dict(
                "equation" => result.tidy_equation_labels[i],
                "name" => String(row.name),
                "estimate" => row.estimate,
                "stderror" => row.stderror,
                "statistic" => row.statistic,
                "pvalue" => row.pvalue,
                "ci_lower" => row.ci_lower,
                "ci_upper" => row.ci_upper,
            )
        end
        for i in eachindex(tidy_table.rows)
    ]

    return Dict(
        "status" => "success",
        "messages" => [
            Dict(
                "level" => _severity_to_string(w.severity),
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
            "equation_glances" => [_glance_to_dict(g) for g in result.equation_glances],
            "vcov_label" => tidy_table.vcov_label,
            "tidy" => tidy_payload,
            "warnings" => warnings,
            "summary_text" => summary_text,
            "diagnostics" => _diagnostics_to_jsonable(result.diagnostics),
        ),
    )
end
