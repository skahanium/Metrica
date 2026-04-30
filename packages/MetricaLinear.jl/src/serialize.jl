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

function result_to_payload(result::OLSFitResult)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)
    warnings = [warning_to_dict(warning) for warning in glance_table.warnings]

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    return Dict(
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
            "summary_text" => summary_text,
        ),
    )
end

result_to_payload(err::MetricaBase.ModelError) = error_to_payload(err)

function inspect_dataset(path::AbstractString)
    dataset = load_dataset(path)
    dataset isa MetricaBase.ModelError && return error_to_payload(dataset)

    return Dict(
        "status" => "success",
        "messages" => Any[],
        "result_payload" => Dict(
            "dataset_summary" => dataset_summary_dict(dataset),
            "columns" => columns_summary(dataset),
            "preview_rows" => preview_rows(dataset),
            "warnings" => Any[],
        ),
    )
end
