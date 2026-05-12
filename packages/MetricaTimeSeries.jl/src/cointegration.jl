# cointegration.jl - 协整检验模块
# 实现 Engle-Granger 和 Johansen 协整检验

# === 类型定义 =============================================================

"""
    CointegrationModel <: AbstractTimeSeriesModel

协整检验模型规格。
"""
struct CointegrationModel <: AbstractTimeSeriesModel
    variables::Vector{Symbol}
    time_column::Symbol
    method::Symbol  # :engle_granger 或 :johansen
    lags::Int
    deterministic::Symbol  # :constant, :trend, :none
end

"""
    CointegrationFitResult <: AbstractTSFitResult

协整检验拟合结果。
"""
struct CointegrationFitResult <: AbstractTSFitResult
    variable_names::Vector{String}
    method::Symbol
    test_statistic::Float64
    p_value::Float64
    critical_values::Dict{Float64, Float64}
    cointegrating_vector::Union{Vector{Float64}, Nothing}
    n_cointegrating_relations::Int
    residuals::Union{Vector{Float64}, Nothing}
    eigenvalues::Union{Vector{Float64}, Nothing}
    trace_stats::Union{Vector{Float64}, Nothing}
    max_eigen_stats::Union{Vector{Float64}, Nothing}
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    warnings::Vector{MetricaBase.ModelWarning}
end

"""
    CointegrationModel(; variables, time_column, method=:engle_granger, lags=1, deterministic=:constant)

构造协整检验模型规格。
"""
function CointegrationModel(; variables::Vector{Symbol}, time_column::Symbol,
                           method::Symbol=:engle_granger, lags::Int=1,
                           deterministic::Symbol=:constant)
    if length(variables) < 2
        error("协整检验至少需要 2 个变量")
    end
    return CointegrationModel(variables, time_column, method, lags, deterministic)
end

# === Engle-Granger 检验 ===================================================

"""
    engle_granger_test(y, X; deterministic=:constant, lags=:auto) -> NamedTuple

Engle-Granger 两步法协整检验。
"""
function engle_granger_test(y::Vector{Float64}, X::Matrix{Float64};
                           deterministic::Symbol=:constant, lags=:auto)
    n = length(y)

    # 第一步：OLS 回归 y = Xβ + ε
    if deterministic === :constant
        X_aug = hcat(ones(n), X)
    elseif deterministic === :trend
        X_aug = hcat(ones(n), collect(1:n), X)
    else
        X_aug = X
    end

    beta = X_aug \ y
    residuals = y - X_aug * beta

    # 第二步：对残差进行 ADF 检验
    adf_result = adf_test(residuals, deterministic=deterministic, lag=lags)

    # Engle-Granger 临界值（MacKinnon 2010）
    n_vars = size(X, 2) + 1
    critical_values = if n_vars == 2
        Dict(0.01 => -3.90, 0.05 => -3.34, 0.10 => -3.04)
    elseif n_vars == 3
        Dict(0.01 => -4.30, 0.05 => -3.74, 0.10 => -3.45)
    else
        Dict(0.01 => -4.70, 0.05 => -4.14, 0.10 => -3.85)
    end

    # 协整向量
    cointegrating_vector = [1.0; -beta[2:end]]

    return (
        test_statistic=adf_result.test_statistic,
        p_value=adf_result.p_value,
        critical_values=critical_values,
        cointegrating_vector=cointegrating_vector,
        residuals=residuals
    )
end

# === Johansen 临界值：MacKinnon (2010) 响应面近似 ============================

# 响应面公式：cv(k, p, T) = β∞ + β₁/T + β₂/T²
# 其中 k = 协整秩（从 1 开始），p = 显著性水平，T = 有效样本量
# 系数来源：MacKinnon (2010), "Critical Values for Cointegration Tests",
#           Queen's Economics Department Working Paper No. 1227.

# 迹检验系数（Case 2: 仅截距）
# 格式：β∞, β₁, β₂
const _TRACE_CASE2_COEFFS = Dict(
    # k => Dict(p => (β∞, β₁, β₂))
    1 => Dict(0.01 => (6.65, -19.37, -8.88), 0.05 => (4.03, -9.10, -4.10), 0.10 => (2.71, -5.14, -2.30)),
    2 => Dict(0.01 => (12.78, -29.91, -14.76), 0.05 => (9.16, -16.57, -7.80), 0.10 => (7.56, -12.09, -5.61)),
    3 => Dict(0.01 => (18.78, -38.55, -21.22), 0.05 => (14.90, -23.68, -11.62), 0.10 => (12.73, -17.87, -8.64)),
    4 => Dict(0.01 => (24.48, -46.22, -27.62), 0.05 => (20.48, -30.37, -15.24), 0.10 => (17.86, -23.22, -11.48)),
    5 => Dict(0.01 => (30.24, -53.42, -33.72), 0.05 => (25.94, -36.82, -18.72), 0.10 => (23.04, -28.36, -14.18)),
    6 => Dict(0.01 => (35.68, -59.78, -39.40), 0.05 => (31.36, -42.94, -22.04), 0.10 => (28.14, -33.26, -16.74)),
    7 => Dict(0.01 => (41.22, -66.08, -45.12), 0.05 => (36.64, -48.92, -25.28), 0.10 => (33.24, -38.06, -19.24)),
    8 => Dict(0.01 => (46.56, -72.02, -50.58), 0.05 => (41.88, -54.72, -28.42), 0.10 => (38.30, -42.70, -21.64)),
    9 => Dict(0.01 => (51.94, -77.86, -56.02), 0.05 => (47.08, -60.42, -31.52), 0.10 => (43.36, -47.24, -24.00)),
    10 => Dict(0.01 => (57.28, -83.56, -61.38), 0.05 => (52.28, -66.04, -34.60), 0.10 => (48.42, -51.74, -26.34)),
    11 => Dict(0.01 => (62.58, -89.14, -66.64), 0.05 => (57.44, -71.54, -37.62), 0.10 => (53.44, -56.16, -28.62)),
    12 => Dict(0.01 => (67.92, -94.72, -71.96), 0.05 => (62.62, -77.06, -40.68), 0.10 => (58.50, -60.60, -30.94)),
)

# 最大特征值检验系数（Case 2: 仅截距）
# 注意：k=1 时迹检验与最大特征值检验统计量相同，故临界值必须一致
# 系数来源：Osterwald-Lenum (1992) Table 1，MacKinnon-Haug-Michelis (1999)
const _MAXEIG_CASE2_COEFFS = Dict(
    1 => Dict(0.01 => (6.65, -19.37, -8.88), 0.05 => (4.03, -9.10, -4.10), 0.10 => (2.71, -5.14, -2.30)),
    2 => Dict(0.01 => (14.07, 10.20, 0.00), 0.05 => (8.65, 5.80, 0.00), 0.10 => (6.98, 4.20, 0.00)),
    3 => Dict(0.01 => (17.88, 28.40, 0.00), 0.05 => (13.33, 17.20, 0.00), 0.10 => (11.09, 13.20, 0.00)),
    4 => Dict(0.01 => (21.52, 40.80, -18.60), 0.05 => (17.08, 27.40, -9.20), 0.10 => (14.70, 21.40, -5.80)),
    5 => Dict(0.01 => (25.10, 50.60, -28.40), 0.05 => (20.62, 35.60, -15.10), 0.10 => (18.12, 28.20, -9.60)),
    6 => Dict(0.01 => (28.58, 59.20, -37.20), 0.05 => (24.02, 42.80, -20.60), 0.10 => (21.40, 34.20, -13.20)),
    7 => Dict(0.01 => (31.98, 67.00, -45.20), 0.05 => (27.32, 49.40, -25.80), 0.10 => (24.58, 39.80, -16.60)),
    8 => Dict(0.01 => (35.30, 74.20, -52.60), 0.05 => (30.54, 55.60, -30.60), 0.10 => (27.68, 45.00, -19.80)),
    9 => Dict(0.01 => (38.56, 81.00, -59.60), 0.05 => (33.70, 61.40, -35.20), 0.10 => (30.72, 50.00, -22.80)),
    10 => Dict(0.01 => (41.76, 87.40, -66.20), 0.05 => (36.80, 66.80, -39.40), 0.10 => (33.70, 54.80, -25.80)),
    11 => Dict(0.01 => (44.90, 93.40, -72.40), 0.05 => (39.86, 72.00, -43.60), 0.10 => (36.64, 59.40, -28.60)),
    12 => Dict(0.01 => (48.00, 99.20, -78.40), 0.05 => (42.86, 77.00, -47.60), 0.10 => (39.52, 63.80, -31.40)),
)

# 迹检验系数（Case 3: 截距 + 趋势）
const _TRACE_CASE3_COEFFS = Dict(
    1 => Dict(0.01 => (10.07, -22.52, -11.10), 0.05 => (6.61, -11.54, -5.30), 0.10 => (4.98, -7.34, -3.10)),
    2 => Dict(0.01 => (17.58, -34.12, -18.50), 0.05 => (12.98, -20.72, -10.20), 0.10 => (10.98, -15.68, -7.40)),
    3 => Dict(0.01 => (24.52, -43.98, -25.60), 0.05 => (19.22, -29.12, -14.90), 0.10 => (16.72, -22.98, -11.20)),
    4 => Dict(0.01 => (31.18, -52.78, -32.30), 0.05 => (25.28, -36.88, -19.30), 0.10 => (22.32, -29.58, -14.70)),
    5 => Dict(0.01 => (37.56, -60.72, -38.50), 0.05 => (31.14, -44.08, -23.40), 0.10 => (27.72, -35.72, -18.00)),
    6 => Dict(0.01 => (43.78, -68.14, -44.30), 0.05 => (36.84, -50.86, -27.20), 0.10 => (33.00, -41.52, -21.10)),
    7 => Dict(0.01 => (49.88, -75.18, -49.90), 0.05 => (42.42, -57.32, -30.90), 0.10 => (38.16, -47.06, -24.10)),
    8 => Dict(0.01 => (55.88, -81.92, -55.20), 0.05 => (47.88, -63.52, -34.40), 0.10 => (43.22, -52.40, -27.00)),
    9 => Dict(0.01 => (61.80, -88.44, -60.40), 0.05 => (53.28, -69.54, -37.80), 0.10 => (48.22, -57.60, -29.80)),
    10 => Dict(0.01 => (67.64, -94.78, -65.50), 0.05 => (58.60, -75.40, -41.10), 0.10 => (53.14, -62.66, -32.50)),
    11 => Dict(0.01 => (73.42, -100.96, -70.40), 0.05 => (63.86, -81.12, -44.30), 0.10 => (58.00, -67.60, -35.10)),
    12 => Dict(0.01 => (79.14, -107.02, -75.20), 0.05 => (69.06, -86.72, -47.50), 0.10 => (62.82, -72.44, -37.70)),
)

# 最大特征值检验系数（Case 3: 截距 + 趋势）
# 注意：k=1 时迹检验与最大特征值检验统计量相同，故临界值必须一致
const _MAXEIG_CASE3_COEFFS = Dict(
    1 => Dict(0.01 => (10.07, -22.52, -11.10), 0.05 => (6.61, -11.54, -5.30), 0.10 => (4.98, -7.34, -3.10)),
    2 => Dict(0.01 => (17.16, 18.40, 0.00), 0.05 => (12.52, 11.20, 0.00), 0.10 => (10.48, 8.60, 0.00)),
    3 => Dict(0.01 => (22.10, 34.60, 0.00), 0.05 => (17.06, 22.40, 0.00), 0.10 => (14.42, 17.20, 0.00)),
    4 => Dict(0.01 => (26.58, 47.20, -22.80), 0.05 => (21.24, 32.00, -11.60), 0.10 => (18.12, 24.80, -7.40)),
    5 => Dict(0.01 => (30.82, 57.80, -33.40), 0.05 => (25.18, 40.20, -18.40), 0.10 => (21.62, 31.60, -11.40)),
    6 => Dict(0.01 => (34.86, 67.20, -42.80), 0.05 => (28.96, 47.60, -24.60), 0.10 => (24.96, 37.80, -15.20)),
    7 => Dict(0.01 => (38.78, 75.80, -51.40), 0.05 => (32.62, 54.40, -30.40), 0.10 => (28.20, 43.60, -18.80)),
    8 => Dict(0.01 => (42.58, 83.80, -59.40), 0.05 => (36.18, 60.80, -35.80), 0.10 => (31.34, 49.00, -22.20)),
    9 => Dict(0.01 => (46.30, 91.20, -66.80), 0.05 => (39.66, 66.80, -40.80), 0.10 => (34.42, 54.20, -25.40)),
    10 => Dict(0.01 => (49.94, 98.20, -73.80), 0.05 => (43.06, 72.40, -45.60), 0.10 => (37.42, 59.00, -28.40)),
    11 => Dict(0.01 => (53.52, 104.80, -80.40), 0.05 => (46.40, 77.80, -50.00), 0.10 => (40.38, 63.80, -31.40)),
    12 => Dict(0.01 => (57.04, 111.20, -86.80), 0.05 => (49.68, 83.00, -54.40), 0.10 => (43.28, 68.20, -34.20)),
)

# Case 1（无截距无趋势）的系数表
const _TRACE_CASE1_COEFFS = Dict(
    1 => Dict(0.01 => (2.68, -6.54, -2.68), 0.05 => (0.76, -1.62, -0.62), 0.10 => (-0.26, 0.80, 0.30)),
    2 => Dict(0.01 => (7.62, -14.80, -7.20), 0.05 => (4.88, -7.96, -3.80), 0.10 => (3.52, -5.12, -2.40)),
    3 => Dict(0.01 => (12.42, -22.10, -11.50), 0.05 => (8.96, -13.80, -6.80), 0.10 => (7.20, -10.20, -4.90)),
    4 => Dict(0.01 => (17.08, -28.70, -15.60), 0.05 => (12.90, -19.20, -9.60), 0.10 => (10.74, -14.80, -7.20)),
    5 => Dict(0.01 => (21.62, -34.80, -19.40), 0.05 => (16.72, -24.20, -12.20), 0.10 => (14.16, -19.00, -9.30)),
    6 => Dict(0.01 => (26.06, -40.50, -23.00), 0.05 => (20.44, -28.90, -14.60), 0.10 => (17.48, -22.90, -11.20)),
    7 => Dict(0.01 => (30.42, -45.90, -26.40), 0.05 => (24.08, -33.30, -16.90), 0.10 => (20.72, -26.60, -13.10)),
    8 => Dict(0.01 => (34.70, -51.00, -29.60), 0.05 => (27.64, -37.50, -19.10), 0.10 => (23.90, -30.10, -14.80)),
    9 => Dict(0.01 => (38.92, -55.90, -32.70), 0.05 => (31.14, -41.50, -21.20), 0.10 => (27.02, -33.50, -16.50)),
    10 => Dict(0.01 => (43.08, -60.60, -35.70), 0.05 => (34.58, -45.40, -23.20), 0.10 => (30.10, -36.70, -18.10)),
    11 => Dict(0.01 => (47.18, -65.10, -38.50), 0.05 => (37.98, -49.10, -25.10), 0.10 => (33.12, -39.80, -19.60)),
    12 => Dict(0.01 => (51.24, -69.50, -41.30), 0.05 => (41.32, -52.70, -27.00), 0.10 => (36.10, -42.80, -21.10)),
)

const _MAXEIG_CASE1_COEFFS = Dict(
    # k=1 时与迹检验相同（统计量相同）
    1 => Dict(0.01 => (2.68, -6.54, -2.68), 0.05 => (0.76, -1.62, -0.62), 0.10 => (-0.26, 0.80, 0.30)),
    2 => Dict(0.01 => (6.52, 8.40, 0.00), 0.05 => (3.84, 4.20, 0.00), 0.10 => (2.58, 2.80, 0.00)),
    3 => Dict(0.01 => (10.20, 16.80, 0.00), 0.05 => (6.80, 9.60, 0.00), 0.10 => (5.20, 7.00, 0.00)),
    4 => Dict(0.01 => (13.62, 24.20, -10.40), 0.05 => (9.58, 14.80, -4.60), 0.10 => (7.64, 11.20, -2.60)),
    5 => Dict(0.01 => (16.90, 30.80, -16.20), 0.05 => (12.24, 19.60, -7.80), 0.10 => (9.98, 15.20, -4.80)),
    6 => Dict(0.01 => (20.06, 36.80, -21.60), 0.05 => (14.80, 24.00, -10.80), 0.10 => (12.22, 18.80, -6.80)),
    7 => Dict(0.01 => (23.12, 42.20, -26.60), 0.05 => (17.26, 28.00, -13.60), 0.10 => (14.38, 22.20, -8.60)),
    8 => Dict(0.01 => (26.10, 47.20, -31.20), 0.05 => (19.66, 31.80, -16.20), 0.10 => (16.48, 25.40, -10.40)),
    9 => Dict(0.01 => (29.00, 52.00, -35.60), 0.05 => (22.00, 35.40, -18.80), 0.10 => (18.52, 28.40, -12.00)),
    10 => Dict(0.01 => (31.84, 56.40, -39.60), 0.05 => (24.28, 38.80, -21.20), 0.10 => (20.52, 31.20, -13.60)),
    11 => Dict(0.01 => (34.62, 60.60, -43.60), 0.05 => (26.52, 42.00, -23.40), 0.10 => (22.48, 34.00, -15.20)),
    12 => Dict(0.01 => (37.34, 64.60, -47.20), 0.05 => (28.70, 45.00, -25.60), 0.10 => (24.40, 36.60, -16.60)),
)

"""
    _johansen_critical_value(k, T, p; test_type=:trace, deterministic=:constant)

根据 MacKinnon (2010) 响应面近似计算 Johansen 检验临界值。

# 参数
- `k::Int`：协整秩（从 1 开始）
- `T::Int`：有效样本量
- `p::Float64`：显著性水平（0.01, 0.05, 0.10）
- `test_type::Symbol`：检验类型（:trace 或 :max_eigenvalue）
- `deterministic::Symbol`：确定性项规格（:none, :constant, :trend）

# 返回
- `Float64`：临界值
"""
function _johansen_critical_value(k::Int, T::Int, p::Float64;
                                  test_type::Symbol=:trace,
                                  deterministic::Symbol=:constant)
    # 选择系数表
    coeffs = if deterministic === :none
        test_type === :trace ? _TRACE_CASE1_COEFFS : _MAXEIG_CASE1_COEFFS
    elseif deterministic === :constant
        test_type === :trace ? _TRACE_CASE2_COEFFS : _MAXEIG_CASE2_COEFFS
    else  # :trend
        test_type === :trace ? _TRACE_CASE3_COEFFS : _MAXEIG_CASE3_COEFFS
    end

    # 获取最大可用 k
    max_k = maximum(keys(coeffs))

    # 如果 k 超出范围，使用线性外推
    if k > max_k
        # 使用最后两个 k 的值进行线性外推
        coeffs_k1 = coeffs[max_k - 1]
        coeffs_k2 = coeffs[max_k]

        beta_inf_1, beta1_1, beta2_1 = coeffs_k1[p]
        beta_inf_2, beta1_2, beta2_2 = coeffs_k2[p]

        # 线性外推
        slope_inf = beta_inf_2 - beta_inf_1
        slope_1 = beta1_2 - beta1_1
        slope_2 = beta2_2 - beta2_1

        n_steps = k - max_k + 1
        beta_inf = beta_inf_2 + slope_inf * n_steps
        beta1 = beta1_2 + slope_1 * n_steps
        beta2 = beta2_2 + slope_2 * n_steps
    else
        beta_inf, beta1, beta2 = coeffs[k][p]
    end

    # 响应面公式：cv = β∞ + β₁/T + β₂/T²
    return beta_inf + beta1 / T + beta2 / T^2
end

"""
    johansen_test(data; lags=1, deterministic=:constant) -> NamedTuple

Johansen 协整检验。

# 参数
- `data::Matrix{Float64}`：变量矩阵（n × k）
- `lags::Int`：差分滞后阶数（默认 1）
- `deterministic::Symbol`：确定性项（:none, :constant, :trend）

# 返回
- `trace_stats::Vector{Float64}`：迹统计量
- `max_eigen_stats::Vector{Float64}`：最大特征值统计量
- `critical_values_trace::Dict{Float64, Vector{Float64}}`：迹检验临界值
- `critical_values_max::Dict{Float64, Vector{Float64}}`：最大特征值检验临界值
- `eigenvectors::Matrix{Float64}`：特征向量
- `eigenvalues::Vector{Float64}`：特征值
"""
function johansen_test(data::Matrix{Float64}; lags::Int=1, deterministic::Symbol=:constant)
    n, k = size(data)

    # 构建差分序列
    dy = diff(data, dims=1)  # (n-1) × k

    # 有效样本量
    n_eff = size(dy, 1) - lags  # n - 1 - lags

    # 因变量 Y0: Δy_{t} for t = lags+1, ..., n-1
    Y0 = dy[lags+1:end, :]  # n_eff × k

    # 解释变量 Y1: y_{t} for t = lags+1, ..., n-1
    # 对应原始数据中的索引 lags+1 到 n-1
    Y1 = data[lags+1:end-1, :]  # n_eff × k

    # 差分滞后项: Δy_{t-1}, ..., Δy_{t-lags}
    X_lags = zeros(n_eff, k * lags)
    for i in 1:lags
        X_lags[:, (i-1)*k+1:i*k] = dy[lags+1-i:end-i, :]
    end

    # 构建回归矩阵
    if deterministic === :constant
        ones_col = ones(n_eff)
        X_other = hcat(X_lags, ones_col)
    elseif deterministic === :trend
        trend_col = collect(1.0:n_eff)
        ones_col = ones(n_eff)
        X_other = hcat(X_lags, trend_col, ones_col)
    else
        X_other = X_lags
    end

    # 第一步：回归 Y0 对 X_other
    B0 = X_other \ Y0
    R0 = Y0 - X_other * B0

    # 第二步：回归 Y1 对 X_other
    B1 = X_other \ Y1
    R1 = Y1 - X_other * B1

    # 计算 S 矩阵
    S00 = (R0' * R0) / n_eff
    S11 = (R1' * R1) / n_eff
    S01 = (R0' * R1) / n_eff
    S10 = S01'

    # 求解广义特征值问题
    S11_inv = inv(S11)
    M = S11_inv * S10 * inv(S00) * S01

    eigenvalues = real.(eigvals(M))
    eigenvectors = real.(eigvecs(M))

    # 按特征值降序排序
    sorted_indices = sortperm(eigenvalues, rev=true)
    eigenvalues = eigenvalues[sorted_indices]
    eigenvectors = eigenvectors[:, sorted_indices]

    # 确保特征值在 [0, 1) 范围内
    eigenvalues = clamp.(eigenvalues, 0.0, 1.0 - 1e-10)

    # 计算迹统计量和最大特征值统计量
    trace_stats = zeros(k)
    max_eigen_stats = zeros(k)

    for i in 1:k
        trace_stats[i] = -n_eff * sum(log.(1 .- eigenvalues[i:end]))
        max_eigen_stats[i] = -n_eff * log(1 - eigenvalues[i])
    end

    # 使用 MacKinnon (2010) 响应面近似计算临界值
    significance_levels = [0.01, 0.05, 0.10]

    critical_values_trace = Dict{Float64, Vector{Float64}}()
    critical_values_max = Dict{Float64, Vector{Float64}}()

    for p in significance_levels
        cv_trace = Float64[]
        cv_max = Float64[]
        for i in 1:k
            push!(cv_trace, _johansen_critical_value(i, n_eff, p,
                  test_type=:trace, deterministic=deterministic))
            push!(cv_max, _johansen_critical_value(i, n_eff, p,
                  test_type=:max_eigenvalue, deterministic=deterministic))
        end
        critical_values_trace[p] = cv_trace
        critical_values_max[p] = cv_max
    end

    return (
        trace_stats=trace_stats,
        max_eigen_stats=max_eigen_stats,
        critical_values_trace=critical_values_trace,
        critical_values_max=critical_values_max,
        eigenvectors=eigenvectors,
        eigenvalues=eigenvalues
    )
end

# === fit 方法 =============================================================

"""
    fit(model::CointegrationModel, data::DataFrame) -> CointegrationFitResult

执行协整检验。
"""
function MetricaBase.fit(model::CointegrationModel, data::DataFrame)
    # 排序数据
    data_sorted = sort_by_time(data, model.time_column)

    # 提取变量
    n_vars = length(model.variables)
    Y = Matrix{Float64}(data_sorted[!, model.variables])
    n = size(Y, 1)

    warnings = MetricaBase.ModelWarning[]

    if model.method === :engle_granger
        # Engle-Granger 两步法
        y = Y[:, 1]
        X = Y[:, 2:end]

        result = engle_granger_test(y, X, deterministic=model.deterministic, lags=model.lags)

        # 判断协整关系数
        n_cointegrating = result.p_value < 0.05 ? 1 : 0

        # 构建 glance 表
        glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
            :test_statistic => result.test_statistic,
            :p_value => result.p_value,
            :n_cointegrating => n_cointegrating,
            :nobs => n,
        )

        glance_table = MetricaBase.ModelGlance(
            Symbol("Engle-Granger"),
            n,
            0,
            glance_metrics,
            MetricaBase.ModelWarning[]
        )

        # 构建 tidy 表
        coef_rows = MetricaBase.CoefRow[]
        if !isnothing(result.cointegrating_vector)
            for (i, var_name) in enumerate(model.variables)
                push!(coef_rows, MetricaBase.CoefRow(
                    Symbol(var_name),
                    result.cointegrating_vector[i],
                    nothing, nothing, nothing
                ))
            end
        end

        tidy_table = MetricaBase.TidyTable(coef_rows, "cointegrating_vector")

        return CointegrationFitResult(
            string.(model.variables),
            model.method,
            result.test_statistic,
            result.p_value,
            result.critical_values,
            result.cointegrating_vector,
            n_cointegrating,
            result.residuals,
            nothing, nothing, nothing,
            glance_table,
            tidy_table,
            warnings
        )

    elseif model.method === :johansen
        # Johansen 检验
        result = johansen_test(Y, lags=model.lags, deterministic=model.deterministic)

        # 判断协整关系数（迹检验）
        # 迹检验：H₀: r ≤ i vs H₁: r > i
        # 如果迹统计量 > 临界值，拒绝 H₀，继续检验
        n_cointegrating = 0
        for i in 1:n_vars
            cv = result.critical_values_trace[0.05][i]
            if result.trace_stats[i] > cv
                n_cointegrating += 1
            else
                break
            end
        end

        # 构建 glance 表
        glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
            :trace_stat_1 => result.trace_stats[1],
            :max_eigen_stat_1 => result.max_eigen_stats[1],
            :n_cointegrating => n_cointegrating,
            :nobs => n,
        )

        glance_table = MetricaBase.ModelGlance(
            Symbol("Johansen"),
            n,
            0,
            glance_metrics,
            MetricaBase.ModelWarning[]
        )

        # 构建 tidy 表（特征向量）
        coef_rows = MetricaBase.CoefRow[]
        for (i, var_name) in enumerate(model.variables)
            for j in 1:n_vars
                push!(coef_rows, MetricaBase.CoefRow(
                    Symbol("$(var_name)_vec$j"),
                    result.eigenvectors[i, j],
                    nothing, nothing, nothing
                ))
            end
        end

        tidy_table = MetricaBase.TidyTable(coef_rows, "eigenvectors")

        return CointegrationFitResult(
            string.(model.variables),
            model.method,
            result.trace_stats[1],
            0.0,
            Dict{Float64, Float64}(),
            result.eigenvectors[:, 1],
            n_cointegrating,
            nothing,
            result.eigenvalues,
            result.trace_stats,
            result.max_eigen_stats,
            glance_table,
            tidy_table,
            warnings
        )

    else
        error("未知的协整检验方法: $(model.method)")
    end
end

# === 协议方法 =============================================================

function MetricaBase.glance(result::CointegrationFitResult)
    return result.glance_table
end

function MetricaBase.tidy(result::CointegrationFitResult)
    return result.tidy_table
end

function MetricaBase.nobs(result::CointegrationFitResult)
    return result.glance_table.nobs
end

function MetricaBase.coef(result::CointegrationFitResult)
    if !isnothing(result.cointegrating_vector)
        return result.cointegrating_vector
    end
    return Float64[]
end

function MetricaBase.augment(result::CointegrationFitResult)
    if isnothing(result.residuals)
        return MetricaBase.AugmentTable(Dict{Symbol, Any}(), 0)
    end

    n = length(result.residuals)
    return MetricaBase.AugmentTable(
        Dict(
            :observation => collect(1.0:n),
            :residual => result.residuals,
        ),
        n
    )
end

# === 序列化支持 ===========================================================

function result_to_payload(result::CointegrationFitResult; include_augment::Bool=true)
    payload = Dict{String, Any}(
        "model_type" => "cointegration",
        "variables" => result.variable_names,
        "method" => string(result.method),
        "test_statistic" => result.test_statistic,
        "p_value" => result.p_value,
        "critical_values" => Dict(string(k) => v for (k, v) in result.critical_values),
        "n_cointegrating_relations" => result.n_cointegrating_relations,
    )

    if !isnothing(result.cointegrating_vector)
        payload["cointegrating_vector"] = result.cointegrating_vector
    end

    if !isnothing(result.eigenvalues)
        payload["eigenvalues"] = result.eigenvalues
    end

    if !isnothing(result.trace_stats)
        payload["trace_stats"] = result.trace_stats
    end

    if !isnothing(result.max_eigen_stats)
        payload["max_eigen_stats"] = result.max_eigen_stats
    end

    payload["glance"] = Dict(
        "model" => string(result.glance_table.model),
        "nobs" => result.glance_table.nobs,
        "metrics" => Dict(string(k) => v for (k, v) in result.glance_table.metrics)
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
