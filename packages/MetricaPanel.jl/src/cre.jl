# === CRE/Mundlak 估计器 =======================================================
# 统一使用 StatsModels 公式

function fit_crea(panel_data::MetricaBase.PanelData, formula::String)
    data = DataFrame(panel_data.data)
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    # StatsModels 公式解析
    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula
    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    prepared = MetricaLinear.prepare_model_data(data, model_formula, model_columns, nothing, nothing)
    prepared isa MetricaBase.ModelError && return prepared
    (filtered_df, model_frame, _, X, y, _, _, _, _) = prepared

    # 移除截距列
    X_noint = X[:, 2:end]
    nobs = length(y)
    unique_ids = unique(filtered_df[!, id_col])
    n_ids = length(unique_ids)
    base_names = Symbol.(coefnames(model_frame))[2:end]

    # 组均值
    X_group_mean = zeros(nobs, size(X_noint, 2))
    for id in unique_ids
        mask = filtered_df[!, id_col] .== id
        X_id = X_noint[mask, :]
        gm = vec(mean(X_id, dims=1))
        for j in 1:size(X_noint, 2)
            X_group_mean[mask, j] .= gm[j]
        end
    end

    X_design = hcat(ones(nobs), X_noint, X_group_mean)
    gm_names = [Symbol("group_mean_$(name)") for name in base_names]
    coef_names = vcat([:intercept], base_names, gm_names)

    stats = ols_statistics(X_design, y, coef_names, :cre,
                           Dict(:n_ids => n_ids, :n_times => length(unique(filtered_df[!, time_col]))))

    fitted = X_design * stats.coefficients
    residuals = y - fitted

    return PanelFitResult(formula, stats.glance_table, stats.tidy_table,
                          panel_data, fitted, residuals, coef_names, :cre)
end
