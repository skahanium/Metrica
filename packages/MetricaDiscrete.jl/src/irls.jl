# === IRLS 通用求解器 =========================================================

struct IRLSResult
    coefficients::Vector{Float64}
    vcov::Matrix{Float64}
    fitted_values::Vector{Float64}
    linear_predictor::Vector{Float64}
    working_residuals::Vector{Float64}
    deviance::Float64
    loglikelihood::Float64
    iterations::Int
    converged::Bool
end

"""
    irls(X::Matrix{Float64}, y::Vector{Float64}, link::Link;
         max_iter=25, tol=1e-8, offset=zeros(length(y)))

通过 IRLS 迭代拟合 GLM。返回 IRLSResult 或 ModelError。
"""
function irls(
    X::Matrix{Float64}, y::Vector{Float64}, link::Link;
    max_iter::Int=25, tol::Float64=1e-8, offset::Vector{Float64}=zeros(length(y))
)
    nobs, p = size(X)

    # 初始化
    μ = clamp.(copy(y), 0.05, 0.95)
    β = zeros(p)

    for iter in 1:max_iter
        η = link.linkinv(μ) .+ offset
        dμ_dη = link.mu_eta(μ)
        working_var = link.variance(μ)
        z = η .+ (y .- μ) ./ max.(dμ_dη, 1e-10)

        w = dμ_dη .^ 2 ./ max.(working_var, 1e-10)
        w_sqrt = sqrt.(w)

        Xw = X .* w_sqrt
        zw = z .* w_sqrt
        β_new = Xw \ zw

        η_new = X * β_new .+ offset
        μ_new = link.linkfun(η_new)
        μ_new = clamp.(μ_new, 1e-10, 1.0 - 1e-10)

        β_change = norm(β_new - β) / (norm(β) + tol)
        β = β_new
        μ = μ_new

        if β_change < tol
            η_final = X * β .+ offset
            μ_final = link.linkfun(η_final)
            μ_final = clamp.(μ_final, 1e-10, 1.0 - 1e-10)

            dμ_dη_final = link.mu_eta(μ_final)
            working_var_final = link.variance(μ_final)
            w_final = dμ_dη_final .^ 2 ./ max.(working_var_final, 1e-10)

            Xw_final = X .* sqrt.(w_final)
            hessian = Xw_final' * Xw_final
            hessian = (hessian + hessian') ./ 2

            vcov = try
                inv(hessian)
            catch
                pinv(hessian)
            end

            deviance = compute_deviance(y, μ_final, link)
            loglik = compute_loglikelihood(y, μ_final, link)
            working_residuals = (y .- μ_final) ./ max.(dμ_dη_final, 1e-10)

            return IRLSResult(
                β, vcov, μ_final, η_final,
                working_residuals, deviance, loglik, iter, true,
            )
        end
    end

    return MetricaBase.ModelError(
        :irls_not_converged,
        "IRLS 未收敛",
        "IRLS 在 $(max_iter) 次迭代后仍未收敛。",
        "请检查数据中是否存在完全分离、过度分散或其他数值问题。",
    )
end

function compute_deviance(y::Vector{Float64}, μ::Vector{Float64}, link::Link)
    if link.name == :logit || link.name == :probit
        d = 0.0
        for i in eachindex(y)
            if y[i] > 0 && y[i] < 1
                d += 2 * (y[i] * log(y[i] / μ[i]) + (1 - y[i]) * log((1 - y[i]) / (1 - μ[i])))
            elseif y[i] == 0
                d += -2 * log(1 - μ[i])
            elseif y[i] == 1
                d += -2 * log(μ[i])
            end
        end
        return d
    elseif link.name == :log
        d = 0.0
        for i in eachindex(y)
            if y[i] > 0
                d += 2 * (y[i] * log(y[i] / μ[i]) - (y[i] - μ[i]))
            else
                d += 2 * μ[i]
            end
        end
        return d
    else
        return NaN
    end
end

function compute_loglikelihood(y::Vector{Float64}, μ::Vector{Float64}, link::Link)
    if link.name == :logit || link.name == :probit
        return loglikelihood_bernoulli(y, μ)
    elseif link.name == :log
        return loglikelihood_poisson(y, μ)
    else
        return NaN
    end
end

function loglikelihood_bernoulli(y::Vector{Float64}, μ::Vector{Float64})
    ll = 0.0
    for i in eachindex(y)
        μ_i = clamp(μ[i], 1e-15, 1.0 - 1e-15)
        if y[i] == 1.0
            ll += log(μ_i)
        else
            ll += log(1.0 - μ_i)
        end
    end
    return ll
end

function loglikelihood_poisson(y::Vector{Float64}, μ::Vector{Float64})
    ll = 0.0
    for i in eachindex(y)
        μ_i = max(μ[i], 1e-15)
        ll += y[i] * log(μ_i) - μ_i  # omit -log(y_i!) constant
    end
    return ll
end

function null_loglikelihood_bernoulli(y::Vector{Float64})
    ybar = mean(y)
    ybar = clamp(ybar, 1e-15, 1.0 - 1e-15)
    n = length(y)
    return sum(y) * log(ybar) + (n - sum(y)) * log(1.0 - ybar)
end

function null_loglikelihood_poisson(y::Vector{Float64})
    ybar = mean(y)
    if ybar == 0
        return 0.0
    end
    ll = 0.0
    for yi in y
        ll += yi > 0 ? yi * log(ybar) - ybar : -ybar
    end
    return ll
end
