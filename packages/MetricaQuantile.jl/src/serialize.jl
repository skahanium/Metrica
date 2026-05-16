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
    build_augment_preview,
    try_capabilities

function result_to_payload(result::QuantileFitResult; include_augment::Bool = true)
    glance_table = result.glance_table
    tidy_table = result.tidy_table

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    glance_dict, warnings = build_glance_envelope(glance_table)
    tidy_rows = build_tidy_rows(tidy_table)
    messages = build_messages(glance_table)
    caps_dict = try_capabilities(result)
    diag = copy(result.diagnostics)
    aug_status = build_augment_status(
        result;
        available=include_augment,
        columns_available=include_augment ? ["fitted", "residual", "std_residual", "leverage", "cooks_d"] : String[],
        columns_unavailable=[],
        preview_included=include_augment,
        preview_rows=include_augment ? min(100, length(result.fitted_values)) : 0,
    )

    payload = Dict{String, Any}(
        "status" => "success",
        "messages" => messages,
        "result_payload" => Dict{String, Any}(
            "glance" => glance_dict,
            "vcov_label" => tidy_table.vcov_label,
            "tidy" => tidy_rows,
            "warnings" => warnings,
            "summary_text" => summary_text,
            "diagnostics" => dict_symbol_to_string(diag),
            "model_capabilities" => caps_dict,
            "augment_status" => aug_status,
        ),
        "artifacts" => Any[],
    )

    if include_augment
        at = MetricaBase.augment(result)
        payload["result_payload"]["augment_preview"] = build_augment_preview(at)
    end

    return payload
end
