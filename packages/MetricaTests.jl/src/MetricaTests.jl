module MetricaTests

using Distributions
using LinearAlgebra
using Statistics
using MetricaLinear

export vif, breusch_pagan

function is_intercept_name(name::Symbol)
    normalized = lowercase(String(name))
    return normalized == "intercept" || normalized == "(intercept)"
end

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

end
