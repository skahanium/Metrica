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

返回 `PanelFitResult`。
"""
function fit_fe(panel_data::MetricaBase.PanelData, formula::String)
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
    # 简化实现：假设公式格式为 "y ~ x1 + x2"
    parts = split(formula, "~")
    response_name = strip(parts[1])
    predictor_names = [strip(x) for x in split(parts[2], "+")]

    # 提取数据列
    y = Float64.(df[!, Symbol(response_name)])
    X_names = [Symbol(name) for name in predictor_names]
    X = hcat([Float64.(df[!, name]) for name in X_names]...)

    # 组内去均值
    y_demeaned = copy(y)
    X_demeaned = copy(X)

    for id in unique_ids
        mask = df[!, id_col] .== id
        y_id = y[mask]
        X_id = X[mask, :]

        # 计算组内均值
        y_mean = mean(y_id)
        X_means = vec(mean(X_id, dims=1))

        # 去均值
        y_demeaned[mask] = y_id .- y_mean
        for j in 1:size(X, 2)
            X_demeaned[mask, j] = X_id[:, j] .- X_means[j]
        end
    end

    # 添加截距（去均值后截距为 0，但为了兼容性仍添加）
    X_design = hcat(ones(nobs), X_demeaned)
    coef_names = vcat([:intercept], X_names)

    # OLS 拟合
    coefficients = X_design \ y_demeaned
    fitted = X_design * coefficients
    residuals = y_demeaned - fitted

    # 计算统计量
    dof_residual = nobs - size(X_design, 2)
    rss = sum(abs2, residuals)
    tss = sum(abs2, y_demeaned .- mean(y_demeaned))
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
        :fe,
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
        :fe,
    )
end
