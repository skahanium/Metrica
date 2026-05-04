# === 边际效应 =================================================================

"""
    ame(result, data::DataFrame)

计算平均边际效应（Average Marginal Effects）。

对每个观测计算 ∂P(y=1)/∂x，然后取平均。Logit 的闭式导数：∂p/∂x_j = p*(1-p)*β_j。
标准误用 Delta 法。
"""
function ame(result::LogitFitResult, data::DataFrame)
    coefficient_names = result.coefficient_names
    ncoef = length(coefficient_names)
    X = result.design_matrix
    β = result.coefficient_values
    V = result.vcov_matrix
    nobs = size(X, 1)

    ame_values = zeros(ncoef)
    ame_se = zeros(ncoef)

    for j in 1:ncoef
        η = X * β
        p = 1.0 ./ (1.0 .+ exp.(-η))
        dp_dxj = p .* (1.0 .- p) .* β[j]
        ame_values[j] = mean(dp_dxj)

        # Delta 法 SE：梯度平均
        grad = zeros(ncoef)
        for i in 1:nobs
            p_i = p[i]
            dp_i = p_i * (1.0 - p_i)
            grad[j] += dp_i / nobs
            for k in 1:ncoef
                if k != j
                    grad[k] += dp_i * X[i, k] * (1.0 - 2.0 * p_i) * β[j] / nobs
                else
                    grad[k] += dp_i * (1.0 + X[i, k] * (1.0 - 2.0 * p_i) * β[j]) / nobs
                end
            end
        end
        ame_se[j] = sqrt(max(grad' * V * grad, 0.0))
    end

    z_stats = ame_values ./ ame_se
    pvalues = 2 .* (1 .- cdf.(Normal(), abs.(z_stats)))

    return MetricaBase.TidyTable(
        [MetricaBase.CoefRow(coefficient_names[i], ame_values[i], ame_se[i], z_stats[i], pvalues[i]) for i in 1:ncoef],
        "AME (Delta method)",
    )
end

"""
    mem(result, data::DataFrame)

计算均值处边际效应（Marginal Effects at the Mean）。
"""
function mem(result::LogitFitResult, data::DataFrame)
    X = result.design_matrix
    β = result.coefficient_values
    V = result.vcov_matrix
    ncoef = length(β)

    X_mean = vec(mean(X, dims=1))
    η_mean = dot(X_mean, β)
    p_mean = 1.0 / (1.0 + exp(-η_mean))

    mem_values = p_mean .* (1.0 - p_mean) .* β
    dp_dβ = p_mean * (1.0 - p_mean) * (Matrix{Float64}(I, ncoef, ncoef) .+ (1.0 - 2.0 * p_mean) * β * X_mean')
    mem_se = sqrt.(max.(diag(dp_dβ * V * dp_dβ'), 0.0))

    z_stats = mem_values ./ mem_se
    pvalues = 2 .* (1 .- cdf.(Normal(), abs.(z_stats)))

    return MetricaBase.TidyTable(
        [MetricaBase.CoefRow(result.coefficient_names[i], mem_values[i], mem_se[i], z_stats[i], pvalues[i]) for i in 1:ncoef],
        "MEM (Delta method)",
    )
end

# === Probit 边际效应 =========================================================

"""
Probit AME: ∂p/∂x_j = φ(Xβ) * β_j

φ 是标准正态密度函数。
"""
function ame(result::ProbitFitResult, data::DataFrame)
    X = result.design_matrix
    β = result.coefficient_values
    V = result.vcov_matrix
    ncoef = length(β)
    nobs = size(X, 1)

    η = X * β
    φ = pdf.(Normal(), η)

    ame_values = zeros(ncoef)
    ame_se = zeros(ncoef)

    for j in 1:ncoef
        dp_dxj = φ .* β[j]
        ame_values[j] = mean(dp_dxj)

        # Delta 法 SE
        grad = zeros(ncoef)
        for i in 1:nobs
            φ_i = φ[i]
            η_i = η[i]
            dφ_dη = -η_i * φ_i  # derivative of φ(η)
            for k in 1:ncoef
                if k != j
                    grad[k] += β[j] * dφ_dη * X[i, k] / nobs
                else
                    grad[k] += (φ_i + β[j] * dφ_dη * X[i, k]) / nobs
                end
            end
        end
        ame_se[j] = sqrt(max(grad' * V * grad, 0.0))
    end

    z_stats = ame_values ./ ame_se
    pvalues = 2 .* (1 .- cdf.(Normal(), abs.(z_stats)))
    return MetricaBase.TidyTable(
        [MetricaBase.CoefRow(result.coefficient_names[i], ame_values[i], ame_se[i], z_stats[i], pvalues[i]) for i in 1:ncoef],
        "AME (Probit, Delta method)",
    )
end

function mem(result::ProbitFitResult, data::DataFrame)
    X = result.design_matrix
    β = result.coefficient_values
    V = result.vcov_matrix
    ncoef = length(β)

    X_mean = vec(mean(X, dims=1))
    η_mean = dot(X_mean, β)
    φ_mean = pdf(Normal(), η_mean)

    mem_values = φ_mean .* β
    dφ_dη = -η_mean * φ_mean
    dp_dβ = φ_mean * Matrix{Float64}(I, ncoef, ncoef) .+ dφ_dη * β * X_mean'
    mem_se = sqrt.(max.(diag(dp_dβ * V * dp_dβ'), 0.0))

    z_stats = mem_values ./ mem_se
    pvalues = 2 .* (1 .- cdf.(Normal(), abs.(z_stats)))
    return MetricaBase.TidyTable(
        [MetricaBase.CoefRow(result.coefficient_names[i], mem_values[i], mem_se[i], z_stats[i], pvalues[i]) for i in 1:ncoef],
        "MEM (Probit, Delta method)",
    )
end
