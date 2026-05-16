# === 面板结果序列化（复用 MetricaBase 共享序列化辅助）==========================

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

function result_to_payload(result::PanelFitResult; include_augment::Bool=true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)

    glance_dict, warnings = build_glance_envelope(glance_table)
    tidy_rows = build_tidy_rows(tidy_table)
    messages = build_messages(glance_table)
    caps_dict = try_capabilities(result)
    aug_status = build_augment_status(
        result;
        available=include_augment,
        columns_available=include_augment ? ["fitted", "residual", "std_residual"] : String[],
        columns_unavailable=["leverage", "cooks_d"],
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
            "model_capabilities" => caps_dict,
            "augment_status" => aug_status,
        ),
    )

    if include_augment
        at = MetricaBase.augment(result)
        payload["result_payload"]["augment_preview"] = build_augment_preview(at)
    end

    return payload
end

function result_to_payload(result::PanelIVFitResult; include_augment::Bool=true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)

    glance_dict, warnings = build_glance_envelope(glance_table)
    tidy_rows = build_tidy_rows(tidy_table)
    messages = build_messages(glance_table)
    caps_dict = try_capabilities(result)
    first_stage = Dict{String, Any}(String(k) => v for (k, v) in result.first_stage_stats)
    weak_warnings = [warning_to_dict(w) for w in result.weak_instrument_warnings]
    aug_status = build_augment_status(
        result;
        available=include_augment,
        columns_available=include_augment ? ["fitted", "residual"] : String[],
        columns_unavailable=["leverage", "cooks_d"],
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
            "first_stage_stats" => first_stage,
            "weak_instrument_warnings" => weak_warnings,
            "warnings" => warnings,
            "model_capabilities" => caps_dict,
            "augment_status" => aug_status,
        ),
    )

    if include_augment
        at = MetricaBase.augment(result)
        payload["result_payload"]["augment_preview"] = build_augment_preview(at)
    end

    return payload
end

function result_to_payload(result::DynamicPanelGMMFitResult; include_augment::Bool = true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)

    glance_dict, warnings = build_glance_envelope(glance_table)
    tidy_rows = build_tidy_rows(tidy_table)
    messages = build_messages(glance_table)
    caps_dict = try_capabilities(result)

    diagnostics_block = dict_symbol_to_string(result.diagnostics)
    for (k, v) in result.gmm_diagnostics
        diagnostics_block[String(k)] = v isa Symbol ? String(v) : v
    end

    aug_status = build_augment_status(
        result;
        available=include_augment,
        columns_available=include_augment ? ["fitted", "residual", "std_residual"] : String[],
        columns_unavailable=["leverage", "cooks_d"],
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
            "diagnostics" => diagnostics_block,
            "warnings" => warnings,
            "model_capabilities" => caps_dict,
            "augment_status" => aug_status,
        ),
    )

    if include_augment
        at = MetricaBase.augment(result)
        payload["result_payload"]["augment_preview"] = build_augment_preview(at)
    end

    return payload
end
