# === 固定效应估计器 ===========================================================
# 实现组内去均值算法（Within Transformation）

"""
    fit_fe(panel_data::MetricaBase.PanelData, formula::String)

使用固定效应方法拟合面板模型。

核心算法：
1. 按个体分组
2. 计算每个变量的组内均值
3. 用原始值减去组内均值
4. 对去均值后的数据执行 OLS
5. 用个体均值重建原始尺度的拟合值

返回 `PanelFitResult`。
"""
function fit_fe(panel_data::MetricaBase.PanelData, formula::String)
    data = panel_data.data
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    df = DataFrame(data)
    nobs = nrow(df)

    unique_ids = unique(df[!, id_col])
    unique_times = unique(df[!, time_col])
    n_ids = length(unique_ids)
    n_times = length(unique_times)

    # 解析公式
    response_name, predictor_names = MetricaBase.parse_metrica_formula(formula)

    y = Float64.(df[!, Symbol(response_name)])
    X_names = [Symbol(name) for name in predictor_names]
    X = hcat([Float64.(df[!, name]) for name in X_names]...)

    # 组内去均值，同时记录个体均值以用于重建原始尺度拟合值
    y_demeaned = copy(y)
    X_demeaned = copy(X)
    y_means = zeros(nobs)

    for id in unique_ids
        mask = df[!, id_col] .== id
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

    # 对去均值数据执行 OLS（添加截距，理论上应为零）
    X_design = hcat(ones(nobs), X_demeaned)
    coef_names = vcat([:intercept], X_names)

    stats = ols_statistics(X_design, y_demeaned, coef_names, :fe,
                           Dict(:n_ids => n_ids, :n_times => n_times))

    # 重建原始尺度的拟合值：ŷ_it = ȳ_i + X_demeaned_it * β_within
    k = length(X_names)
    within_beta = stats.coefficients[2:end]  # 排除截距
    fitted_original = y_means .+ X_demeaned * within_beta
    residuals_original = y - fitted_original

    return PanelFitResult(
        formula,
        stats.glance_table,
        stats.tidy_table,
        panel_data,
        fitted_original,
        residuals_original,
        coef_names,
        :fe,
    )
end
