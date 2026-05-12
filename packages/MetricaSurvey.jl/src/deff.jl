# === 设计效应与分层摘要 =========================================================

function design_effect(result::AbstractSurveyFitResult)
    coef_str = String.(result.coefficient_names)
    srs_se = if result isa SurveyOLSFitResult
        MetricaBase.stderror(result.ols_result)
    else
        # discrete_result 是加权 IRLS 返回的命名元组
        sqrt.(max.(diag(result.discrete_result.vcov_matrix), 0.0))
    end
    return DEFFResult(
        coef_str,
        result.design_effects,
        result.effective_n,
        srs_se,
        result.survey_se,
    )
end

function strata_summary(design::SurveyDesign)
    data = design.data
    sc = design.strata_column

    if isnothing(sc)
        n_total = nrow(data)
        w = data[:, design.weights_column]
        return DataFrame(
            stratum = ["(全部观测)"],
            n = [n_total],
            sum_weights = [sum(w)],
            mean_weight = [mean(w)],
            min_weight = [minimum(w)],
            max_weight = [maximum(w)],
        )
    end

    strata_values = sort(unique(data[:, sc]))
    result = DataFrame(
        stratum = String[],
        n = Int[],
        sum_weights = Float64[],
        mean_weight = Float64[],
        min_weight = Float64[],
        max_weight = Float64[],
    )

    for s in strata_values
        in_s = data[:, sc] .== s
        n_s = sum(in_s)
        w_s = data[in_s, design.weights_column]

        push!(result, (
            stratum = string(s),
            n = n_s,
            sum_weights = sum(w_s),
            mean_weight = mean(w_s),
            min_weight = minimum(w_s),
            max_weight = maximum(w_s),
        ))
    end

    return result
end
