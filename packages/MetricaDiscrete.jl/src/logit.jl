# === Logit 模型 ==============================================================

function MetricaBase.fit(
    ::Type{LogitModel}, formula::AbstractString, data;
    vcov::Symbol=:classical, cluster_column::Union{Nothing,Symbol,String}=nothing,
)
    dataset = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    err = MetricaLinear.validate_model_columns(dataset, model_columns, nothing, cluster_column)
    err isa MetricaBase.ModelError && return err

    prepared = MetricaLinear.prepare_model_data(
        dataset, model_formula, model_columns, nothing,
        isnothing(cluster_column) ? nothing : Symbol(cluster_column),
    )
    prepared isa MetricaBase.ModelError && return prepared

    (_, model_frame, _, X, y, _, cluster_values, n_total, n_effective) = prepared
    nobs = length(y)
    ncoef = size(X, 2)

    unique_y = unique(y)
    if !all(in([0.0, 1.0]), unique_y)
        return MetricaBase.ModelError(
            :invalid_binary_response,
            "响应变量不是二值变量",
            "Logit 模型要求响应变量为 0/1 二值变量。当前数据包含值：$(unique_y)。",
            "请检查响应变量是否为 0/1 编码。",
        )
    end

    err = MetricaLinear.validate_design(X, ncoef, nobs)
    err isa MetricaBase.ModelError && return err

    irls_result = irls(X, y, LOGIT_LINK)
    irls_result isa MetricaBase.ModelError && return irls_result

    coefficients = irls_result.coefficients
    vcov_matrix = irls_result.vcov
    dof = nobs - ncoef
    # 稳健 / 聚类标准误
    if vcov == :classical
        # 默认 IRLS 方差，无需调整
    elseif vcov == :HC1
        residuals = y - irls_result.fitted_values
        XtX_inv = vcov_matrix
        meat = X' * (X .* residuals.^2)
        sandwich = XtX_inv * meat * XtX_inv
        vcov_matrix = (nobs / dof) * sandwich
    elseif vcov == :cluster && !isnothing(cluster_column)
        residuals = y - irls_result.fitted_values
        XtX_inv = vcov_matrix
        unique_clusters = unique(cluster_values)
        G = length(unique_clusters)
        meat = zeros(ncoef, ncoef)
        for g in unique_clusters
            idx = cluster_values .== g
            Xg = X[idx, :]
            eg = residuals[idx]
            meat += (Xg' * eg) * (eg' * Xg)
        end
        vcov_matrix = XtX_inv * meat * XtX_inv * (G / (G - 1)) * ((nobs - 1) / (nobs - ncoef))
    else
        return MetricaBase.ModelError(
            :unsupported_vcov,
            "协方差类型暂不支持",
            "离散模型当前仅支持 classical、HC1 与 cluster。",
            "请使用 :classical、:HC1 或 :cluster。",
        )
    end
    se_values = sqrt.(max.(diag(vcov_matrix), 0.0))
    coefficient_names = Symbol.(StatsModels.coefnames(model_frame))

    z_stats = coefficients ./ se_values
    pvalues = 2 .* (1 .- cdf.(Normal(), abs.(z_stats)))

    null_loglik = null_loglikelihood_bernoulli(y)
    loglik = irls_result.loglikelihood
    pseudo_r2 = 1 - (-loglik) / (-null_loglik)
    aic = 2 * ncoef - 2 * loglik
    bic = ncoef * log(nobs) - 2 * loglik

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, MetricaLinear.build_rows_dropped_warning(dropped_rows))

    if !irls_result.converged
        push!(warnings, MetricaBase.ModelWarning(
            :irls_not_converged, "IRLS 未收敛",
            "IRLS 迭代在最大次数内未收敛，结果可能不可靠。",
            "请检查数据中是否存在完全分离。",
            MetricaBase.warning,
        ))
    end

    if any(abs.(z_stats) .> 50)
        push!(warnings, MetricaBase.ModelWarning(
            :possible_separation, "可能存在完全分离",
            "部分系数的 z 统计量极大，可能存在完全分离或 quasi-complete separation。",
            "请检查预测变量是否完美预测响应变量。",
            MetricaBase.warning,
        ))
    end

    glance_table = MetricaBase.ModelGlance(
        :logit, nobs, dof,
        Dict{Symbol, MetricaBase.MetricValue}(
            :pseudo_r2 => pseudo_r2, :loglik => loglik,
            :aic => aic, :bic => bic, :deviance => irls_result.deviance,
        ),
        warnings,
    )

    tidy_rows = [
        MetricaBase.CoefRow(
            coefficient_names[i], coefficients[i],
            se_values[i], z_stats[i], pvalues[i],
        )
        for i in eachindex(coefficients)
    ]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "MLE")

    return LogitFitResult(
        String(formula), glance_table, tidy_table,
        Matrix{Float64}(X), y,
        irls_result.fitted_values, irls_result.linear_predictor,
        coefficient_names, coefficients,
        vcov_matrix, se_values,
        irls_result.deviance, loglik, irls_result.iterations, irls_result.converged,
    )
end

# === 协议方法 ==============================================================

MetricaBase.glance(result::LogitFitResult) = result.glance_table
MetricaBase.tidy(result::LogitFitResult) = result.tidy_table
MetricaBase.coef(result::LogitFitResult) = result.coefficient_names .=> result.coefficient_values
MetricaBase.vcov(result::LogitFitResult) = result.vcov_matrix
MetricaBase.stderror(result::LogitFitResult) = result.stderror_values
MetricaBase.nobs(result::LogitFitResult) = length(result.response_vector)
MetricaBase.dof(result::LogitFitResult) = length(result.response_vector) - length(result.coefficient_names)
MetricaBase.r2(result::LogitFitResult) = result.glance_table.metrics[:pseudo_r2]
MetricaBase.fitted(result::LogitFitResult) = result.fitted_values
MetricaBase.residuals(result::LogitFitResult) = result.response_vector - result.fitted_values

function MetricaBase.augment(result::LogitFitResult)
    n = length(result.response_vector)
    residuals = result.response_vector - result.fitted_values
    pearson_residuals = residuals ./ sqrt.(result.fitted_values .* (1.0 .- result.fitted_values) .+ 1e-10)
    return MetricaBase.AugmentTable(
        Dict(
            :observation => collect(1.0:n),
            :fitted => result.fitted_values,
            :residual => residuals,
            :pearson_residual => pearson_residuals,
        ),
        n,
    )
end

function MetricaBase.predict(result::LogitFitResult;
                              newdata::Union{Nothing,Matrix{Float64}}=nothing,
                              interval::Symbol=:none, level::Float64=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    η = X * result.coefficient_values
    prob = 1.0 ./ (1.0 .+ exp.(-η))
    if interval === :none
        return prob
    end
    se_eta = [sqrt(X[i, :]' * result.vcov_matrix * X[i, :]) for i in 1:size(X, 1)]
    z_crit = quantile(Normal(), 1 - (1 - level) / 2)
    return (
        predictions=prob,
        lower=1.0 ./ (1.0 .+ exp.(-(η .- z_crit .* se_eta))),
        upper=1.0 ./ (1.0 .+ exp.(-(η .+ z_crit .* se_eta))),
    )
end
