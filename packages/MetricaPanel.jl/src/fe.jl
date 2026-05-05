# === 固定效应估计器 ===========================================================
# 实现组内去均值算法（Within Transformation），统一使用 StatsModels 公式

function fit_fe(panel_data::MetricaBase.PanelData, formula::String)
    data = panel_data.data
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    df = DataFrame(data)

    # 用 StatsModels 解析公式（与 MetricaLinear/Discrete 统一）
    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula
    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    # 用共享数据管道准备设计矩阵
    prepared = MetricaLinear.prepare_model_data(df, model_formula, model_columns, nothing, nothing)
    prepared isa MetricaBase.ModelError && return prepared
    (filtered_df, model_frame, _, X, y, _, _, n_total, n_effective) = prepared

    nobs = length(y)
    unique_ids = unique(filtered_df[!, id_col])
    unique_times = unique(filtered_df[!, time_col])
    n_ids = length(unique_ids)
    n_times = length(unique_times)

    # 组内去均值
    y_demeaned = copy(y)
    X_demeaned = copy(X)
    y_means = zeros(nobs)

    for id in unique_ids
        mask = filtered_df[!, id_col] .== id
        y_id = y[mask]
        X_id = X[mask, :]

        y_mean = mean(y_id)
        X_means_vec = vec(mean(X_id, dims=1))

        y_demeaned[mask] = y_id .- y_mean
        y_means[mask] .= y_mean
        for j in 1:size(X, 2)
            X_demeaned[mask, j] = X_id[:, j] .- X_means_vec[j]
        end
    end

    # 移除 demean 后全零的截距列
    X_demeaned_noint = X_demeaned[:, 2:end]
    coefficient_names = Symbol.(coefnames(model_frame))[2:end]  # 去掉 intercept

    stats = ols_statistics(X_demeaned_noint, y_demeaned, coefficient_names, :fe,
                           Dict(:n_ids => n_ids, :n_times => n_times))

    # 重建原始尺度拟合值（用无截距的 demeaned X + within-beta）
    fitted_original = y_means .+ X_demeaned_noint * stats.coefficients
    residuals_original = y - fitted_original

    return PanelFitResult(
        formula,
        stats.glance_table,
        stats.tidy_table,
        panel_data,
        fitted_original,
        residuals_original,
        coefficient_names,
        :fe,
    )
end
