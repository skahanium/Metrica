# === 面板结果序列化 ===========================================================

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

function result_to_payload(result::PanelFitResult; include_augment::Bool=true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)
    warnings = [warning_to_dict(warning) for warning in glance_table.warnings]

    payload = Dict(
        "status" => "success",
        "messages" => [
            Dict(
                "level" => severity_to_string(warning.severity),
                "code" => String(warning.code),
                "text" => warning.detail,
                "hint" => warning.hint,
            )
            for warning in glance_table.warnings
        ],
        "result_payload" => Dict(
            "glance" => Dict(
                "model" => String(glance_table.model),
                "nobs" => glance_table.nobs,
                "dof" => glance_table.dof,
                "metrics" => Dict(String(key) => value for (key, value) in glance_table.metrics),
                "warnings" => warnings,
            ),
            "vcov_label" => tidy_table.vcov_label,
            "tidy" => [
                Dict(
                    "name" => String(row.name),
                    "estimate" => row.estimate,
                    "stderror" => row.stderror,
                    "statistic" => row.statistic,
                    "pvalue" => row.pvalue,
                )
                for row in tidy_table.rows
            ],
            "warnings" => warnings,
        ),
    )

    if include_augment
        augment_table = MetricaBase.augment(result)
        max_preview = min(100, augment_table.nobs)
        augment_preview = Dict(
            String(key) => values[1:max_preview]
            for (key, values) in augment_table.columns
        )
        payload["result_payload"]["augment_preview"] = augment_preview
    end

    return payload
end
