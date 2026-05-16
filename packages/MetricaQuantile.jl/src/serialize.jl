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

function _diagnostics_to_jsonable(d::Dict{Symbol, Any})
    out = Dict{String, Any}()
    for (k, v) in pairs(d)
        out[String(k)] = v isa Symbol ? String(v) : v
    end
    return out
end

function result_to_payload(result::QuantileFitResult; include_augment::Bool = true)
    glance_table = result.glance_table
    tidy_table = result.tidy_table
    warnings = [_warning_to_dict(w) for w in glance_table.warnings]

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    diag = copy(result.diagnostics)

    payload = Dict(
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
            "vcov_label" => tidy_table.vcov_label,
            "tidy" => [
                Dict(
                    "name" => String(row.name),
                    "estimate" => row.estimate,
                    "stderror" => row.stderror === nothing ? nothing : row.stderror,
                    "statistic" => row.statistic === nothing ? nothing : row.statistic,
                    "pvalue" => row.pvalue === nothing ? nothing : row.pvalue,
                    "ci_lower" => row.ci_lower === nothing ? nothing : row.ci_lower,
                    "ci_upper" => row.ci_upper === nothing ? nothing : row.ci_upper,
                )
                for row in tidy_table.rows
            ],
            "warnings" => warnings,
            "summary_text" => summary_text,
            "diagnostics" => _diagnostics_to_jsonable(diag),
        ),
        "artifacts" => Any[],
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
