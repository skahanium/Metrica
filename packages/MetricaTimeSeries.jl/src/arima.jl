# arima.jl - ARIMA 模型模块
# 实现 ARMA/ARIMA 模型，使用 Optim.jl 进行数值优化

# === 类型定义 =============================================================

"""
    ARIMAModel <: AbstractTimeSeriesModel

ARIMA 模型规格。
"""
struct ARIMAModel <: AbstractTimeSeriesModel
    variable::Symbol
    time_column::Symbol
    order::Tuple{Int, Int, Int}  # (p, d, q)
    seasonal_order::Tuple{Int, Int, Int, Int}  # (P, D, Q, s)
    include_constant::Bool
    method::Symbol  # :mle (Kalman) 或 :css (条件平方和)
end

"""
    ARIMAFitResult <: AbstractTSFitResult

ARIMA 模型拟合结果。
"""
struct ARIMAFitResult <: AbstractTSFitResult
    variable_name::String
    order::Tuple{Int, Int, Int}
    seasonal_order::Tuple{Int, Int, Int, Int}
    coefficients::Dict{Symbol, Float64}
    std_errors::Dict{Symbol, Float64}
    sigma2::Float64
    loglik::Float64
    aic::Float64
    bic::Float64
    residuals::Vector{Float64}
    fitted_values::Vector{Float64}
    original_series::Vector{Float64}
    differenced_series::Union{Vector{Float64}, Nothing}
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    warnings::Vector{MetricaBase.ModelWarning}
end

"""
    ARIMAModel(; variable, time_column, order=(1,1,1), seasonal_order=(0,0,0,0), include_constant=true, method=:mle)

构造 ARIMA 模型规格。

# 参数
- `variable`: 目标变量列名
- `time_column`: 时间列名
- `order`: (p, d, q) 阶数
- `seasonal_order`: (P, D, Q, s) 季节性阶数
- `include_constant`: 是否包含常数项
- `method`: 估计方法 (:mle 或 :css)
"""
function ARIMAModel(; variable::Symbol, time_column::Symbol,
                    order::Tuple{Int,Int,Int}=(1,1,1),
                    seasonal_order::Tuple{Int,Int,Int,Int}=(0,0,0,0),
                    include_constant::Bool=true,
                    method::Symbol=:mle)
    return ARIMAModel(variable, time_column, order, seasonal_order, include_constant, method)
end

# === 拟合方法 =============================================================

"""
    fit(model::ARIMAModel, data::DataFrame) -> ARIMAFitResult

拟合 ARIMA 模型。
"""
function MetricaBase.fit(model::ARIMAModel, data::DataFrame)
    # 排序数据
    data_sorted = sort_by_time(data, model.time_column)

    # 提取序列
    y = Float64.(data_sorted[!, model.variable])
    n = length(y)

    # 验证阶数
    p, d, q = model.order
    P, D, Q, s = model.seasonal_order

    if p < 0 || d < 0 || q < 0
        error("ARIMA 阶数 (p, d, q) 必须非负")
    end
    if P < 0 || D < 0 || Q < 0 || s < 0
        error("季节性阶数 (P, D, Q, s) 必须非负")
    end
    if s > 0 && (P + D + Q == 0)
        error("季节性周期 s > 0 时，P + D + Q 必须 > 0")
    end

    # 选择估计方法
    if model.method === :mle
        try
            return fit_mle(model, y, n)
        catch e
            @warn "MLE 估计失败，尝试 CSS 方法: $e"
            return fit_css(model, y, n)
        end
    else
        return fit_css(model, y, n)
    end
end

"""
    fit_mle(model::ARIMAModel, y::Vector{Float64}, n::Int) -> ARIMAFitResult

使用条件 MLE（数值优化）拟合 ARIMA 模型。
基于条件对数似然函数，通过 Optim.jl 进行数值优化。
"""
function fit_mle(model::ARIMAModel, y::Vector{Float64}, n::Int)
    p, d, q = model.order

    # 差分
    y_diff = copy(y)
    for _ in 1:d
        y_diff = diff(y_diff)
    end
    n_diff = length(y_diff)

    include_const = model.include_constant
    n_ar = p
    n_ma = q
    n_params = n_ar + n_ma + (include_const ? 1 : 0) + 1  # +1 for sigma2

    if n_params <= 1
        # 纯白噪声
        residuals = y_diff
        sigma2 = sum(residuals .^ 2) / n_diff
        coefficients = Dict{Symbol, Float64}()
        std_errors = Dict{Symbol, Float64}()
        loglik = -n_diff / 2 * log(2π * sigma2) - n_diff / 2
        aic = -2 * loglik + 2
        bic = -2 * loglik + log(n_diff)
        warnings = MetricaBase.ModelWarning[]
        glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
            :nobs => n, :sigma2 => sigma2, :loglik => loglik,
            :aic => aic, :bic => bic, :p => p, :d => d, :q => q,
        )
        glance_table = MetricaBase.ModelGlance(
            Symbol("ARIMA($(p),$(d),$(q))"), n, 0, glance_metrics, MetricaBase.ModelWarning[]
        )
        tidy_table = MetricaBase.TidyTable(MetricaBase.CoefRow[], "std.error")
        return ARIMAFitResult(
            string(model.variable), model.order, model.seasonal_order,
            coefficients, std_errors, sigma2, loglik, aic, bic,
            residuals, zeros(n_diff), y, y_diff, glance_table, tidy_table, warnings
        )
    end

    # 条件对数似然函数
    function neg_loglik(theta)
        ar_coeffs = theta[1:n_ar]
        ma_coeffs = theta[n_ar+1:n_ar+n_ma]
        const_term = include_const ? theta[n_ar+n_ma+1] : 0.0
        sigma2 = exp(theta[end])  # 用 exp 保证正数
        sigma2 = max(sigma2, 1e-10)

        resid = zeros(n_diff)
        for t in 1:n_diff
            ar_part = 0.0
            for i in 1:n_ar
                if t > i
                    ar_part += ar_coeffs[i] * y_diff[t - i]
                end
            end
            ma_part = 0.0
            for j in 1:n_ma
                if t > j
                    ma_part += ma_coeffs[j] * resid[t - j]
                end
            end
            mu = const_term + ar_part + ma_part
            resid[t] = y_diff[t] - mu
        end

        # 条件对数似然（正态分布）
        ll = -n_diff / 2 * log(2π * sigma2) - sum(resid .^ 2) / (2 * sigma2)
        return -ll  # 返回负对数似然
    end

    # 初始值
    initial_theta = zeros(n_params)
    if n_ar > 0
        max_lag = max(p, q)
        if max_lag > 0 && n_diff > max_lag
            X_ar = zeros(n_diff - max_lag, p)
            for i in 1:p
                X_ar[:, i] = y_diff[max_lag+1-i:n_diff-i]
            end
            y_reg = y_diff[max_lag+1:end]
            initial_theta[1:n_ar] = X_ar \ y_reg
        else
            initial_theta[1:n_ar] .= 0.1
        end
    end
    if include_const
        initial_theta[n_ar+n_ma+1] = mean(y_diff)
    end
    initial_theta[end] = log(var(y_diff))  # log(sigma2)

    # 数值优化
    opt_result = Optim.optimize(
        neg_loglik,
        initial_theta,
        Optim.NelderMead(),
        Optim.Options(iterations=2000, g_tol=1e-10)
    )

    theta_hat = Optim.minimizer(opt_result)
    converged = Optim.converged(opt_result)

    # 提取参数
    ar_coeffs_hat = theta_hat[1:n_ar]
    ma_coeffs_hat = theta_hat[n_ar+1:n_ar+n_ma]
    const_hat = include_const ? theta_hat[n_ar+n_ma+1] : 0.0
    sigma2_hat = exp(theta_hat[end])

    # 计算最终残差
    residuals = zeros(n_diff)
    fitted = zeros(n_diff)
    for t in 1:n_diff
        ar_part = 0.0
        for i in 1:n_ar
            if t > i
                ar_part += ar_coeffs_hat[i] * y_diff[t - i]
            end
        end
        ma_part = 0.0
        for j in 1:n_ma
            if t > j
                ma_part += ma_coeffs_hat[j] * residuals[t - j]
            end
        end
        fitted[t] = const_hat + ar_part + ma_part
        residuals[t] = y_diff[t] - fitted[t]
    end

    # 构建系数字典
    coefficients = Dict{Symbol, Float64}()
    std_errors = Dict{Symbol, Float64}()
    for i in 1:n_ar
        coefficients[Symbol("ar_L$i")] = ar_coeffs_hat[i]
    end
    for j in 1:n_ma
        coefficients[Symbol("ma_L$j")] = ma_coeffs_hat[j]
    end
    if include_const
        coefficients[:constant] = const_hat
    end

    # 用数值 Hessian 计算标准误
    ϵ = 1e-5
    H_fd = zeros(n_params, n_params)
    f0 = neg_loglik(theta_hat)
    for i in 1:n_params
        for j in i:n_params
            θ_ij = copy(theta_hat); θ_ij[i] += ϵ; θ_ij[j] += ϵ
            θ_i = copy(theta_hat); θ_i[i] += ϵ
            θ_j = copy(theta_hat); θ_j[j] += ϵ
            f_ij = neg_loglik(θ_ij)
            f_i = neg_loglik(θ_i)
            f_j = neg_loglik(θ_j)
            H_fd[i, j] = (f_ij - f_i - f_j + f0) / (ϵ * ϵ)
            H_fd[j, i] = H_fd[i, j]
        end
    end
    H_fd = (H_fd + H_fd') ./ 2

    hessian_ok = false
    if all(isfinite, H_fd) && isposdef(H_fd)
        vcov_matrix = inv(H_fd)
        ses = sqrt.(max.(diag(vcov_matrix), 0.0))
        idx = 1
        for i in 1:n_ar
            std_errors[Symbol("ar_L$i")] = ses[idx]; idx += 1
        end
        for j in 1:n_ma
            std_errors[Symbol("ma_L$j")] = ses[idx]; idx += 1
        end
        if include_const
            std_errors[:constant] = ses[idx]; idx += 1
        end
        hessian_ok = true
    end

    if !hessian_ok
        for (k, _) in coefficients
            std_errors[k] = 0.0
        end
    end

    # 信息准则
    loglik = -n_diff / 2 * log(2π * sigma2_hat) - sum(residuals .^ 2) / (2 * sigma2_hat)
    k = n_params
    aic = -2 * loglik + 2 * k
    bic = -2 * loglik + k * log(n_diff)

    # Ljung-Box 检验
    lb_lags = min(20, n_diff ÷ 5)
    lb_lags = max(lb_lags, 1)
    lb = ljung_box_test(residuals, lags=lb_lags)

    # 警告
    warnings = MetricaBase.ModelWarning[]
    if !converged
        push!(warnings, MetricaBase.ModelWarning(
            :mle_not_converged, "MLE 优化未收敛",
            "数值优化在最大迭代次数内未收敛",
            "考虑使用 CSS 方法或检查数据", MetricaBase.warning
        ))
    end
    if !hessian_ok
        push!(warnings, MetricaBase.ModelWarning(
            :mle_se_unavailable, "无法计算 MLE 标准误",
            "Hessian 矩阵不可逆，标准误已设为 0",
            "考虑使用 CSS 方法", MetricaBase.warning
        ))
    end

    # 构建 glance 表（含 Ljung-Box）
    P, D, Q, s = model.seasonal_order
    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :nobs => n, :sigma2 => sigma2_hat, :loglik => loglik,
        :aic => aic, :bic => bic, :p => p, :d => d, :q => q,
        :P => P, :D => D, :Q => Q, :s => s,
        :ljung_box_Q => lb.test_statistic, :ljung_box_p => lb.p_value,
    )
    model_label = Symbol("ARIMA($(p),$(d),$(q))" * (s > 0 ? "×($(P),$(D),$(Q),$(s))" : ""))
    glance_table = MetricaBase.ModelGlance(model_label, n, 0, glance_metrics, warnings)

    # 构建 tidy 表（含 95% 置信区间）
    z_95 = 1.96
    coef_rows = MetricaBase.CoefRow[]
    for (name, value) in coefficients
        se = get(std_errors, name, 0.0)
        t_stat = se > 0 ? value / se : 0.0
        p_value = 2 * (1 - cdf(Normal(0, 1), abs(t_stat)))
        ci_l = se > 0 ? value - z_95 * se : nothing
        ci_u = se > 0 ? value + z_95 * se : nothing
        push!(coef_rows, MetricaBase.CoefRow(name, value, se, t_stat, p_value, ci_l, ci_u))
    end
    tidy_table = MetricaBase.TidyTable(coef_rows, "std.error")

    return ARIMAFitResult(
        string(model.variable), model.order, model.seasonal_order,
        coefficients, std_errors, sigma2_hat, loglik, aic, bic,
        residuals, fitted, y, y_diff, glance_table, tidy_table, warnings
    )
end

"""
    fit_css(model::ARIMAModel, y::Vector{Float64}, n::Int) -> ARIMAFitResult

使用条件平方和（CSS）方法拟合 ARIMA 模型。
通过数值优化（Optim）联合估计 AR 和 MA 参数。
"""
function fit_css(model::ARIMAModel, y::Vector{Float64}, n::Int)
    p, d, q = model.order

    # 差分
    y_diff = copy(y)
    for _ in 1:d
        y_diff = diff(y_diff)
    end
    n_diff = length(y_diff)

    include_const = model.include_constant
    n_ar = p
    n_ma = q
    n_params = n_ar + n_ma + (include_const ? 1 : 0)

    if n_params == 0
        # 纯白噪声：无参数
        residuals = y_diff
        fitted = zeros(n_diff)
        sigma2 = sum(residuals .^ 2) / n_diff
        coefficients = Dict{Symbol, Float64}()
        std_errors = Dict{Symbol, Float64}()
        warnings = MetricaBase.ModelWarning[]
    else
        # CSS 目标函数：给定参数向量 θ，计算条件残差平方和
        function css_objective(theta)
            ar_coeffs = theta[1:n_ar]
            ma_coeffs = theta[n_ar+1:n_ar+n_ma]
            const_term = include_const ? theta[end] : 0.0

            n_eff = n_diff
            resid = zeros(n_eff)
            fitted_vec = zeros(n_eff)

            for t in 1:n_eff
                # AR 部分
                ar_part = 0.0
                for i in 1:n_ar
                    if t > i
                        ar_part += ar_coeffs[i] * y_diff[t - i]
                    end
                end

                # MA 部分
                ma_part = 0.0
                for j in 1:n_ma
                    if t > j
                        ma_part += ma_coeffs[j] * resid[t - j]
                    end
                end

                fitted_vec[t] = const_term + ar_part + ma_part
                resid[t] = y_diff[t] - fitted_vec[t]
            end

            return sum(resid .^ 2)
        end

        # 初始值：AR 部分用 OLS 初值，MA 部分从 0 开始
        initial_theta = zeros(n_params)
        if n_ar > 0
            max_lag = max(p, q)
            if max_lag > 0 && n_diff > max_lag
                X_ar = zeros(n_diff - max_lag, p)
                for i in 1:p
                    X_ar[:, i] = y_diff[max_lag+1-i:n_diff-i]
                end
                y_reg = y_diff[max_lag+1:end]
                initial_theta[1:n_ar] = X_ar \ y_reg
            else
                initial_theta[1:n_ar] .= 0.1
            end
        end
        if n_ma > 0
            initial_theta[n_ar+1:n_ar+n_ma] .= 0.0
        end
        if include_const
            initial_theta[end] = mean(y_diff)
        end

        # 数值优化
        opt_result = Optim.optimize(
            css_objective,
            initial_theta,
            Optim.NelderMead(),
            Optim.Options(iterations=1000, g_tol=1e-8)
        )

        theta_hat = Optim.minimizer(opt_result)
        converged = Optim.converged(opt_result)

        # 提取参数
        ar_coeffs = theta_hat[1:n_ar]
        ma_coeffs = theta_hat[n_ar+1:n_ar+n_ma]
        const_term = include_const ? theta_hat[end] : 0.0

        # 计算最终残差
        residuals = zeros(n_diff)
        fitted = zeros(n_diff)
        for t in 1:n_diff
            ar_part = 0.0
            for i in 1:n_ar
                if t > i
                    ar_part += ar_coeffs[i] * y_diff[t - i]
                end
            end
            ma_part = 0.0
            for j in 1:n_ma
                if t > j
                    ma_part += ma_coeffs[j] * residuals[t - j]
                end
            end
            fitted[t] = const_term + ar_part + ma_part
            residuals[t] = y_diff[t] - fitted[t]
        end

        sigma2 = sum(residuals .^ 2) / max(n_diff - n_params, 1)

        # 尝试从 Hessian 获取标准误
        coefficients = Dict{Symbol, Float64}()
        std_errors = Dict{Symbol, Float64}()

        for i in 1:n_ar
            coefficients[Symbol("ar_L$i")] = ar_coeffs[i]
            std_errors[Symbol("ar_L$i")] = 0.0
        end
        for j in 1:n_ma
            coefficients[Symbol("ma_L$j")] = ma_coeffs[j]
            std_errors[Symbol("ma_L$j")] = 0.0
        end
        if include_const
            coefficients[:constant] = const_term
            std_errors[:constant] = 0.0
        end

        # 尝试用 Hessian 计算标准误
        hessian_ok = false
        try
            H = Optim.hessian!(opt_result)
            if all(isfinite, H) && isposdef(H)
                vcov = inv(H) .* 2.0 .* sigma2
                ses = sqrt.(max.(diag(vcov), 0.0))
                idx = 1
                for i in 1:n_ar
                    std_errors[Symbol("ar_L$i")] = ses[idx]
                    idx += 1
                end
                for j in 1:n_ma
                    std_errors[Symbol("ma_L$j")] = ses[idx]
                    idx += 1
                end
                if include_const
                    std_errors[:constant] = ses[idx]
                end
                hessian_ok = true
            end
        catch
        end

        # 回退：有限差分数值 Hessian
        if !hessian_ok
            try
                θ_opt = Optim.minimizer(opt_result)
                ϵ = 1e-5
                n_params = length(θ_opt)
                H_fd = zeros(n_params, n_params)
                f0 = css_objective(θ_opt)
                for i in 1:n_params
                    for j in i:n_params
                        θ_ij = copy(θ_opt); θ_ij[i] += ϵ; θ_ij[j] += ϵ
                        θ_i = copy(θ_opt); θ_i[i] += ϵ
                        θ_j = copy(θ_opt); θ_j[j] += ϵ
                        f_ij = css_objective(θ_ij)
                        f_i = css_objective(θ_i)
                        f_j = css_objective(θ_j)
                        H_fd[i, j] = (f_ij - f_i - f_j + f0) / (ϵ * ϵ)
                        H_fd[j, i] = H_fd[i, j]
                    end
                end
                H_fd = (H_fd + H_fd') ./ 2
                if isposdef(H_fd)
                    vcov_fd = inv(H_fd) .* 2.0 .* sigma2
                    ses_fd = sqrt.(max.(diag(vcov_fd), 0.0))
                    idx = 1
                    for i in 1:n_ar
                        std_errors[Symbol("ar_L$i")] = ses_fd[idx]
                        idx += 1
                    end
                    for j in 1:n_ma
                        std_errors[Symbol("ma_L$j")] = ses_fd[idx]
                        idx += 1
                    end
                    if include_const
                        std_errors[:constant] = ses_fd[idx]
                    end
                    hessian_ok = true
                end
            catch
            end
        end

        warnings = MetricaBase.ModelWarning[]
        if !hessian_ok
            push!(warnings, MetricaBase.ModelWarning(
                :css_se_unavailable,
                "无法计算 CSS 标准误",
                "Hessian 矩阵不可逆或有限差分 Hessian 计算失败。标准误已设为 0。",
                "考虑使用 MLE 方法以获得可靠的标准误。",
                MetricaBase.warning,
            ))
        end
        if !converged
            push!(warnings, MetricaBase.ModelWarning(
                :css_not_converged,
                "CSS 优化未收敛",
                "数值优化在最大迭代次数内未收敛",
                "考虑增加 max_iter 或切换到 MLE 方法",
                MetricaBase.warning
            ))
        end
    end

    # 信息准则
    loglik = -n_diff / 2 * log(2π * sigma2) - sum(residuals .^ 2) / (2 * sigma2)
    k = n_params + 1
    aic = -2 * loglik + 2 * k
    bic = -2 * loglik + k * log(n_diff)

    # Ljung-Box 检验
    lb_lags = min(20, n_diff ÷ 5)
    lb_lags = max(lb_lags, 1)
    lb = ljung_box_test(residuals, lags=lb_lags)

    # 构建 glance 表
    P, D, Q, s = model.seasonal_order
    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :nobs => n,
        :sigma2 => sigma2,
        :loglik => loglik,
        :aic => aic,
        :bic => bic,
        :p => p,
        :d => d,
        :q => q,
        :ljung_box_Q => lb.test_statistic,
        :ljung_box_p => lb.p_value,
    )

    glance_table = MetricaBase.ModelGlance(
        Symbol("ARIMA($(p),$(d),$(q))"),
        n,
        0,
        glance_metrics,
        warnings
    )

    # 构建 tidy 表（含 95% 置信区间）
    z_95 = 1.96
    coef_rows = MetricaBase.CoefRow[]
    for (name, value) in coefficients
        se = get(std_errors, name, 0.0)
        t_stat = se > 0 ? value / se : 0.0
        p_value = 2 * (1 - cdf(Normal(0, 1), abs(t_stat)))
        ci_l = se > 0 ? value - z_95 * se : nothing
        ci_u = se > 0 ? value + z_95 * se : nothing
        push!(coef_rows, MetricaBase.CoefRow(name, value, se, t_stat, p_value, ci_l, ci_u))
    end

    tidy_table = MetricaBase.TidyTable(coef_rows, "std.error")

    return ARIMAFitResult(
        string(model.variable),
        model.order,
        model.seasonal_order,
        coefficients,
        std_errors,
        sigma2,
        loglik,
        aic,
        bic,
        residuals,
        fitted,
        y,
        y_diff,
        glance_table,
        tidy_table,
        warnings
    )
end

# === 协议方法 =============================================================

function MetricaBase.glance(result::ARIMAFitResult)
    return result.glance_table
end

function MetricaBase.tidy(result::ARIMAFitResult)
    return result.tidy_table
end

function MetricaBase.augment(result::ARIMAFitResult)
    n = length(result.original_series)
    n_resid = length(result.residuals)

    sigma = sqrt(result.sigma2)
    std_residuals = sigma > 0 ? result.residuals ./ sigma : zeros(n_resid)

    obs = collect(1.0:n)
    fitted = zeros(n)
    resid = zeros(n)
    std_resid = zeros(n)

    start_idx = n - n_resid + 1
    fitted[start_idx:end] = result.fitted_values
    resid[start_idx:end] = result.residuals
    std_resid[start_idx:end] = std_residuals

    return MetricaBase.AugmentTable(
        Dict(
            :observation => obs,
            :fitted => fitted,
            :residual => resid,
            :std_residual => std_resid,
        ),
        n
    )
end

function MetricaBase.coef(result::ARIMAFitResult)
    return collect(result.coefficients)
end

function MetricaBase.nobs(result::ARIMAFitResult)
    return length(result.original_series)
end

# === 序列化支持 ===========================================================

function result_to_payload(result::ARIMAFitResult; include_augment::Bool=true)
    payload = Dict{String, Any}(
        "model_type" => "arima",
        "variable" => result.variable_name,
        "order" => collect(result.order),
        "seasonal_order" => collect(result.seasonal_order),
        "nobs" => length(result.original_series),
        "sigma2" => result.sigma2,
        "loglik" => result.loglik,
        "aic" => result.aic,
        "bic" => result.bic,
        "coefficients" => Dict(string(k) => v for (k, v) in result.coefficients),
        "residuals" => result.residuals,
        "fitted_values" => result.fitted_values,
    )

    # Ljung-Box 检验结果
    n_resid = length(result.residuals)
    lb_lags = min(20, n_resid ÷ 5)
    lb_lags = max(lb_lags, 1)
    lb = ljung_box_test(result.residuals, lags=lb_lags)
    payload["ljung_box"] = Dict(
        "test_statistic" => lb.test_statistic,
        "p_value" => lb.p_value,
        "conclusion" => lb.conclusion,
        "lags" => lb_lags,
    )

    # ACF 和 PACF（用于诊断图）
    payload["acf_values"] = MetricaTimeSeries.acf(result.residuals)
    payload["pacf_values"] = MetricaTimeSeries.pacf(result.residuals)

    payload["glance"] = Dict(
        "model" => string(result.glance_table.model),
        "nobs" => result.glance_table.nobs,
        "metrics" => Dict(string(k) => v for (k, v) in result.glance_table.metrics)
    )

    payload["tidy"] = Dict(
        "rows" => [
            Dict(
                "term" => string(row.name),
                "estimate" => row.estimate,
                "stderror" => row.stderror,
                "statistic" => row.statistic,
                "p_value" => row.pvalue,
                "ci_lower" => row.ci_lower,
                "ci_upper" => row.ci_upper,
            )
            for row in result.tidy_table.rows
        ]
    )

    if !isempty(result.warnings)
        payload["warnings"] = [
            Dict(
                "code" => string(w.code),
                "title" => w.title,
                "detail" => w.detail,
                "hint" => w.hint,
                "severity" => string(w.severity)
            )
            for w in result.warnings
        ]
    end

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = 50
        payload["augment_preview"] = Dict(
            String(k) => v[1:min(length(v), max_preview)]
            for (k, v) in at.columns
        )
    end

    return payload
end
