# === Runtime JSON 载荷（复用 MetricaBase 共享序列化辅助）========================

using MetricaBase: severity_to_string,
    warning_to_dict,
    error_to_payload,
    capabilities_to_dict,
    dict_symbol_to_string,
    build_glance_envelope,
    build_tidy_rows,
    build_messages,
    build_augment_status,
    try_capabilities

function _matrix_to_nested(m::AbstractMatrix{<:Real})
    return [collect(Float64.(m[i, :])) for i in 1:size(m, 1)]
end

function _diag_to_jsonable(d::Dict{Symbol, Any})
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

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    glance_dict, warnings = build_glance_envelope(glance_table)
    messages = build_messages(glance_table)
    caps_dict = try_capabilities(result)
    aug_status = build_augment_status(
        result;
        available=false,
        columns_available=String[],
        columns_unavailable=String[],
        preview_included=false,
        preview_rows=0,
    )

    # 系统模型需要方程级 tidy（含 equation 列）
    tidy_payload = [
        begin
            row = tidy_table.rows[i]
            Dict{String, Any}(
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

    # 方程级 glance
    equation_glances = [
        begin
            g = result.equation_glances[i]
            ew = [warning_to_dict(w) for w in g.warnings]
            Dict{String, Any}(
                "model" => String(g.model),
                "nobs" => g.nobs,
                "dof" => g.dof,
                "metrics" => Dict{String, Any}(String(k) => v for (k, v) in g.metrics),
                "warnings" => ew,
            )
        end
        for i in eachindex(result.equation_glances)
    ]

    return Dict{String, Any}(
        "status" => "success",
        "messages" => messages,
        "result_payload" => Dict{String, Any}(
            "glance" => glance_dict,
            "equation_glances" => equation_glances,
            "vcov_label" => tidy_table.vcov_label,
            "tidy" => tidy_payload,
            "warnings" => warnings,
            "summary_text" => summary_text,
            "diagnostics" => _diag_to_jsonable(result.diagnostics),
            "model_capabilities" => caps_dict,
            "augment_status" => aug_status,
        ),
    )
end
