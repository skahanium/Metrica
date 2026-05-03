# === 组间估计器 ===============================================================

"""
    fit_between(panel_data::MetricaBase.PanelData, formula::String)

使用组间估计方法拟合面板模型。

核心算法：
1. 按个体分组
2. 计算组均值
3. 对组均值数据执行 OLS
4. 修正标准误

返回 `PanelFitResult`。注：观测数为个体数，拟合值与残差基于组均值。
"""
function fit_between(panel_data::MetricaBase.PanelData, formula::String)
    data = panel_data.data
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    df = DataFrame(data)
    nobs_original = nrow(df)

    unique_ids = unique(df[!, id_col])
    unique_times = unique(df[!, time_col])
    n_ids = length(unique_ids)
    n_times = length(unique_times)

    # 解析公式
    response_name, predictor_names = MetricaBase.parse_metrica_formula(formula)

    y = Float64.(df[!, Symbol(response_name)])
    X_names = [Symbol(name) for name in predictor_names]
    X = hcat([Float64.(df[!, name]) for name in X_names]...)

    # 按个体分组并计算组均值
    y_means = zeros(n_ids)
    X_means = zeros(n_ids, length(X_names))

    for (idx, id) in enumerate(unique_ids)
        mask = df[!, id_col] .== id
        y_means[idx] = mean(y[mask])
        X_means[idx, :] = vec(mean(X[mask, :], dims=1))
    end

    # 对组均值执行 OLS
    X_design = hcat(ones(n_ids), X_means)
    coef_names = vcat([:intercept], X_names)

    stats = ols_statistics(X_design, y_means, coef_names, :between,
                           Dict(:n_ids => n_ids, :n_times => n_times,
                                :nobs_original => nobs_original))

    return PanelFitResult(
        formula,
        stats.glance_table,
        stats.tidy_table,
        panel_data,
        stats.fitted,
        stats.residuals,
        coef_names,
        :between,
    )
end
