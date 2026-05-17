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
    try_capabilities

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

function _hazard_ratio_rows(beta::Vector{Float64}, se::Vector{Float64}, names::Vector{Symbol})
    zcrit = 1.9599639845400536
    out = Dict{String, Any}[]
    for i in eachindex(names)
        b = beta[i]
        s = se[i]
        hr = exp(b)
        if s > 0 && isfinite(s)
            lo = exp(b - zcrit * s)
            hi = exp(b + zcrit * s)
        else
            lo = nothing
            hi = nothing
        end
        push!(
            out,
            Dict{String, Any}(
                "term" => String(names[i]),
                "hr" => hr,
                "ci_lower" => lo,
                "ci_upper" => hi,
            ),
        )
    end
    return out
end

function result_to_payload(result::CoxFitResult; include_augment::Bool = true)
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
        available=false,
        columns_available=String[],
        columns_unavailable=["martingale", "deviance", "score", "schoenfeld"],
        preview_included=false,
        preview_rows=0,
    )
    hr_rows = _hazard_ratio_rows(result.beta, result.se, result.coef_names)

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
            "aic" => get(result.diagnostics, :aic, nothing),
            "bic" => get(result.diagnostics, :bic, nothing),
            "diagnostics" => _diag_to_dict(result.diagnostics),
            "cluster_se" => get(result.diagnostics, :cluster_se, nothing),
            "hazard_ratios" => hr_rows,
            "model_capabilities" => caps_dict,
            "augment_status" => aug_status,
        ),
    )

    return payload
end

result_to_payload(err::MetricaBase.ModelError; include_augment::Bool=true) = error_to_payload(err)
