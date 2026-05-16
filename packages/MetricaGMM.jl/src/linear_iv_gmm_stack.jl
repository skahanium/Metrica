# === 线性 IV-GMM 堆叠估计（无公式层，供动态面板等内部复用）=====================

"""
    linear_iv_gmm_stack(y, X, Z; gmm_weight=:two_step)

对已对齐的堆叠数据执行线性 IV-GMM（一步或两步稳健最优权重），数值管线与
`GMMLinearModel` 一致，但不计算第一阶段 F 或弱工具诊断。

- `y`：n×1 响应；`X`：n×k 结构回归元（若需截距须由调用方显式加入列）；
- `Z`：n×L 工具矩阵。

成功时返回 `NamedTuple`，含 `coef`、`vcov`、`stderror`、`residual`、`j_statistic`、
`j_df`、`j_pvalue`、`n_moments`、`n_params`、`weight_matrix_description`、`iterations`。
失败时返回 `ModelError`。
"""
function linear_iv_gmm_stack(
    y::Vector{Float64},
    X::Matrix{Float64},
    Z::Matrix{Float64};
    gmm_weight::Symbol = :two_step,
)
    nobs = length(y)
    if size(X, 1) != nobs || size(Z, 1) != nobs
        return MetricaBase.ModelError(
            :dimension_mismatch,
            "堆叠矩阵行数不一致",
            "y、X、Z 的行数必须相同。",
            "请检查差分样本与工具矩阵装配。",
        )
    end
    k = size(X, 2)
    L = size(Z, 2)
    if L < k
        return MetricaBase.ModelError(
            :underidentified_gmm,
            "模型欠识别",
            "矩条件数 L=$(L) 小于待估参数数 k=$(k)。",
            "请放宽工具滞后或增加时期深度。",
        )
    end

    if gmm_weight !== :one_step && gmm_weight !== :two_step
        return MetricaBase.ModelError(
            :invalid_gmm_weight,
            "不支持的 GMM 权重步长",
            "gmm_weight 只能为 :one_step 或 :two_step。",
            "请使用 one_step 或 two_step。",
        )
    end

    ZtZ = Z' * Z
    W = _inv_sym_pd(
        ZtZ,
        :singular_weight_matrix,
        "权重矩阵奇异",
        "一步 GMM 权重 (Z'Z)^{-1} 不可逆：",
        "请检查工具变量是否完全共线或样本量是否过小。",
    )
    W isa MetricaBase.ModelError && return W

    local W_final
    local β
    local u
    local iterations
    local weight_description

    if gmm_weight === :one_step || (gmm_weight === :two_step && L == k)
        W_final = W
        β = _solve_gmm_beta(X, Z, y, W_final)
        β isa MetricaBase.ModelError && return β
        u = y - X * β
        iterations = 1
        weight_description = if gmm_weight === :one_step
            "one_step: W = (Z'Z)^{-1}"
        else
            "two_step 请求在恰识别 (L=k) 下退化为一步权重：W = (Z'Z)^{-1}（稳健矩协方差 Ω̂ 不可逆，无法构造第二步最优权重）。"
        end
    else
        β1 = _solve_gmm_beta(X, Z, y, W)
        β1 isa MetricaBase.ModelError && return β1
        u1 = y - X * β1
        Ω = _moment_covariance(Z, u1, nobs)
        n_Ω = size(Ω, 1)
        jitter = 1e-10 * (tr(Ω) / max(n_Ω, 1) + 1e-12)
        Ωreg = Symmetric(Ω + jitter * I)
        W2 = _inv_sym_pd(
            Ωreg,
            :singular_weight_matrix,
            "权重矩阵奇异",
            "两步 GMM 的稳健矩协方差 Ω 不可逆：",
            "请检查矩条件共线性或第一阶段残差是否退化。",
        )
        W2 isa MetricaBase.ModelError && return W2
        iterations = 2
        weight_description = "two_step: W = Ω̂^{-1}，Ω̂ 为基于第一步残差的异方差稳健矩协方差 (Z'DZ)/n。"
        W_final = W2
        β = _solve_gmm_beta(X, Z, y, W_final)
        β isa MetricaBase.ModelError && return β
        u = y - X * β
    end

    Ω_hat = _moment_covariance(Z, u, nobs)
    vcov_mat = _gmm_vcov(X, Z, W_final, Ω_hat, nobs)
    vcov_mat isa MetricaBase.ModelError && return vcov_mat
    stderror = sqrt.(max.(0.0, diag(vcov_mat)))

    g = (Z' * u) ./ nobs
    j_stat = nobs * dot(g, W_final * g)
    overid_df = L - k
    j_pvalue = if overid_df > 0
        1 - cdf(Chisq(overid_df), j_stat)
    else
        nothing
    end

    return (
        coef = β,
        vcov = vcov_mat,
        stderror = stderror,
        residual = u,
        j_statistic = j_stat,
        j_df = overid_df,
        j_pvalue = j_pvalue,
        n_moments = L,
        n_params = k,
        weight_matrix_description = weight_description,
        iterations = iterations,
    )
end
