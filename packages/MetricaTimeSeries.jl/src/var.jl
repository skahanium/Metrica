# var.jl - VAR 模型模块
# 实现 VAR 模型、Granger 因果检验、脉冲响应分析和方差分解

# === 类型定义 =============================================================

"""
    VARModel <: AbstractTimeSeriesModel

VAR 模型规格。
"""
struct VARModel <: AbstractTimeSeriesModel
    variables::Vector{Symbol}
    time_column::Symbol
    lags::Int
    include_constant::Bool
end

"""
    VARFitResult <: AbstractTSFitResult

VAR 模型拟合结果。
"""
struct VARFitResult <: AbstractTSFitResult
    variable_names::Vector{String}
    lags::Int
    coefficients::Matrix{Float64}  # (n_vars * lags + 1) × n_vars
    std_errors::Matrix{Float64}
    residuals::Matrix{Float64}
    fitted_values::Matrix{Float64}
    original_data::Matrix{Float64}
    sigma::Matrix{Float64}  # 残差协方差矩阵
    loglik::Float64
    aic::Float64
    bic::Float64
    hqic::Float64
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    warnings::Vector{MetricaBase.ModelWarning}
end

"""
    VARModel(; variables, time_column, lags=1, include_constant=true)

构造 VAR 模型规格。

# 参数
- `variables`: 变量列名向量
- `time_column`: 时间列名
- `lags`: 滞后阶数
- `include_constant`: 是否包含常数项
"""
function VARModel(; variables::Vector{Symbol}, time_column::Symbol,
                  lags::Int=1, include_constant::Bool=true)
    if length(variables) < 2
        error("VAR 模型至少需要 2 个变量")
    end
    if lags < 1
        error("滞后阶数必须 >= 1")
    end
    return VARModel(variables, time_column, lags, include_constant)
end

# === 拟合方法 =============================================================

"""
    fit(model::VARModel, data::DataFrame) -> VARFitResult

拟合 VAR 模型。
"""
function MetricaBase.fit(model::VARModel, data::DataFrame)
    # 排序数据
    data_sorted = sort_by_time(data, model.time_column)

    # 提取变量
    n_vars = length(model.variables)
    n_obs = nrow(data_sorted)

    # 构建数据矩阵
    Y = Matrix{Float64}(data_sorted[!, model.variables])

    # 构建滞后矩阵
    n_reg = n_obs - model.lags
    k = n_vars * model.lags + (model.include_constant ? 1 : 0)

    X = zeros(n_reg, k)
    y_target = zeros(n_reg, n_vars)

    for t in 1:n_reg
        idx = t + model.lags

        # 滞后值
        col_idx = 1
        for lag in 1:model.lags
            for var in 1:n_vars
                X[t, col_idx] = Y[idx - lag, var]
                col_idx += 1
            end
        end

        # 常数项
        if model.include_constant
            X[t, col_idx] = 1.0
        end

        # 目标值
        y_target[t, :] = Y[idx, :]
    end

    # 方程-方程 OLS 估计
    coefficients = zeros(k, n_vars)
    std_errors = zeros(k, n_vars)
    residuals = zeros(n_reg, n_vars)

    for var in 1:n_vars
        beta = X \ y_target[:, var]
        resid = y_target[:, var] - X * beta

        coefficients[:, var] = beta
        residuals[:, var] = resid

        # 标准误
        sigma2 = sum(resid .^ 2) / (n_reg - k)
        XtX_inv = inv(X' * X)
        se = sqrt.(diag(XtX_inv) .* sigma2)
        std_errors[:, var] = se
    end

    # 拟合值
    fitted_values = X * coefficients

    # 残差协方差矩阵
    sigma = (residuals' * residuals) / n_reg

    # 对数似然
    loglik = -n_reg * n_vars / 2 * log(2π) -
             n_reg / 2 * log(det(sigma)) -
             n_reg * n_vars / 2

    # 信息准则
    n_params = k * n_vars + n_vars * (n_vars + 1) / 2
    aic = -2 * loglik + 2 * n_params
    bic = -2 * loglik + n_params * log(n_reg)
    hqic = -2 * loglik + 2 * n_params * log(log(n_reg))

    # 构建 glance 表
    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :nobs => n_reg,
        :n_vars => n_vars,
        :lags => model.lags,
        :loglik => loglik,
        :aic => aic,
        :bic => bic,
        :hqic => hqic,
    )

    glance_table = MetricaBase.ModelGlance(
        Symbol("VAR($(model.lags))"),
        n_reg,
        0,
        glance_metrics,
        MetricaBase.ModelWarning[]
    )

    # 构建 tidy 表
    coef_rows = MetricaBase.CoefRow[]
    row_idx = 1
    for lag in 1:model.lags
        for (var_idx, var_name) in enumerate(model.variables)
            for (dep_idx, dep_name) in enumerate(model.variables)
                est = coefficients[row_idx, dep_idx]
                se = std_errors[row_idx, dep_idx]
                t_stat = se > 0 ? est / se : 0.0
                p_value = 2 * (1 - cdf(Normal(0, 1), abs(t_stat)))

                term = Symbol("$(var_name)_lag$(lag)_to_$(dep_name)")
                push!(coef_rows, MetricaBase.CoefRow(term, est, se, t_stat, p_value))
            end
            row_idx += 1
        end
    end

    # 常数项
    if model.include_constant
        for (dep_idx, dep_name) in enumerate(model.variables)
            est = coefficients[row_idx, dep_idx]
            se = std_errors[row_idx, dep_idx]
            t_stat = se > 0 ? est / se : 0.0
            p_value = 2 * (1 - cdf(Normal(0, 1), abs(t_stat)))

            push!(coef_rows, MetricaBase.CoefRow(Symbol("constant_to_$(dep_name)"), est, se, t_stat, p_value))
        end
    end

    tidy_table = MetricaBase.TidyTable(coef_rows, "std.error")

    # 警告
    warnings = MetricaBase.ModelWarning[]

    # 检查稳定性条件
    companion = zeros(n_vars * model.lags, n_vars * model.lags)
    for i in 1:n_vars
        for j in 1:n_vars
            for lag in 1:model.lags
                companion[i, (lag-1)*n_vars + j] = coefficients[(lag-1)*n_vars + j, i]
            end
        end
    end
    if model.lags > 1
        companion[n_vars+1:end, 1:n_vars*(model.lags-1)] = I(n_vars*(model.lags-1))
    end

    eigenvalues = eigvals(companion)
    max_eigenvalue = maximum(abs.(eigenvalues))
    if max_eigenvalue >= 1.0
        push!(warnings, MetricaBase.ModelWarning(
            :var_instability,
            "VAR 模型不稳定",
            "最大特征根模 = $(round(max_eigenvalue, digits=4)) >= 1",
            "考虑减少滞后阶数或检查数据",
            MetricaBase.warning
        ))
    end

    return VARFitResult(
        string.(model.variables),
        model.lags,
        coefficients,
        std_errors,
        residuals,
        fitted_values,
        Y,
        sigma,
        loglik,
        aic,
        bic,
        hqic,
        glance_table,
        tidy_table,
        warnings
    )
end

# === Granger 因果检验 =====================================================

"""
    granger_causality(result::VARFitResult, cause::Symbol, effect::Symbol; alpha=0.05) -> NamedTuple

Granger 因果检验。

# 参数
- `result`: VAR 拟合结果
- `cause`: 原因变量名
- `effect`: 结果变量名
- `alpha`: 显著性水平

# 返回
- `(f_stat, p_value, conclusion)`: F 统计量、p 值、结论
"""
function granger_causality(result::VARFitResult, cause::Symbol, effect::Symbol; alpha::Float64=0.05)
    cause_idx = findfirst(==(string(cause)), result.variable_names)
    effect_idx = findfirst(==(string(effect)), result.variable_names)

    if isnothing(cause_idx) || isnothing(effect_idx)
        error("变量名不在模型中")
    end

    n_vars = length(result.variable_names)
    lags = result.lags
    n_obs = size(result.residuals, 1)
    k = size(result.coefficients, 1)

    # 提取 cause 变量的系数
    cause_coeffs = Float64[]
    cause_se = Float64[]
    for lag in 1:lags
        row_idx = (lag - 1) * n_vars + cause_idx
        push!(cause_coeffs, result.coefficients[row_idx, effect_idx])
        push!(cause_se, result.std_errors[row_idx, effect_idx])
    end

    # Wald 统计量
    r = length(cause_coeffs)
    wald = sum((cause_coeffs ./ cause_se) .^ 2)
    f_stat = wald / r
    p_value = 1 - cdf(FDist(Float64(r), Float64(n_obs - k)), f_stat)

    conclusion = p_value < alpha ? "reject" : "fail_to_reject"

    return (f_stat=f_stat, p_value=p_value, conclusion=conclusion)
end

# === 脉冲响应分析 =========================================================

"""
    impulse_response(result::VARFitResult; periods=20) -> Array{Float64, 3}

脉冲响应分析（Cholesky 分解）。

# 参数
- `result`: VAR 拟合结果
- `periods`: 响应期数

# 返回
- `irf`: 脉冲响应矩阵 (periods+1) × n_vars × n_vars
"""
function impulse_response(result::VARFitResult; periods::Int=20)
    n_vars = length(result.variable_names)
    lags = result.lags

    # Cholesky 分解
    P = cholesky(result.sigma).L

    # 初始化脉冲响应
    irf = zeros(periods + 1, n_vars, n_vars)
    irf[1, :, :] = P

    # 构建 VAR 系数矩阵
    Phi = zeros(n_vars, n_vars, lags)
    for lag in 1:lags
        for i in 1:n_vars
            for j in 1:n_vars
                row_idx = (lag - 1) * n_vars + j
                Phi[i, j, lag] = result.coefficients[row_idx, i]
            end
        end
    end

    # 计算脉冲响应
    for t in 1:periods
        response = zeros(n_vars, n_vars)
        for s in 1:min(t, lags)
            response += Phi[:, :, s] * irf[t - s + 1, :, :]
        end
        irf[t + 1, :, :] = response
    end

    return irf
end

# === 方差分解 =============================================================

"""
    variance_decomposition(result::VARFitResult; periods=20) -> Array{Float64, 3}

方差分解。

# 参数
- `result`: VAR 拟合结果
- `periods`: 分解期数

# 返回
- `vd`: 方差分解矩阵 (periods+1) × n_vars × n_vars
"""
function variance_decomposition(result::VARFitResult; periods::Int=20)
    n_vars = length(result.variable_names)

    # 获取脉冲响应
    irf = impulse_response(result, periods=periods)

    # 计算方差分解
    vd = zeros(periods + 1, n_vars, n_vars)

    for t in 1:(periods + 1)
        cum_irf_sq = zeros(n_vars, n_vars)
        for s in 1:t
            cum_irf_sq += irf[s, :, :] .^ 2
        end

        total_var = sum(cum_irf_sq, dims=2)

        for i in 1:n_vars
            vd[t, i, :] = cum_irf_sq[i, :] ./ total_var[i]
        end
    end

    return vd
end

# === 协议方法 =============================================================

function MetricaBase.glance(result::VARFitResult)
    return result.glance_table
end

function MetricaBase.tidy(result::VARFitResult)
    return result.tidy_table
end

function MetricaBase.augment(result::VARFitResult)
    n = size(result.original_data, 1)
    n_fitted = size(result.fitted_values, 1)

    obs = collect(1.0:n)
    fitted = zeros(n, length(result.variable_names))
    resid = zeros(n, length(result.variable_names))

    start_idx = n - n_fitted + 1
    fitted[start_idx:end, :] = result.fitted_values
    resid[start_idx:end, :] = result.residuals

    return MetricaBase.AugmentTable(
        Dict(
            :observation => obs,
            :fitted => fitted,
            :residual => resid,
        ),
        n
    )
end

function MetricaBase.coef(result::VARFitResult)
    return result.coefficients
end

function MetricaBase.nobs(result::VARFitResult)
    return size(result.original_data, 1)
end

# === 序列化支持 ===========================================================

function result_to_payload(result::VARFitResult; include_augment::Bool=true)
    payload = Dict{String, Any}(
        "model_type" => "var",
        "variables" => result.variable_names,
        "lags" => result.lags,
        "nobs" => size(result.original_data, 1),
        "loglik" => result.loglik,
        "aic" => result.aic,
        "bic" => result.bic,
        "hqic" => result.hqic,
        "coefficients" => result.coefficients,
        "std_errors" => result.std_errors,
        "residuals" => result.residuals,
        "sigma" => result.sigma,
    )

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
                "p_value" => row.pvalue
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
