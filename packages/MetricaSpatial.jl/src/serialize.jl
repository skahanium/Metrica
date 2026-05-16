# === JSON 载荷（复用 MetricaBase 共享序列化辅助）===============================

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

function result_to_payload(result::SpatialFitResult; include_augment::Bool = true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    glance_dict, warnings = build_glance_envelope(glance_table)
    tidy_rows = build_tidy_rows(tidy_table)
    messages = build_messages(glance_table)
    caps_dict = try_capabilities(result)
    aug_status = build_augment_status(
        result;
        available=true,
        columns_available=["fitted", "residual"],
        columns_unavailable=["std_residual", "leverage", "cooks_d"],
        preview_included=include_augment,
        preview_rows=include_augment ? length(result.fitted) : 0,
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
            "loglikelihood" => result.loglik,
            "aic" => nothing,
            "bic" => nothing,
            "diagnostics" => dict_symbol_to_string(result.diagnostics),
            "model_capabilities" => caps_dict,
            "augment_status" => aug_status,
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

result_to_payload(err::MetricaBase.ModelError; include_augment::Bool=true) = error_to_payload(err)
