# === 一阶差分估计器 ===========================================================
# 统一使用 StatsModels 公式

function fit_fd(panel_data::MetricaBase.PanelData, formula::String)
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

    # 移除截距列（差分后全为零）
    X_noint = X[:, 2:end]
    unique_ids = unique(filtered_df[!, id_col])
    n_ids = length(unique_ids)

    # 差分
    y_diff = Float64[]
    X_diff = Matrix{Float64}(undef, 0, size(X_noint, 2))

    for id in unique_ids
        mask = filtered_df[!, id_col] .== id
        y_id = y[mask]
        X_id = X_noint[mask, :]
        times = filtered_df[mask, time_col]

        sort_idx = sortperm(times)
        y_id = y_id[sort_idx]
        X_id = X_id[sort_idx, :]

        for i in 2:length(y_id)
            push!(y_diff, y_id[i] - y_id[i-1])
            X_diff = vcat(X_diff, (X_id[i, :] - X_id[i-1, :])')
        end
    end

    coef_names = Symbol.(coefnames(model_frame))[2:end]  # 无截距

    stats = ols_statistics(X_diff, y_diff, coef_names, :fd,
                           Dict(:n_ids => n_ids, :nobs_original => nobs_original))

    return PanelFitResult(formula, stats.glance_table, stats.tidy_table,
                          panel_data, stats.fitted, stats.residuals, coef_names, :fd)
end
