module MetricaDiagnostics

using Distributions
using LinearAlgebra
using Statistics
using MetricaBase

export vif, breusch_pagan, white_test, durbin_watson, breusch_godfrey, reset_test, jarque_bera, diagnostics_to_dict

function is_intercept_name(name::Symbol)
    normalized = lowercase(String(name))
    return normalized == "intercept" || normalized == "(intercept)"
end

# === 内部辅助：从拟合结果安全提取所需数据 ========================================

function _check_design_matrix(fit::AbstractFittedModel)
    X = design_matrix(fit)
    isnothing(X) && throw(ArgumentError("该模型类型不支持设计矩阵提取。诊断检验当前仅适用于提供设计矩阵的模型。"))
    return X
end

function _check_residuals(fit::AbstractFittedModel)
    r = residuals(fit)
    isnothing(r) && throw(ArgumentError("该模型类型不支持残差提取。"))
    return r
end

function _check_response(fit::AbstractFittedModel)
    y = response(fit)
    isnothing(y) && throw(ArgumentError("该模型类型不支持响应向量提取。"))
    return y
end

function _check_fitted(fit::AbstractFittedModel)
    f = fitted(fit)
    isnothing(f) && throw(ArgumentError("该模型类型不支持拟合值提取。"))
    return f
end

# === VIF =======================================================================
# 方差膨胀因子 — 检测多重共线性

function vif(fit::AbstractFittedModel)
    names = coefficient_names(fit)
    X = _check_design_matrix(fit)
    results = NamedTuple[]

    for index in eachindex(names)
        is_intercept_name(names[index]) && continue

        other_indices = [candidate for candidate in eachindex(names) if candidate != index]
        if isempty(other_indices)
            push!(results, (name=String(names[index]), vif=1.0))
            continue
        end

        y = X[:, index]
        X_other = X[:, other_indices]
        coefficients = X_other \ y
        fitted = X_other * coefficients
        rss = sum(abs2, y - fitted)
        tss = sum(abs2, y .- mean(y))
        r2 = iszero(tss) ? 1.0 : 1 - rss / tss
        vif_value = isapprox(1 - r2, 0.0; atol=sqrt(eps(Float64))) ? Inf : 1 / (1 - r2)
        push!(results, (name=String(names[index]), vif=vif_value))
    end

    return results
end

# === Breusch-Pagan =============================================================
# 异方差检验（线性形式）

function breusch_pagan(fit::AbstractFittedModel)
    r = _check_residuals(fit)
    X = _check_design_matrix(fit)
    nobs = length(r)
    squared_residuals = r .^ 2
    coefficients = X \ squared_residuals
    fitted = X * coefficients
    rss = sum(abs2, squared_residuals - fitted)
    tss = sum(abs2, squared_residuals .- mean(squared_residuals))
    r2 = iszero(tss) ? 0.0 : max(0.0, 1 - rss / tss)
    statistic = nobs * r2
    dof = max(size(X, 2) - 1, 1)
    pvalue = 1 - cdf(Chisq(dof), statistic)

    return (statistic=statistic, pvalue=pvalue, dof=dof)
end

# === White 检验 ================================================================
# 异方差检验（含二次项，不含交叉项）

"""
White 异方差检验（无交叉项版本）。

在原始设计矩阵的基础上加入每个非截距列的平方项作为辅助回归元，对残差平方做
辅助回归，以 n·R² 作为 LM 统计量，渐近服从 χ²(df)。
df = 辅助回归矩阵非截距列数 = 原始非截距列数 + 平方项列数。

返回 `(statistic, pvalue, dof)`。
"""
function white_test(fit::AbstractFittedModel)
    r = _check_residuals(fit)
    X = _check_design_matrix(fit)
    names = coefficient_names(fit)
    nobs = length(r)

    non_intercept_cols = Int[]
    for (i, name) in enumerate(names)
        is_intercept_name(name) && continue
        push!(non_intercept_cols, i)
    end

    aux_cols = [X[:, i] for i in 1:size(X, 2)]
    for i in non_intercept_cols
        push!(aux_cols, X[:, i] .^ 2)
    end
    Z = hcat(aux_cols...)

    squared_residuals = r .^ 2
    coef = Z \ squared_residuals
    fitted = Z * coef
    rss = sum(abs2, squared_residuals - fitted)
    tss = sum(abs2, squared_residuals .- mean(squared_residuals))
    r2 = iszero(tss) ? 0.0 : max(0.0, 1 - rss / tss)
    statistic = nobs * r2
    dof = size(Z, 2) - 1
    dof = max(dof, 1)
    pvalue = 1 - cdf(Chisq(dof), statistic)

    return (statistic=statistic, pvalue=pvalue, dof=dof)
end

# === Durbin-Watson =============================================================
# 一阶自相关检验

"""
Durbin-Watson 一阶自相关检验。

统计量 DW 的取值范围为 [0, 4]，接近 2 表示无一阶自相关。
DW < 2 表示正自相关，DW > 2 表示负自相关。

返回 `(statistic, pvalue, warnings)`。
p 值采用正态近似（DW 在大样本下渐近正态）。
DW 分布依赖样本量和设计矩阵结构，当前正态近似为粗略近似，
小样本或复杂设计矩阵下 p 值可能严重失真。
建议参考 Durbin-Watson 界限检验表（dL, dU）获取精确推断。
"""
function durbin_watson(fit::AbstractFittedModel)
    r = _check_residuals(fit)
    n = length(r)

    n < 2 && return (statistic=NaN, pvalue=NaN, warnings=Dict{String,Any}[])

    diff_sum = sum(abs2, r[2:end] - r[1:(end-1)])
    residual_sum = sum(abs2, r)
    dw = iszero(residual_sum) ? NaN : diff_sum / residual_sum

    pvalue = if !isnan(dw) && n >= 10
        se = 2 / sqrt(n)
        z = (dw - 2) / se
        2 * (1 - cdf(Normal(), abs(z)))
    else
        nothing
    end

    dw_warnings = Dict{String,Any}[]
    if pvalue !== nothing
        push!(dw_warnings, Dict(
            "code" => "dw_pvalue_approximate",
            "title" => "DW p 值为粗略近似",
            "detail" => "Durbin-Watson 分布依赖样本量和设计矩阵结构，当前正态近似 N(2, 4/n) 在小样本或复杂设计下可能严重失真。",
            "hint" => "参考 Durbin-Watson 界限检验表（dL, dU）获取精确推断，或使用 Breusch-Godfrey 检验作为替代。",
            "severity" => "warning",
        ))
    end

    return (statistic=dw, pvalue=pvalue, warnings=dw_warnings)
end

# === Breusch-Godfrey ===========================================================
# 高阶自相关检验

"""
Breusch-Godfrey 高阶自相关检验。

检验残差中是否存在直到 p 阶的自相关。对残差做包含原始设计矩阵
与滞后 1..p 阶残差的辅助回归，以 (n-p)·R² 作为 LM 统计量，
渐近服从 χ²(p)。

返回 `(statistic, pvalue, dof)`。
"""
function breusch_godfrey(fit::AbstractFittedModel; p::Int=2)
    r = _check_residuals(fit)
    X = _check_design_matrix(fit)
    n = length(r)

    n <= p && return (statistic=nothing, pvalue=nothing, dof=p)

    lagged_residuals = Matrix{Float64}(undef, n, p)
    for lag in 1:p
        lagged_residuals[1:lag, lag] .= 0.0
        lagged_residuals[(lag+1):end, lag] = r[1:(n-lag)]
    end

    y_aux = r[(p+1):end]
    X_aux = X[(p+1):end, :]
    L_aux = lagged_residuals[(p+1):end, :]
    Z = hcat(X_aux, L_aux)
    n_eff = size(Z, 1)

    coef = Z \ y_aux
    fitted = Z * coef
    rss = sum(abs2, y_aux - fitted)
    tss = sum(abs2, y_aux .- mean(y_aux))
    r2 = iszero(tss) ? 0.0 : max(0.0, 1 - rss / tss)
    statistic = n_eff * r2
    dof = p
    pvalue = 1 - cdf(Chisq(dof), statistic)

    return (statistic=statistic, pvalue=pvalue, dof=dof)
end

# === RESET 检验 ================================================================
# Ramsey 回归设定误差检验

"""
Ramsey RESET 检验（模型设定检验）。

在原模型中添加拟合值的幂次项（默认 ŷ² 和 ŷ³），检验它们是否联合显著。
使用 F 统计量。

返回 `(statistic, pvalue, df_num, df_den)`。
"""
function reset_test(fit::AbstractFittedModel; power::UnitRange{Int}=2:3)
    y = _check_response(fit)
    X = _check_design_matrix(fit)
    f = _check_fitted(fit)
    r = _check_residuals(fit)
    n = length(y)
    k = size(X, 2)

    aux_cols = [X[:, i] for i in 1:k]
    for p in power
        push!(aux_cols, f .^ p)
    end
    Z = hcat(aux_cols...)
    r = length(power)

    coef_aux = Z \ y
    fitted_aux = Z * coef_aux
    rss_unrestricted = sum(abs2, y - fitted_aux)

    rss_restricted = sum(abs2, r)

    f_stat = ((rss_restricted - rss_unrestricted) / r) / (rss_unrestricted / (n - k - r))
    df_num = r
    df_den = n - k - r

    if df_den > 0 && !isnan(f_stat) && f_stat >= 0
        pvalue = 1 - cdf(FDist(df_num, df_den), f_stat)
    else
        f_stat = NaN
        pvalue = NaN
    end

    return (statistic=f_stat, pvalue=pvalue, df_num=df_num, df_den=df_den)
end

# === Jarque-Bera ===============================================================
# 残差正态性检验

"""
Jarque-Bera 正态性检验。

基于残差的偏度与峰度检验其是否服从正态分布。
JB = n/6 · (S² + (K-3)²/4)，其中 S 为偏度，K 为峰度。
渐近服从 χ²(2)。

返回 `(statistic, pvalue, skewness, kurtosis)`。
"""
function jarque_bera(fit::AbstractFittedModel)
    r = _check_residuals(fit)
    n = length(r)

    n < 5 && return (statistic=NaN, pvalue=NaN, skewness=NaN, kurtosis=NaN)

    m2 = var(r; corrected=false)
    m3 = mean((r .- mean(r)) .^ 3)
    m4 = mean((r .- mean(r)) .^ 4)

    S = m3 / (m2^(3/2))
    K = m4 / (m2^2)

    statistic = (n / 6) * (S^2 + (K - 3)^2 / 4)
    pvalue = 1 - cdf(Chisq(2), statistic)

    return (statistic=statistic, pvalue=pvalue, skewness=S, kurtosis=K)
end

include("diagnostics_common.jl")

end
