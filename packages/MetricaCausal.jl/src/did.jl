# === DID 估计器 ==============================================================

function MetricaBase.fit(::Type{DIDModel}, formula::AbstractString, data;
                          panel_id::Symbol, panel_time::Symbol,
                          treated_column::Symbol, post_column::Symbol,
                          vcov::Symbol=:cluster, panel_method::Symbol=:fe,
                          fe_spec::Vector{Symbol}=Symbol[], weights=nothing)
    df = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    # StatsModels 公式展开
    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula
    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    # 确保 treated 和 post 在数据中
    if treated_column ∉ Symbol.(names(df))
        return MetricaBase.ModelError(:missing_treated_column, "处理变量不存在",
            "列 $treated_column 不在数据中。", "")
    end
    if post_column ∉ Symbol.(names(df))
        return MetricaBase.ModelError(:missing_post_column, "处理期变量不存在",
            "列 $post_column 不在数据中。", "")
    end

    # 添加交互列（若公式使用了 treat*post，StatsModels 会自动展开）
    df.treat_post = Float64.(df[!, treated_column] .* df[!, post_column])

    prepared = MetricaLinear.prepare_model_data(df, model_formula, model_columns, nothing, nothing)
    prepared isa MetricaBase.ModelError && return prepared
    (filtered_df, model_frame, _, X, y, _, _, _, _) = prepared

    # 移除截距再给 TWFE
    X_noint = X[:, 2:end]
    coef_names = Symbol.(coefnames(model_frame))[2:end]

    # TWFE（has_intercept=false 因为已手动移除）
    id_vec = filtered_df[!, panel_id]
    time_vec = filtered_df[!, panel_time]
    twfe_result = fit_twfe(X_noint, y, id_vec, time_vec, has_intercept=false)
    coefficients = twfe_result.coefficients
    vcov_matrix = twfe_result.vcov
    se_values = twfe_result.stderror
    dof = twfe_result.dof
    nobs = twfe_result.nobs

    # 个体聚类标准误（使用吸收后的设计矩阵和残差）
    if vcov == :cluster
        X_absorbed = twfe_result.X_demeaned
        residuals = twfe_result.residuals
        XtX_inv = twfe_result.XtX_inv
        unique_ids = unique(id_vec)
        G = length(unique_ids)
        ncoef_did = length(coefficients)
        meat = zeros(ncoef_did, ncoef_did)
        for g in unique_ids
            idx = id_vec .== g
            Xg = X_absorbed[idx, :]
            eg = residuals[idx]
            meat += (Xg' * eg) * (eg' * Xg)
        end
        vcov_matrix = XtX_inv * meat * XtX_inv * (G / (G - 1)) * ((nobs - 1) / (nobs - ncoef_did))
        se_values = sqrt.(max.(diag(vcov_matrix), 0.0))
    end

    # 提取处理效应（treat_post 交互项的系数）
    treat_idx = findfirst(==(:treat_post), coef_names)
    if isnothing(treat_idx)
        treat_idx = findfirst(n -> occursin("&", String(n)) || occursin("treat_post", String(n)), coef_names)
    end
    if isnothing(treat_idx)
        return MetricaBase.ModelError(:no_treat_interaction, "未找到处理交互项",
            "公式中需包含 treated 和 post 的交互项。建议使用 treat * post。", "")
    end

    treat_effect = coefficients[treat_idx]
    treat_se = se_values[treat_idx]
    treat_t = treat_effect / treat_se
    treat_pvalue = 2 * (1 - cdf(TDist(dof), abs(treat_t)))

    # 处理/对照组样本量
    n_treated = sum(filtered_df[!, treated_column] .> 0)
    n_control = nobs - n_treated
    unique_times = sort(unique(time_vec))
    treat_period = minimum(filtered_df[filtered_df[!, post_column] .> 0, panel_time])
    n_pre = sum(time_vec .< treat_period)
    n_post = sum(time_vec .>= treat_period)

    # parallel trends warning (if ≥ 3 pre periods, check pre-trends)
    warnings = MetricaBase.ModelWarning[]
    if n_pre >= 3 && length(unique_times[unique_times .< treat_period]) >= 3
        push!(warnings, MetricaBase.ModelWarning(:parallel_trends_unchecked,
            "平行趋势需检验", "面板有 ≥ 3 期预处理数据，建议使用事件研究检验平行趋势假设。",
            "可使用 EventStudyModel 进行平行趋势检验。",
            MetricaBase.info))
    end

    glance_table = MetricaBase.ModelGlance(:did, nobs, dof,
        Dict{Symbol, MetricaBase.MetricValue}(
            :treat_effect => treat_effect, :n_treated => n_treated, :n_control => n_control,
            :n_pre => n_pre, :n_post => n_post,
        ), warnings)

    tidy_rows = [let
        t_stat = se_values[i] > 1e-15 ? coefficients[i]/se_values[i] : 0.0
        p_val = t_stat != 0.0 ? 2*(1-cdf(TDist(max(dof,1)), abs(t_stat))) : 1.0
        MetricaBase.CoefRow(coef_names[i], coefficients[i], se_values[i], t_stat, p_val)
    end for i in 1:length(coef_names)]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "TWFE")

    return DIDFitResult(formula, glance_table, tidy_table,
        treat_effect, treat_se, treat_pvalue,
        n_treated, n_control, n_pre, n_post,
        coef_names, coefficients, vcov_matrix, -Inf)
end

# 协议方法
MetricaBase.glance(result::DIDFitResult) = result.glance_table
MetricaBase.tidy(result::DIDFitResult) = result.tidy_table
MetricaBase.coef(result::DIDFitResult) = result.coefficient_names .=> result.coefficient_values
MetricaBase.vcov(result::DIDFitResult) = result.vcov_matrix
MetricaBase.nobs(result::DIDFitResult) = result.glance_table.nobs
MetricaBase.dof(result::DIDFitResult) = result.glance_table.dof
MetricaBase.r2(result::DIDFitResult) = NaN  # DID uses within-R2
MetricaBase.stderror(result::DIDFitResult) = result.tidy_table.rows .|> r -> r.stderror |> Float64
