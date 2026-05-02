module MetricaDiagnostics

using Distributions
using LinearAlgebra
using Statistics
using MetricaLinear

export vif, breusch_pagan, white_test, durbin_watson, breusch_godfrey, reset_test, jarque_bera, diagnostics_to_dict

function is_intercept_name(name::Symbol)
    normalized = lowercase(String(name))
    return normalized == "intercept" || normalized == "(intercept)"
end

# === VIF =======================================================================
# 方差膨胀因子 — 检测多重共线性

function vif(fit::MetricaLinear.OLSFitResult)
    names = fit.coefficient_names
    X = fit.design_matrix
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

function breusch_pagan(fit::MetricaLinear.OLSFitResult)
    residuals = fit.residual_vector
    X = fit.design_matrix
    nobs = length(residuals)
    squared_residuals = residuals .^ 2
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

返回 `(statistic, pvalue, dof)`。
"""
function white_test(fit::MetricaLinear.OLSFitResult)
    residuals = fit.residual_vector
    X = fit.design_matrix
    names = fit.coefficient_names
    nobs = length(residuals)

    # 找出非截距列的索引与列
    non_intercept_cols = Int[]
    for (i, name) in enumerate(names)
        is_intercept_name(name) && continue
        push!(non_intercept_cols, i)
    end

    # 构造辅助回归矩阵：原始列 + 非截距列的平方
    aux_cols = [X[:, i] for i in 1:size(X, 2)]
    for i in non_intercept_cols
        push!(aux_cols, X[:, i] .^ 2)
    end
    Z = hcat(aux_cols...)

    squared_residuals = residuals .^ 2
    coef = Z \ squared_residuals
    fitted = Z * coef
    rss = sum(abs2, squared_residuals - fitted)
    tss = sum(abs2, squared_residuals .- mean(squared_residuals))
    r2 = iszero(tss) ? 0.0 : max(0.0, 1 - rss / tss)
    statistic = nobs * r2
    dof = length(non_intercept_cols)
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

返回 `(statistic, pvalue)`。
p 值采用正态近似（DW 在大样本下渐近正态）。
"""
function durbin_watson(fit::MetricaLinear.OLSFitResult)
    residuals = fit.residual_vector
    n = length(residuals)

    n < 2 && return (statistic=NaN, pvalue=NaN)

    diff_sum = sum(abs2, residuals[2:end] - residuals[1:(end-1)])
    residual_sum = sum(abs2, residuals)
    dw = iszero(residual_sum) ? NaN : diff_sum / residual_sum

    # 正态近似：DW ~ N(2, 4/n)
    pvalue = if !isnan(dw) && n >= 10
        se = 2 / sqrt(n)
        z = (dw - 2) / se
        2 * (1 - cdf(Normal(), abs(z)))
    else
        nothing
    end

    return (statistic=dw, pvalue=pvalue)
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
function breusch_godfrey(fit::MetricaLinear.OLSFitResult; p::Int=2)
    residuals = fit.residual_vector
    X = fit.design_matrix
    n = length(residuals)

    n <= p && return (statistic=nothing, pvalue=nothing, dof=p)

    # 构造滞后残差矩阵
    lagged_residuals = Matrix{Float64}(undef, n, p)
    for lag in 1:p
        lagged_residuals[1:lag, lag] .= 0.0
        lagged_residuals[(lag+1):end, lag] = residuals[1:(n-lag)]
    end

    # 截取有效观测（p+1 到 n）
    y_aux = residuals[(p+1):end]
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
function reset_test(fit::MetricaLinear.OLSFitResult; power::UnitRange{Int}=2:3)
    y = fit.response_vector
    X = fit.design_matrix
    fitted = fit.fitted_values
    residuals = fit.residual_vector
    n = length(y)
    k = size(X, 2)

    # 构造辅助回归矩阵 [X, ŷ^p for p in power]
    aux_cols = [X[:, i] for i in 1:k]
    for p in power
        push!(aux_cols, fitted .^ p)
    end
    Z = hcat(aux_cols...)
    r = length(power)  # 约束数

    coef_aux = Z \ y
    fitted_aux = Z * coef_aux
    rss_unrestricted = sum(abs2, y - fitted_aux)

    rss_restricted = sum(abs2, residuals)

    # F = ((RSS_R - RSS_UR) / r) / (RSS_UR / (n - k - r))
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
function jarque_bera(fit::MetricaLinear.OLSFitResult)
    residuals = fit.residual_vector
    n = length(residuals)

    n < 5 && return (statistic=NaN, pvalue=NaN, skewness=NaN, kurtosis=NaN)

    m2 = var(residuals; corrected=false)  # 二阶中心矩（总体方差）
    m3 = mean((residuals .- mean(residuals)) .^ 3)  # 三阶中心矩
    m4 = mean((residuals .- mean(residuals)) .^ 4)  # 四阶中心矩

    S = m3 / (m2^(3/2))  # 偏度
    K = m4 / (m2^2)      # 峰度

    statistic = (n / 6) * (S^2 + (K - 3)^2 / 4)
    pvalue = 1 - cdf(Chisq(2), statistic)

    return (statistic=statistic, pvalue=pvalue, skewness=S, kurtosis=K)
end

include("diagnostics_common.jl")

end
