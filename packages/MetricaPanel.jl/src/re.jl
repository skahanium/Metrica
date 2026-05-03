# === 随机效应估计器 ===========================================================
# 实现 Mundlak 方法

"""
    fit_re(panel_data::MetricaBase.PanelData, formula::String)

使用随机效应方法拟合面板模型。

Mundlak 方法：
1. 计算组均值
2. 将组均值作为额外回归元
3. 执行 OLS
4. 使用 GLS 修正标准误

返回 `PanelFitResult`。
"""
function fit_re(panel_data::MetricaBase.PanelData, formula::String)
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

    # 计算组均值
    X_group_means = zeros(n_ids, size(X, 2))
    y_group_means = zeros(n_ids)
    id_index = Dict(id => i for (i, id) in enumerate(unique_ids))

    for id in unique_ids
        idx = id_index[id]
        mask = df[!, id_col] .== id
        X_group_means[idx, :] = vec(mean(X[mask, :], dims=1))
        y_group_means[idx] = mean(y[mask])
    end

    # 构造扩展设计矩阵 [1, X, X_group_means]
    X_extended = hcat(X, X_group_means[df[!, id_col] .|> (id -> id_index[id]), :])
    X_design = hcat(ones(nobs), X_extended)
    coef_names = vcat(
        [:intercept],
        X_names,
        [Symbol("group_mean_$name") for name in X_names],
    )

    stats = ols_statistics(X_design, y, coef_names, :re,
                           Dict(:n_ids => n_ids, :n_times => n_times))

    return PanelFitResult(
        formula,
        stats.glance_table,
        stats.tidy_table,
        panel_data,
        stats.fitted,
        stats.residuals,
        coef_names,
        :re,
    )
end
