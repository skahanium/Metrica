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

    residual_dof = nobs - length(coefficient_names) - (n_ids - 1)
    stats = ols_statistics(X_demeaned_noint, y_demeaned, coefficient_names, :fe,
                           Dict(:n_ids => n_ids, :n_times => n_times);
                           residual_dof=residual_dof)

    # 重建原始尺度拟合值（用无截距的 demeaned X + within-beta）
    fitted_original = y_means .+ X_demeaned_noint * stats.coefficients
    residuals_original = y - fitted_original

    # === Task 11: within/between/overall R² ====================================
    rss = sum(abs2, residuals_original)
    tss = sum(abs2, y .- mean(y))

    # 组内 TSS
    y_within = zeros(nobs)
    for id in unique_ids
        mask = filtered_df[!, id_col] .== id
        y_within[mask] = y[mask] .- mean(y[mask])
    end
    tss_within = sum(abs2, y_within)
    r2_within = tss_within > 0 ? 1.0 - rss / tss_within : 0.0

    # 组间 R²
    y_means_vec = zeros(n_ids)
    fitted_means_vec = zeros(n_ids)
    for (idx, id) in enumerate(unique_ids)
        mask = filtered_df[!, id_col] .== id
        y_means_vec[idx] = mean(y[mask])
        fitted_means_vec[idx] = mean(fitted_original[mask])
    end
    tss_between = sum(abs2, y_means_vec .- mean(y_means_vec))
    rss_between = sum(abs2, y_means_vec .- fitted_means_vec)
    r2_between = tss_between > 0 ? 1.0 - rss_between / tss_between : 0.0

    # 整体 R²
    r2_overall = tss > 0 ? 1.0 - rss / tss : 0.0

    merge!(stats.glance_table.metrics, Dict{Symbol, MetricaBase.MetricValue}(
        :r2_within => r2_within,
        :r2_between => r2_between,
        :r2_overall => r2_overall,
    ))

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
