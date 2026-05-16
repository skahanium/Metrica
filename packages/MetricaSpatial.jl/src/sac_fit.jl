# sac_fit.jl — SAC/SARAR (Spatial Autoregressive Confused)
# y = ρWy + Xβ + u, u = λWu + ε
# 估计器：GS2SLS (Kelejian & Prucha 1998)

function fit_sac_gs2sls(y::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64},
                         colnames::Vector{Symbol})
    n = length(y)
    p = size(X, 2)
    n > 5000 && return MetricaBase.ModelError(:sac_too_large,
        "SAC 当前限 n ≤ 5000", "n=$n", "")

    # Step 1: 2SLS 估计 ρ 和 β
    Z = _remove_collinear_columns(hcat(X, W * X, W * W * X))
    Pz = Z * pinv(Z' * Z) * Z'
    Wy = W * y
    Wy_hat = Pz * Wy
    X_endo = hcat(Wy_hat, X)
    beta_step1 = X_endo \ y
    rho_hat = beta_step1[1]
    beta_hat = beta_step1[2:end]
    u_hat = y - rho_hat * Wy - X * beta_hat

    # Step 2: GMM 估计 λ
    Wu = W * u_hat
    num = dot(Wu, Wu)
    den = dot(Wu, W * u_hat)
    lambda_hat = den > 1e-12 ? num / den : 0.0

    # Step 3: FGLS 变换
    A = I - lambda_hat * W
    y_star = A * y
    Wy_star = W * y_star
    X_star = A * X

    Z_star = _remove_collinear_columns(hcat(X_star, W * X_star, W * W * X_star))
    Pz_star = Z_star * pinv(Z_star' * Z_star) * Z_star'
    Wy_star_hat = Pz_star * Wy_star
    X_endo_star = hcat(Wy_star_hat, X_star)
    beta_final = X_endo_star \ y_star

    rho_final = beta_final[1]
    beta_final_x = beta_final[2:end]

    fitted = rho_final * Wy + X * beta_final_x
    resid = y - fitted
    rss = dot(resid, resid)
    sigma2 = rss / (n - (1 + p))

    Xe = hcat(Wy, X)
    XpX_inv = inv(Xe' * Xe)
    se = sqrt.(max.(diag(XpX_inv) .* sigma2, 0.0))

    coef_names = vcat([:rho], colnames)
    coef_vals = vcat([rho_final], beta_final_x)
    coef_pairs = [coef_names[i] => coef_vals[i] for i in eachindex(coef_names)]

    return (coef_pairs, se, fitted, resid, rho_final, lambda_hat)
end
