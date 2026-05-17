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

# === GWR / GTWR / Probit 序列化 ===============================================

function result_to_payload(result::GWRFitResult; include_augment::Bool=true)
    preview_n = min(10, result.nobs)
    local_preview = [
        Dict{String, Any}(
            "obs" => i,
            [String(result.coef_names[j]) => result.local_coefficients[i, j] for j in 1:result.ncoef]...,
        )
        for i in 1:preview_n
    ]

    diag = dict_symbol_to_string(result.diagnostics)

    payload = Dict{String, Any}(
        "status" => "success",
        "messages" => [],
        "result_payload" => Dict{String, Any}(
            "glance" => Dict{String, Any}(
                "model" => "spatial_gwr",
                "nobs" => result.nobs,
                "ncoef" => result.ncoef,
                "bandwidth" => result.bandwidth,
                "kernel" => result.kernel,
                "aicc" => result.aicc,
            ),
            "local_coefficients_preview" => local_preview,
            "local_stderrors_preview" => result.local_stderrors !== nothing ?
                [result.local_stderrors[i, j] for i in 1:preview_n, j in 1:result.ncoef] : nothing,
            "local_tvalues_preview" => result.local_tvalues !== nothing ?
                [result.local_tvalues[i, j] for i in 1:preview_n, j in 1:result.ncoef] : nothing,
            "local_r2" => result.local_r2[1:preview_n],
            "bandwidth" => result.bandwidth,
            "bandwidth_selection" => result.bandwidth_selection,
            "bandwidth_score" => result.bandwidth_score,
            "kernel" => result.kernel,
            "adaptive" => result.adaptive,
            "effective_parameters" => result.effective_parameters,
            "aicc" => result.aicc,
            "diagnostics" => diag,
            "model_capabilities" => capabilities_to_dict(
                MetricaBase.ModelCapabilities(
                    :partial, :spatial, [:spatial_gwr],
                    ["local WLS (CV bandwidth)"],
                    [:bandwidth, :kernel, :aicc, :local_r2, :local_standard_errors, :local_tvalues],
                    [:golden_value_alignment],
                    Symbol[], true,
                    ["n ≤ 2000。"]))
        ),
    )

    if include_augment
        payload["result_payload"]["fitted"] = result.fitted[1:preview_n]
        payload["result_payload"]["residual"] = result.residual[1:preview_n]
    end

    return payload
end

function result_to_payload(result::GTWRFitResult; include_augment::Bool=true)
    payload = result_to_payload(GWRFitResult(
        result.formula, result.nobs, result.ncoef, result.coef_names,
        result.local_coefficients, result.local_stderrors, result.local_tvalues,
        result.local_r2, result.fitted, result.residual,
        result.bandwidth, result.bandwidth_selection, result.bandwidth_score,
        result.kernel, result.adaptive, result.distance_metric,
        result.effective_parameters, result.sigma2, result.aicc, result.hat_diag,
        result.diagnostics, result.warnings); include_augment=include_augment)
    payload["result_payload"]["glance"]["model"] = "spatial_gtwr"
    payload["result_payload"]["time_scale"] = result.time_scale
    payload["result_payload"]["time_column"] = result.time_column
    payload["result_payload"]["time_range"] = result.time_range
    payload["result_payload"]["spatiotemporal_distance_summary"] =
        Dict{String, Any}(String(k) => v for (k, v) in result.spatiotemporal_distance_summary)
    payload["result_payload"]["model_capabilities"] = capabilities_to_dict(
        MetricaBase.ModelCapabilities(
            :partial, :spatial, [:spatial_gwr, :spatial_gtwr],
            ["local WLS (时空核)"],
            [:bandwidth, :kernel, :aicc, :local_r2, :time_scale, :local_standard_errors, :local_tvalues],
            [:golden_value_alignment],
            Symbol[], true,
            ["GTWR 时空加权回归，支持欧氏/haversine 距离。"]))
    return payload
end

function result_to_payload(result::ProbitFitResult; include_augment::Bool=true)
    tidy_rows = [
        Dict{String, Any}(
            "name" => String(result.coef_names[i]),
            "estimate" => result.posterior_mean[i],
            "stderror" => result.posterior_sd[i],
            "statistic" => nothing,
            "pvalue" => nothing,
            "ci_lower" => result.credible_lower[i],
            "ci_upper" => result.credible_upper[i],
        )
        for i in 1:length(result.coef_names)
    ]

    payload = Dict{String, Any}(
        "status" => "success",
        "messages" => [],
        "result_payload" => Dict{String, Any}(
            "glance" => Dict{String, Any}(
                "model" => "spatial_probit",
                "nobs" => result.nobs,
                "ncoef" => result.ncoef,
                "inference_mode" => "mcmc",
            ),
            "tidy" => tidy_rows,
            "diagnostics" => dict_symbol_to_string(result.diagnostics),
            "rho_posterior_mean" => result.rho_mean,
            "rho_posterior_sd" => result.rho_sd,
            "rho_credible_lower" => result.rho_credible_lower,
            "rho_credible_upper" => result.rho_credible_upper,
            "model_capabilities" => capabilities_to_dict(
                MetricaBase.ModelCapabilities(
                    :partial, :spatial, [:spatial_probit],
                    ["Bayesian Gibbs (MCMC)"],
                    [:posterior_mean, :credible_interval, :rho_accept_rate],
                    [:rhat, :ess, :multi_chain, :golden_value_alignment],
                    Symbol[], false,
                    ["Gibbs 采样限 n ≤ 1000。", "多链和收敛诊断为二期功能。"]))
        ),
    )

    return payload
end
