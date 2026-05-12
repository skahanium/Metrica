# === Driscoll-Kraay 面板稳健协方差 ===========================================
# 处理截面相关 + 异方差 + 时序自相关

"""
    compute_dk_vcov(residuals, X, panel_data; bandwidth=nothing)

计算 Driscoll-Kraay 面板稳健协方差矩阵。

处理截面相关 + 异方差 + 时序自相关。`bandwidth` 为 Newey-West 核带宽，
默认为 floor(4 * (T/100)^(2/9))。

返回 `(vcov_matrix, stderror)` 或 `ModelError`。
"""
function compute_dk_vcov(residuals::Vector{Float64}, X::Matrix{Float64},
                         panel_data::MetricaBase.PanelData;
                         bandwidth::Union{Nothing,Int}=nothing)
    data = DataFrame(panel_data.data)
    time_col = panel_data.time_col

    nobs = length(residuals)
    k = size(X, 2)

    # 按时间期分组计算得分向量 g_t = X_t' * e_t
    unique_times = sort(unique(data[!, time_col]))
    T = length(unique_times)

    isnothing(bandwidth) && (bandwidth = max(0, floor(Int, 4 * (T / 100)^(2/9))))

    # 构建时间期映射
    time_index = Dict(t => i for (i, t) in enumerate(unique_times))

    # 计算每个时间期的得分向量（期内求和，不取平均）
    scores = zeros(T, k)
    for i in 1:nobs
        t_val = data[i, time_col]
        t_idx = time_index[t_val]
        scores[t_idx, :] .+= X[i, :] .* residuals[i]
    end

    # 计算得分均值
    g_bar = vec(mean(scores, dims=1))

    # 计算 Newey-West 加权的 S 矩阵
    S = zeros(k, k)
    for t in 1:T
        g_dev = scores[t, :] .- g_bar
        S .+= g_dev * g_dev'
    end

    for l in 1:bandwidth
        weight = 1.0 - l / (bandwidth + 1)  # Bartlett 核
        for t in (l+1):T
            g_dev_t = scores[t, :] .- g_bar
            g_dev_lag = scores[t-l, :] .- g_bar
            S .+= weight * (g_dev_t * g_dev_lag' + g_dev_lag * g_dev_t')
        end
    end

    # DK 协方差 = (X'X)^{-1} * S * (X'X)^{-1} / T^2
    XtX = X' * X
    XtX_inv = try
        inv(XtX)
    catch
        return MetricaBase.ModelError(:singular_xtx, "X'X 奇异",
            "设计矩阵 X'X 不可逆，无法计算 DK 协方差。",
            "请检查是否存在完全共线性。")
    end

    # 规模修正因子：得分使用期内求和，故除以 T^2
    scale = 1.0 / (T * T)
    vcov_matrix = scale .* (XtX_inv * S * XtX_inv)
    std_errors = sqrt.(max.(diag(vcov_matrix), 0.0))

    return vcov_matrix, std_errors
end

"""
    compute_iv_dk_vcov(residuals, X, Z, panel_data; bandwidth=nothing)

计算面板 IV 模型的 Driscoll-Kraay 协方差矩阵。

`X` 为第二阶段设计矩阵（含拟合值），`Z` 为工具变量矩阵。
"""
function compute_iv_dk_vcov(residuals::Vector{Float64}, X::Matrix{Float64},
                            Z::Matrix{Float64}, panel_data::MetricaBase.PanelData;
                            bandwidth::Union{Nothing,Int}=nothing)
    data = DataFrame(panel_data.data)
    time_col = panel_data.time_col

    nobs = length(residuals)
    k = size(X, 2)

    unique_times = sort(unique(data[!, time_col]))
    T = length(unique_times)
    isnothing(bandwidth) && (bandwidth = max(0, floor(Int, 4 * (T / 100)^(2/9))))

    time_index = Dict(t => i for (i, t) in enumerate(unique_times))

    # 得分：g_t = Σ_i Z_it * e_it（期内求和，不取平均）
    p = size(Z, 2)
    scores = zeros(T, p)
    for i in 1:nobs
        t_val = data[i, time_col]
        t_idx = time_index[t_val]
        scores[t_idx, :] .+= Z[i, :] .* residuals[i]
    end

    g_bar = vec(mean(scores, dims=1))

    S = zeros(p, p)
    for t in 1:T
        g_dev = scores[t, :] .- g_bar
        S .+= g_dev * g_dev'
    end
    for l in 1:bandwidth
        weight = 1.0 - l / (bandwidth + 1)
        for t in (l+1):T
            g_dev_t = scores[t, :] .- g_bar
            g_dev_lag = scores[t-l, :] .- g_bar
            S .+= weight * (g_dev_t * g_dev_lag' + g_dev_lag * g_dev_t')
        end
    end

    # IV-DK: (X'Z (Z'Z)^{-1} Z'X)^{-1} * bread * S * bread' * (X'Z (Z'Z)^{-1} Z'X)^{-1}
    ZtZ = Z' * Z
    ZtZ_inv = try inv(ZtZ) catch
        return MetricaBase.ModelError(:singular_ztz, "Z'Z 奇异", "工具变量矩阵 Z'Z 不可逆。", "请检查工具变量。")
    end
    XZ = X' * Z
    ZX = Z' * X
    bread = inv(XZ * ZtZ_inv * ZX)

    # 规模修正因子：得分使用期内求和，故除以 T^2
    scale = 1.0 / (T * T)
    vcov_matrix = scale .* (bread * (XZ * ZtZ_inv * S * ZtZ_inv * ZX) * bread)
    std_errors = sqrt.(max.(diag(vcov_matrix), 0.0))

    return vcov_matrix, std_errors
end
