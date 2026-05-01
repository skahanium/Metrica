# === 组间估计器 ===============================================================

"""
    fit_between(panel_data::MetricaBase.PanelData, formula::String)

使用组间估计方法拟合面板模型。

核心算法：
1. 按个体分组
2. 计算组均值
3. 对组均值数据执行 OLS
4. 修正标准误

返回 `PanelFitResult`。
"""
function fit_between(panel_data::MetricaBase.PanelData, formula::String)
    data = panel_data.data
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    # 提取变量
    df = DataFrame(data)
    nobs_original = nrow(df)

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

    # 按个体分组并计算组均值
    y_means = zeros(n_ids)
    X_means = zeros(n_ids, length(X_names))

    for (idx, id) in enumerate(unique_ids)
        mask = df[!, id_col] .== id
        y_means[idx] = mean(y[mask])
        X_means[idx, :] = vec(mean(X[mask, :], dims=1))
    end

    nobs = n_ids

    # 添加截距
    X_design = hcat(ones(nobs), X_means)
    coef_names = vcat([:intercept], X_names)

    # OLS 拟合
    coefficients = X_design \ y_means
    fitted = X_design * coefficients
    residuals = y_means - fitted

    # 计算统计量
    dof_residual = nobs - size(X_design, 2)
    rss = sum(abs2, residuals)
    tss = sum(abs2, y_means .- mean(y_means))
    r2 = iszero(tss) ? 0.0 : 1.0 - rss / tss
    adj_r2 = 1.0 - (1.0 - r2) * (nobs - 1) / max(dof_residual, 1)
    sigma = dof_residual > 0 ? sqrt(rss / dof_residual) : NaN

    # 计算系数标准误
    if dof_residual > 0
        XtX_inv = inv(X_design' * X_design)
        std_errors = sqrt.(diag(XtX_inv) .* (rss / dof_residual))
        t_stats = coefficients ./ std_errors
        p_values = 2.0 .* (1.0 .- cdf(TDist(dof_residual), abs.(t_stats)))
    else
        std_errors = fill(NaN, length(coefficients))
        t_stats = fill(NaN, length(coefficients))
        p_values = fill(NaN, length(coefficients))
    end

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
        :between,
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
            :nobs_original => nobs_original,
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
        :between,
    )
end
