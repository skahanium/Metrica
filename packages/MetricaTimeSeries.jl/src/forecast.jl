# forecast.jl - 预测模块
# 实现 ARIMA/VAR 预测、ACF/PACF、Ljung-Box 检验

# === 预测结果类型 =========================================================

"""
    ForecastResult

预测结果。
"""
struct ForecastResult
    point_forecast::Vector{Float64}
    lower_bound::Vector{Float64}
    upper_bound::Vector{Float64}
    confidence_level::Float64
    forecast_origin::Int
    steps::Int
end

# === ARIMA 预测 ===========================================================

"""
    forecast(result::ARIMAFitResult; steps=10, level=0.95) -> ForecastResult

ARIMA 模型预测。

# 参数
- `result`: ARIMA 拟合结果
- `steps`: 预测步数
- `level`: 置信水平

# 返回
- `ForecastResult`: 预测结果
"""
function forecast(result::ARIMAFitResult; steps::Int=10, level::Float64=0.95)
    n = length(result.original_series)
    p, d, q = result.order

    # 获取差分序列
    if isnothing(result.differenced_series)
        y_diff = difference(result.original_series, d)
    else
        y_diff = result.differenced_series
    end
    n_diff = length(y_diff)

    # 获取 AR 系数
    ar_coeffs = Float64[]
    for i in 1:p
        key = Symbol("ar_L$i")
        push!(ar_coeffs, get(result.coefficients, key, 0.0))
    end

    # 获取 MA 系数
    ma_coeffs = Float64[]
    for i in 1:q
        key = Symbol("ma_L$i")
        push!(ma_coeffs, get(result.coefficients, key, 0.0))
    end

    # 获取常数项
    constant = get(result.coefficients, :constant, 0.0)

    # 预测
    point_forecast = zeros(steps)
    forecast_errors = zeros(steps)

    # 使用最后 p 个 AR 值和 q 个残差
    if p > 0
        last_ar = y_diff[end-p+1:end]
    else
        last_ar = Float64[]
    end

    if q > 0
        last_ma = result.residuals[end-q+1:end]
    else
        last_ma = Float64[]
    end

    for h in 1:steps
        # AR 部分
        ar_part = 0.0
        for i in 1:min(p, h)
            ar_part += ar_coeffs[i] * last_ar[end-i+1]
        end

        # MA 部分（未来冲击为 0）
        ma_part = 0.0
        for i in 1:min(q, h-1)
            ma_part += ma_coeffs[i] * last_ma[end-i+1]
        end

        # 预测值
        point_forecast[h] = constant + ar_part + ma_part

        # 更新 AR 历史
        if p > 0
            if h <= p
                last_ar = [last_ar; point_forecast[h]]
            else
                last_ar = [last_ar[2:end]; point_forecast[h]]
            end
        end

        # 预测误差方差（简化计算）
        forecast_errors[h] = sqrt(result.sigma2 * h)
    end

    # 如果有差分，需要积分回原始尺度
    if d > 0
        last_value = result.original_series[end]
        point_forecast = cumsum(point_forecast) .+ last_value
        forecast_errors = cumsum(forecast_errors)
    end

    # 置信区间
    z = quantile(Normal(0, 1), 1 - (1 - level) / 2)
    lower_bound = point_forecast .- z .* forecast_errors
    upper_bound = point_forecast .+ z .* forecast_errors

    return ForecastResult(
        point_forecast,
        lower_bound,
        upper_bound,
        level,
        n,
        steps
    )
end

# === VAR 预测 ==============================================================

"""
    forecast(result::VARFitResult; steps=10, level=0.95) -> Dict{String, ForecastResult}

VAR 模型预测。

# 参数
- `result`: VAR 拟合结果
- `steps`: 预测步数
- `level`: 置信水平

# 返回
- `Dict{String, ForecastResult}`: 各变量的预测结果
"""
function forecast(result::VARFitResult; steps::Int=10, level::Float64=0.95)
    n_vars = length(result.variable_names)
    lags = result.lags
    n = size(result.original_data, 1)
    has_const = size(result.coefficients, 1) > n_vars * lags

    # 获取脉冲响应用于计算预测区间
    irf = impulse_response(result, periods=steps)

    # 所有变量的预测结果
    point_forecasts = zeros(steps, n_vars)
    forecast_errors = zeros(steps, n_vars)

    # 使用最后 lags 个观测值作为初始历史
    history = result.original_data[end-lags+1:end, :]

    # 逐步预测：每一步先预测所有变量，再统一更新历史
    for h in 1:steps
        for var_idx in 1:n_vars
            pred = 0.0

            # AR 部分
            for lag in 1:lags
                for j in 1:n_vars
                    row_idx = (lag - 1) * n_vars + j
                    pred += result.coefficients[row_idx, var_idx] * history[end-lag+1, j]
                end
            end

            # 常数项
            if has_const
                pred += result.coefficients[end, var_idx]
            end

            point_forecasts[h, var_idx] = pred

            # 预测误差方差（使用脉冲响应）
            for s in 1:h
                forecast_errors[h, var_idx] += sum(irf[s, var_idx, :] .^ 2)
            end
            forecast_errors[h, var_idx] = sqrt(forecast_errors[h, var_idx])
        end

        # 统一更新历史：将当前步的所有变量预测值加入历史
        if h < steps
            history = [history[2:end, :]; point_forecasts[h, :]']
        end
    end

    # 构建各变量的 ForecastResult
    forecasts = Dict{String, ForecastResult}()
    z = quantile(Normal(0, 1), 1 - (1 - level) / 2)

    for (var_idx, var_name) in enumerate(result.variable_names)
        pf = point_forecasts[:, var_idx]
        fe = forecast_errors[:, var_idx]
        forecasts[var_name] = ForecastResult(
            pf,
            pf .- z .* fe,
            pf .+ z .* fe,
            level,
            n,
            steps
        )
    end

    return forecasts
end

# === ACF ==================================================================

"""
    acf(y; max_lags=20) -> Vector{Float64}

计算自相关函数。

# 参数
- `y`: 时间序列
- `max_lags`: 最大滞后阶数

# 返回
- `acf_values`: ACF 值向量（索引 1 对应滞后 0）
"""
function acf(y::Vector{Float64}; max_lags::Int=20)
    n = length(y)
    mean_y = mean(y)
    gamma_0 = sum((y .- mean_y) .^ 2) / n

    acf_values = zeros(max_lags + 1)
    acf_values[1] = 1.0

    for k in 1:max_lags
        gamma_k = sum((y[k+1:end] .- mean_y) .* (y[1:end-k] .- mean_y)) / n
        acf_values[k+1] = gamma_k / gamma_0
    end

    return acf_values
end

# === PACF =================================================================

"""
    pacf(y; max_lags=20) -> Vector{Float64}

计算偏自相关函数。

# 参数
- `y`: 时间序列
- `max_lags`: 最大滞后阶数

# 返回
- `pacf_values`: PACF 值向量（索引 1 对应滞后 0）
"""
function pacf(y::Vector{Float64}; max_lags::Int=20)
    acf_values = acf(y, max_lags=max_lags)

    pacf_values = zeros(max_lags + 1)
    pacf_values[1] = 1.0

    # 使用 Durbin-Levinson 算法
    phi = zeros(max_lags, max_lags)
    v = zeros(max_lags + 1)
    v[1] = acf_values[1]

    for k in 1:max_lags
        # 计算 phi[k,k]
        num = acf_values[k+1]
        for j in 1:k-1
            num -= phi[k-1, j] * acf_values[k-j+1]
        end
        phi[k, k] = num / v[k]

        # 更新 phi
        for j in 1:k-1
            phi[k, j] = phi[k-1, j] - phi[k, k] * phi[k-1, k-j]
        end

        # 更新方差
        v[k+1] = v[k] * (1 - phi[k, k]^2)

        pacf_values[k+1] = phi[k, k]
    end

    return pacf_values
end

# === Ljung-Box 检验 ========================================================

"""
    ljung_box_test(y; lags=10) -> NamedTuple

Ljung-Box 自相关检验。

# 参数
- `y`: 时间序列（通常为残差）
- `lags`: 检验滞后阶数

# 返回
- `(test_statistic, p_value, conclusion)`
"""
function ljung_box_test(y::Vector{Float64}; lags::Int=10)
    n = length(y)
    acf_values = acf(y, max_lags=lags)

    # Ljung-Box 统计量
    Q = n * (n + 2) * sum(acf_values[2:lags+1] .^ 2 ./ (n .- (1:lags)))

    # p 值
    p_value = 1 - cdf(Chisq(lags), Q)

    conclusion = p_value < 0.05 ? "reject" : "fail_to_reject"

    return (test_statistic=Q, p_value=p_value, conclusion=conclusion)
end
