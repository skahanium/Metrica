# === 随机效应估计器 ===========================================================
# Mundlak 方法，统一使用 StatsModels 公式

function fit_re(panel_data::MetricaBase.PanelData, formula::String)
    data = panel_data.data
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    df = DataFrame(data)

    # StatsModels 公式解析
    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula
    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    prepared = MetricaLinear.prepare_model_data(df, model_formula, model_columns, nothing, nothing)
    prepared isa MetricaBase.ModelError && return prepared
    (filtered_df, model_frame, _, X, y, _, _, _, _) = prepared

    # 移除 StatsModels 自动添加的截距列，Mundlak 方法自行处理
    X_noint = X[:, 2:end]
    base_names = Symbol.(coefnames(model_frame))[2:end]
    nobs = length(y)
    unique_ids = unique(filtered_df[!, id_col])
    unique_times = unique(filtered_df[!, time_col])
    n_ids = length(unique_ids)
    n_times = length(unique_times)

    # 组均值
    X_group_means = zeros(n_ids, size(X_noint, 2))
    y_group_means_vals = zeros(n_ids)
    id_index = Dict(id => i for (i, id) in enumerate(unique_ids))

    for id in unique_ids
        idx = id_index[id]
        mask = filtered_df[!, id_col] .== id
        X_group_means[idx, :] = vec(mean(X_noint[mask, :], dims=1))
        y_group_means_vals[idx] = mean(y[mask])
    end

    # [X_noint, X_group_means] 扩展设计矩阵
    X_extended = hcat(X_noint, X_group_means[filtered_df[!, id_col] .|> (id -> id_index[id]), :])
    X_design = hcat(ones(nobs), X_extended)
    coef_names = vcat([:intercept], base_names, [Symbol("group_mean_$(name)") for name in base_names])

    stats = ols_statistics(X_design, y, coef_names, :re,
                           Dict(:n_ids => n_ids, :n_times => n_times))

    return PanelFitResult(formula, stats.glance_table, stats.tidy_table,
                          panel_data, stats.fitted, stats.residuals, coef_names, :re)
end
