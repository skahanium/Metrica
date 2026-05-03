# === 一阶差分估计器 ===========================================================

"""
    fit_fd(panel_data::MetricaBase.PanelData, formula::String)

使用一阶差分方法拟合面板模型。

核心算法：
1. 按个体分组
2. 计算相邻期差值
3. 对差值数据执行 OLS
4. 修正自由度

返回 `PanelFitResult`。注：fitted_values 与 residual_vector 为差分空间中的值，
即 fitted + residual = Δy。
"""
function fit_fd(panel_data::MetricaBase.PanelData, formula::String)
    data = panel_data.data
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    df = DataFrame(data)
    nobs_original = nrow(df)

    unique_ids = unique(df[!, id_col])
    n_ids = length(unique_ids)

    # 解析公式
    response_name, predictor_names = MetricaBase.parse_metrica_formula(formula)

    y = Float64.(df[!, Symbol(response_name)])
    X_names = [Symbol(name) for name in predictor_names]
    X = hcat([Float64.(df[!, name]) for name in X_names]...)

    # 按个体分组并计算差值
    y_diff = Float64[]
    X_diff = Matrix{Float64}(undef, 0, length(X_names))

    for id in unique_ids
        mask = df[!, id_col] .== id
        y_id = y[mask]
        X_id = X[mask, :]
        times = df[mask, time_col]

        sort_idx = sortperm(times)
        y_id = y_id[sort_idx]
        X_id = X_id[sort_idx, :]

        for i in 2:length(y_id)
            push!(y_diff, y_id[i] - y_id[i-1])
            X_diff = vcat(X_diff, (X_id[i, :] - X_id[i-1, :])')
        end
    end

    # 差分后无截距
    X_design = X_diff
    coef_names = X_names

    stats = ols_statistics(X_design, y_diff, coef_names, :fd,
                           Dict(:n_ids => n_ids, :nobs_original => nobs_original))

    return PanelFitResult(
        formula,
        stats.glance_table,
        stats.tidy_table,
        panel_data,
        stats.fitted,
        stats.residuals,
        coef_names,
        :fd,
    )
end
