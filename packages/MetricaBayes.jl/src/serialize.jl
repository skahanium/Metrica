function result_to_payload(result::BayesFitResult; include_augment::Bool=true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)
    glance_dict, warnings = MetricaBase.build_glance_envelope(glance_table)
    tidy_rows = MetricaBase.build_tidy_rows(tidy_table)
    caps_dict = MetricaBase.try_capabilities(result)

    payload = Dict{String, Any}(
        "status" => "success",
        "messages" => [],
        "result_payload" => Dict{String, Any}(
            "glance" => glance_dict,
            "tidy" => tidy_rows,
            "warnings" => warnings,
            "diagnostics" => MetricaBase.dict_symbol_to_string(result.diagnostics),
            "log_marginal_likelihood" => result.log_marginal_likelihood,
            "log_marginal_likelihood_not_available_reason" => isnothing(result.log_marginal_likelihood) ? "σ² unknown; 解析边际似然不可得。" : nothing,
            "model_capabilities" => caps_dict,
        ),
    )
    return payload
end

result_to_payload(err::MetricaBase.ModelError; include_augment::Bool=true) = MetricaBase.error_to_payload(err)
error_to_payload(err::MetricaBase.ModelError) = MetricaBase.error_to_payload(err)
