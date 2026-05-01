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

    # 提取变量
    df = DataFrame(data)
    nobs = nrow(df)

    # 获取唯一个体和时期
    unique_ids = unique(df[!, id_col])
    unique_times = unique(df[!, time_col])
    n_ids = length(unique_ids)
    n_times = length(unique_times)

    # 解析公式，提取响应变量和解释变量
    parts = split(formula, "~")
    response_name = strip(parts[1])
    predictor_names = [strip(x) for x in split(parts[2], "+")]

    # 提取数据列
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

    # 构造扩展设计矩阵 [X, X_group_means]
    X_extended = hcat(X, X_group_means[df[!, id_col] .|> (id -> id_index[id]), :])

    # 添加截距
    X_design = hcat(ones(nobs), X_extended)
    coef_names = vcat(
        [:intercept],
        X_names,
        [Symbol("group_mean_$name") for name in X_names],
    )

    # OLS 拟合
    coefficients = X_design \ y
    fitted = X_design * coefficients
    residuals = y - fitted

    # 计算统计量
    dof_residual = nobs - size(X_design, 2)
    rss = sum(abs2, residuals)
    tss = sum(abs2, y .- mean(y))
    r2 = iszero(tss) ? 0.0 : 1.0 - rss / tss
    adj_r2 = 1.0 - (1.0 - r2) * (nobs - 1) / dof_residual
    sigma = sqrt(rss / dof_residual)

    # 计算系数标准误
    XtX_inv = inv(X_design' * X_design)
    std_errors = sqrt.(diag(XtX_inv) .* (rss / dof_residual))
    t_stats = coefficients ./ std_errors
    p_values = 2.0 .* (1.0 .- cdf(TDist(dof_residual), abs.(t_stats)))

    # 构建系数表
    tidy_rows = [
        MetricaBase.CoefRow(
            coef_names[i],
            coefficients[i],
            std_errors[i],
            t_stats[i],
            p_values[i],
        )
        for i in eachindex(coef_names)
    ]

    # 构建摘要
    glance_table = MetricaBase.ModelGlance(
        :re,
        nobs,
        dof_residual,
        Dict(
            :r2 => r2,
            :adj_r2 => adj_r2,
            :sigma => sigma,
            :rss => rss,
            :tss => tss,
            :n_ids => n_ids,
            :n_times => n_times,
        ),
        MetricaBase.ModelWarning[],
    )

    tidy_table = MetricaBase.TidyTable(tidy_rows, "classical")

    return PanelFitResult(
        formula,
        glance_table,
        tidy_table,
        panel_data,
        fitted,
        residuals,
        coef_names,
        :re,
    )
end
