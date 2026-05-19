# sdem_fit.jl — 空间杜宾误差模型 (Spatial Durbin Error Model)
# y = Xβ + WX̃θ + u, u = λWu + ε

function fit_sdem_ml(y::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64},
                      colnames::Vector{Symbol})
    n = length(y)
    p = size(X, 2)
    p < 2 && return MetricaBase.ModelError(:sdem_no_predictors,
        "SDEM 需要至少一个非截距解释变量", "", "")
    n > 800 && return MetricaBase.ModelError(:sdem_too_large,
        "SDEM 当前限 n ≤ 800", "n=$n", "")

    X_tilde = X[:, 2:end]
    WX_tilde = W * X_tilde
    X_aug = hcat(X, WX_tilde)
    p_aug = size(X_aug, 2)

    function prof_ll(lambda::Float64)
        A = I - lambda * W
        ld = log(abs(det(A)))
        if !isfinite(ld)
            return -1e30
        end
        y_star = A * y
        X_star = A * X_aug
        try
            beta = X_star \ y_star
        catch
            return -1e30
        end
        resid = y_star - X_star * beta
        sigma2 = dot(resid, resid) / n
        sigma2 <= 0 && return -1e30
        return -n / 2 * log(2π) - n / 2 * log(sigma2) - dot(resid, resid) / (2 * sigma2) + ld
    end

    f(x) = -prof_ll(x[1])
    result = Optim.optimize(f, [-0.5, 0.5], Optim.NelderMead(),
                            Optim.Options(iterations=500, g_abstol=1e-6))
    lambda_hat = Optim.minimizer(result)[1]
    converged = Optim.converged(result)
    iters = Optim.iterations(result)

    A = I - lambda_hat * W
    y_star = A * y
    X_star = A * X_aug
    beta_hat = X_star \ y_star
    resid = y_star - X_star * beta_hat
    sigma2 = dot(resid, resid) / n

    XpX_inv = inv(X_star' * X_star)
    se_full = sqrt.(max.(diag(XpX_inv) .* sigma2, 0.0))

    coef_names = vcat(colnames, [Symbol("W_$(c)") for c in colnames[2:end]])
    coef_vals = beta_hat
    coef_pairs = [coef_names[i] => coef_vals[i] for i in eachindex(coef_names)]

    p_tilde = size(X_tilde, 2)
    k_total = p + p_tilde + 1
    loglik = prof_ll(lambda_hat)

    return (coef_pairs, se_full, y - resid, resid, lambda_hat, loglik)
end
