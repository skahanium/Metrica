# sdm_fit.jl — 空间杜宾模型 (Spatial Durbin Model)
# y = ρWy + Xβ + WX̃θ + ε, X̃ = X[:, 2:end] (不含截距列)

function _remove_collinear_columns(Z::Matrix{Float64})
    Q, R = qr(Z)
    diag_R = abs.(diag(R))
    max_R = maximum(diag_R)
    rank_Z = sum(diag_R .> 1e-10 * max_R)
    if rank_Z >= size(Z, 2)
        return Z
    end
    return Z[:, 1:rank_Z]
end

function _hc1_se(X::Matrix{Float64}, resid::Vector{Float64}, n::Int)
    XpX_inv = inv(X' * X)
    meat = X' * Diagonal(resid.^2) * X
    V = Symmetric(XpX_inv * meat * XpX_inv * (n / (n - size(X, 2))))
    return sqrt.(max.(diag(V), 0.0))
end

function fit_sdm_2sls(y::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64},
                       colnames::Vector{Symbol};
                       vcov_kind::Symbol=:classical)
    n = length(y)
    p = size(X, 2)
    p < 2 && return MetricaBase.ModelError(:sdm_no_predictors,
        "SDM 需要至少一个非截距解释变量", "", "")

    X_tilde = X[:, 2:end]             # 不含截距
    WX_tilde = W * X_tilde            # 空间滞后解释变量
    X_aug = hcat(X, WX_tilde)         # 增广设计矩阵
    p_tilde = size(X_tilde, 2)

    Wy = W * y

    # 工具: Z = [X, WX, W²X] 剔除共线列
    Z = _remove_collinear_columns(hcat(X, W * X, W * W * X))

    # 2SLS
    Pz = Z * pinv(Z' * Z) * Z'
    Wy_hat = Pz * Wy

    X_endo = hcat(Wy_hat, X_aug)
    beta_hat = X_endo \ y

    rho_hat = beta_hat[1]
    beta_x = beta_hat[2:(p+1)]
    theta_hat = beta_hat[(p+2):end]

    fitted = hcat(Wy, X_aug) * beta_hat
    resid = y - fitted
    rss = dot(resid, resid)
    total_params = 1 + p + p_tilde
    sigma2 = rss / (n - total_params)

    # 系数名称
    coef_names = vcat([:rho], colnames, [Symbol("W_$(c)") for c in colnames[2:end]])
    coef_vals = vcat([rho_hat], beta_x, theta_hat)

    # 标准误
    Xe = hcat(Wy, X_aug)
    XpX_inv = inv(Xe' * Xe)
    if vcov_kind == :classical
        se = sqrt.(max.(diag(XpX_inv) .* sigma2, 0.0))
    elseif vcov_kind == :HC1
        se = _hc1_se(Xe, resid, n)
    else
        return MetricaBase.ModelError(:sdm_unknown_vcov, "SDM 不支持 vcov=$vcov_kind", "", "")
    end

    coef_pairs = [coef_names[i] => coef_vals[i] for i in eachindex(coef_names)]
    return (coef_pairs, se, fitted, resid, rho_hat, theta_hat)
end
