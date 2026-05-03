# === CRE/Mundlak 估计器 =======================================================
# Correlated Random Effects: 将组均值作为额外回归元

"""
    fit_crea(panel_data::PanelData, formula::String)

使用 Correlated Random Effects (CRE/Mundlak) 方法拟合面板模型。

将每个时变变量的组均值作为额外回归元加入 OLS，允许检验
E(u_i | X_i) 的函数形式。组均值系数标记为 `group_mean_*`。

返回 `PanelFitResult`（method = :cre）。
"""
function fit_crea(panel_data::MetricaBase.PanelData, formula::String)
    data = DataFrame(panel_data.data)
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    nobs = nrow(data)
    unique_ids = unique(data[!, id_col])
    n_ids = length(unique_ids)

    # 解析公式
    response_name, predictor_names = MetricaBase.parse_metrica_formula(formula)

    y = Float64.(data[!, Symbol(response_name)])
    X_names = [Symbol(name) for name in predictor_names]
    X = hcat([Float64.(data[!, name]) for name in X_names]...)

    # 计算组均值
    X_group_mean = zeros(nobs, length(X_names))
    for id in unique_ids
        mask = data[!, id_col] .== id
        X_id = X[mask, :]
        gm = vec(mean(X_id, dims=1))
        for j in 1:length(X_names)
            X_group_mean[mask, j] .= gm[j]
        end
    end

    # 构建设计矩阵：截距 + 原始变量 + 组均值变量
    X_design = hcat(ones(nobs), X, X_group_mean)
    gm_names = [Symbol("group_mean_$(name)") for name in X_names]
    coef_names = vcat([:intercept], X_names, gm_names)

    stats = ols_statistics(X_design, y, coef_names, :cre,
                           Dict(:n_ids => n_ids, :n_times => length(unique(data[!, time_col]))))

    fitted = X_design * stats.coefficients
    residuals = y - fitted

    return PanelFitResult(formula, stats.glance_table, stats.tidy_table,
                          panel_data, fitted, residuals, coef_names, :cre)
end
