# === Runtime / JSON 载荷（复用 MetricaBase 共享序列化辅助）======================

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
        available=include_augment,
        columns_available=include_augment ? ["fitted", "residual", "std_residual", "leverage", "cooks_d"] : String[],
        columns_unavailable=String[],
        preview_included=include_augment,
        preview_rows=include_augment ? min(100, length(result.response_vector)) : 0,
    )

    payload = Dict{String, Any}(
        "status" => "success",
        "messages" => messages,
        "result_payload" => Dict{String, Any}(
            "glance" => glance_dict,
            "vcov_label" => tidy_table.vcov_label,
            "tidy" => tidy_rows,
            "first_stage_stats" => Dict{String, Any}(String(k) => v for (k, v) in result.first_stage_stats),
            "warnings" => warnings,
            "summary_text" => summary_text,
            "loglikelihood" => _compute_loglikelihood(result),
            "aic" => _compute_aic(result),
            "bic" => _compute_bic(result),
            "diagnostics" => _gmm_diagnostics_to_dict(result.gmm_diagnostics),
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

result_to_payload(err::MetricaBase.ModelError; include_augment::Bool = true) = error_to_payload(err)
