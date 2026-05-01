# === 一阶差分估计器 ===========================================================

"""
    fit_fd(panel_data::MetricaBase.PanelData, formula::String)

使用一阶差分方法拟合面板模型。

核心算法：
1. 按个体分组
2. 计算相邻期差值
3. 对差值数据执行 OLS
4. 修正自由度

返回 `PanelFitResult`。
"""
function fit_fd(panel_data::MetricaBase.PanelData, formula::String)
    data = panel_data.data
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    # 提取变量
    df = DataFrame(data)
    nobs_original = nrow(df)

    # 获取唯一个体和时期
    unique_ids = unique(df[!, id_col])
    n_ids = length(unique_ids)

    # 解析公式，提取响应变量和解释变量
    parts = split(formula, "~")
    response_name = strip(parts[1])
    predictor_names = [strip(x) for x in split(parts[2], "+")]

    # 提取数据列
    y = Float64.(df[!, Symbol(response_name)])
    X_names = [Symbol(name) for name in predictor_names]
    X = hcat([Float64.(df[!, name]) for name in X_names]...)

    # 按个体分组并计算差值
    y_diff = Float64[]
    X_diff = Matrix{Float64}(undef, 0, length(X_names))
    id_diff = Any[]
    time_diff = Any[]

    for id in unique_ids
        mask = df[!, id_col] .== id
        y_id = y[mask]
        X_id = X[mask, :]
        times = df[mask, time_col]

        # 按时间排序
        sort_idx = sortperm(times)
        y_id = y_id[sort_idx]
        X_id = X_id[sort_idx, :]
        times = times[sort_idx]

        # 计算差值
        for i in 2:length(y_id)
            push!(y_diff, y_id[i] - y_id[i-1])
            X_diff = vcat(X_diff, (X_id[i, :] - X_id[i-1, :])')
            push!(id_diff, id)
            push!(time_diff, times[i])
        end
    end

    nobs = length(y_diff)

    # 设计矩阵（差分后无截距）
    X_design = X_diff
    coef_names = X_names

    # OLS 拟合
    coefficients = X_design \ y_diff
    fitted = X_design * coefficients
    residuals = y_diff - fitted

    # 计算统计量
    dof_residual = nobs - size(X_design, 2)
    rss = sum(abs2, residuals)
    tss = sum(abs2, y_diff .- mean(y_diff))
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
        :fd,
        nobs,
        dof_residual,
        Dict(
            :r2 => r2,
            :adj_r2 => adj_r2,
            :sigma => sigma,
            :rss => rss,
            :tss => tss,
            :n_ids => n_ids,
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
        :fd,
    )
end
