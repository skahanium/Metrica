# === 组间估计器 ===============================================================
# 统一使用 StatsModels 公式

function fit_between(panel_data::MetricaBase.PanelData, formula::String)
    data = panel_data.data
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    df = DataFrame(data)
    nobs_original = nrow(df)

    # StatsModels 公式解析
    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula
    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    prepared = MetricaLinear.prepare_model_data(df, model_formula, model_columns, nothing, nothing)
    prepared isa MetricaBase.ModelError && return prepared
    (filtered_df, model_frame, _, X, y, _, _, _, _) = prepared

    # 移除截距列，组均值估计自行添加
    X_noint = X[:, 2:end]
    unique_ids = unique(filtered_df[!, id_col])
    unique_times = unique(filtered_df[!, time_col])
    n_ids = length(unique_ids)
    n_times = length(unique_times)

    # 组均值
    y_means = zeros(n_ids)
    X_means = zeros(n_ids, size(X_noint, 2))

    for (idx, id) in enumerate(unique_ids)
        mask = filtered_df[!, id_col] .== id
        y_means[idx] = mean(y[mask])
        X_means[idx, :] = vec(mean(X_noint[mask, :], dims=1))
    end

    X_design = hcat(ones(n_ids), X_means)
    coef_names = vcat([:intercept], Symbol.(coefnames(model_frame))[2:end])

    stats = ols_statistics(X_design, y_means, coef_names, :between,
                           Dict(:n_ids => n_ids, :n_times => n_times, :nobs_original => nobs_original))

    return PanelFitResult(formula, stats.glance_table, stats.tidy_table,
                          panel_data, stats.fitted, stats.residuals, coef_names, :between)
end
