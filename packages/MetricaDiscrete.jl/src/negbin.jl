# === 负二项回归 ==============================================================

function nb_loglikelihood(y::Vector{Float64}, μ::Vector{Float64}, α::Float64)
    ll = 0.0
    inv_α = 1.0 / α
    for i in eachindex(y)
        yi = y[i]
        μi = max(μ[i], 1e-10)
        ll += loggamma(yi + inv_α) - loggamma(inv_α) - loggamma(yi + 1) +
              yi * log(α * μi) - (yi + inv_α) * log(1 + α * μi)
    end
    return ll
end

function MetricaBase.fit(::Type{NegBinModel}, formula::AbstractString, data;
                          vcov::Symbol=:classical, cluster_column::Union{Nothing,Symbol,String}=nothing)
    dataset = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula
    model_columns = MetricaLinear.collect_term_symbols(model_formula)
    err = MetricaLinear.validate_model_columns(dataset, model_columns, nothing, cluster_column)
    err isa MetricaBase.ModelError && return err

    prepared = MetricaLinear.prepare_model_data(
        dataset, model_formula, model_columns, nothing,
        isnothing(cluster_column) ? nothing : Symbol(cluster_column),
    )
    prepared isa MetricaBase.ModelError && return prepared

    (_, model_frame, _, X, y, _, _, n_total, n_effective) = prepared
    nobs = length(y)
    ncoef = size(X, 2)

    if any(y .< 0)
        return MetricaBase.ModelError(:invalid_count_response, "负二项回归要求响应变量为非负整数。", "", "")
    end

    err = MetricaLinear.validate_design(X, ncoef, nobs)
    err isa MetricaBase.ModelError && return err

    # 步骤 1：Poisson 初值
    poisson_result = MetricaBase.fit(PoissonModel, formula, data)
    poisson_result isa MetricaBase.ModelError && return poisson_result
    β_init = poisson_result.coefficient_values

    # 步骤 2：矩估计 α₀
    μ_init = max.(exp.(X * β_init), 1e-10)
    residual_var = mean((y .- μ_init).^2)
    mean_var = mean(μ_init)
    α_init = max((residual_var - mean_var) / max(mean_var^2, 1e-10), 0.1)

    # 步骤 3：用 Optim.jl Brent 一维优化器估计 α（profile likelihood）
    total_iterations = 0
    irls_converged = false

    function profile_negloglik(α_try::Float64)
        α_try = max(α_try, 1e-6)
        β = copy(β_init)
        for iter in 1:50
            total_iterations += 1
            μ = max.(exp.(X * β), 1e-10)
            var_nb = μ .+ α_try .* μ.^2
            w = μ.^2 ./ max.(var_nb, 1e-10)
            z = log.(μ) .+ (y .- μ) ./ max.(μ, 1e-10)
            Xw = X .* sqrt.(w)
            zw = z .* sqrt.(w)
            β_new = Xw \ zw
            if norm(β_new - β) / (norm(β) + 1e-8) < 1e-8
                irls_converged = true
                break
            end
            β = β_new
        end
        μ_final = max.(exp.(X * β), 1e-10)
        return -nb_loglikelihood(y, μ_final, α_try)
    end

    α_lo = max(α_init * 0.01, 1e-6)
    α_hi = α_init * 20.0
    opt_result = Optim.optimize(profile_negloglik, α_lo, α_hi, Optim.Brent())
    α = max(Optim.minimizer(opt_result), 1e-6)

    # 用最优 α 重新拟合 β
    coefficients = copy(β_init)
    for iter in 1:50
        μ = max.(exp.(X * coefficients), 1e-10)
        var_nb = μ .+ α .* μ.^2
        w = μ.^2 ./ max.(var_nb, 1e-10)
        z = log.(μ) .+ (y .- μ) ./ max.(μ, 1e-10)
        Xw = X .* sqrt.(w)
        zw = z .* sqrt.(w)
        β_new = Xw \ zw
        if norm(β_new - coefficients) / (norm(coefficients) + 1e-8) < 1e-8
            coefficients = β_new
            break
        end
        coefficients = β_new
    end
    μ_final = max.(exp.(X * coefficients), 1e-10)
    best_ll = nb_loglikelihood(y, μ_final, α)

    # VCov via Fisher info (simplified)
    w_final = μ_final ./ (1.0 .+ α .* μ_final)
    Xw = X .* sqrt.(w_final)
    hessian = Xw' * Xw
    hessian = (hessian + hessian') ./ 2
    vcov_matrix = try inv(hessian) catch; pinv(hessian) end
    se_values = sqrt.(max.(diag(vcov_matrix), 0.0))
    coefficient_names = Symbol.(StatsModels.coefnames(model_frame))

    dof = nobs - ncoef - 1
    loglik = best_ll
    aic = 2 * (ncoef + 1) - 2 * loglik
    bic = (ncoef + 1) * log(nobs) - 2 * loglik
    z_stats = coefficients ./ se_values
    pvalues = 2 .* (1 .- cdf.(Normal(), abs.(z_stats)))

    α_ci = 0.05
    z_crit = quantile(Normal(), 1 - α_ci / 2)

    null_ll = nb_loglikelihood(y, fill(mean(y), nobs), α)
    pseudo_r2 = 1 - (-loglik) / max(-null_ll, 1e-10)

    lr_chi2 = 2 * (loglik - null_ll)
    lr_pvalue = 1 - cdf(Chisq(ncoef), lr_chi2)

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, MetricaLinear.build_rows_dropped_warning(dropped_rows))

    if α < 0.01
        push!(warnings, MetricaBase.ModelWarning(
            :near_poisson, "过度分散参数接近 0",
            "α = $(round(α, digits=4)) 很小，负二项回归可能退化为 Poisson 回归。",
            "请检查是否确实存在过度分散。",
            MetricaBase.info,
        ))
    end

    glance_table = MetricaBase.ModelGlance(
        :negbin, nobs, dof,
        Dict{Symbol, MetricaBase.MetricValue}(
            :pseudo_r2 => pseudo_r2, :loglik => loglik, :aic => aic, :bic => bic,
            :dispersion => α, :lr_chi2 => lr_chi2, :lr_pvalue => lr_pvalue,
        ),
        warnings,
    )

    tidy_rows = [MetricaBase.CoefRow(coefficient_names[i], coefficients[i], se_values[i], z_stats[i], pvalues[i], coefficients[i] - z_crit * se_values[i], coefficients[i] + z_crit * se_values[i]) for i in 1:ncoef]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "MLE (profile likelihood)")

    return NegBinFitResult(
        String(formula), glance_table, tidy_table,
        Matrix{Float64}(X), y, μ_final, log.(μ_final),
        coefficient_names, coefficients, vcov_matrix, se_values,
        α, -2.0 * loglik, loglik, total_iterations, irls_converged,
    )
end

MetricaBase.glance(result::NegBinFitResult) = result.glance_table
MetricaBase.tidy(result::NegBinFitResult) = result.tidy_table
MetricaBase.coef(result::NegBinFitResult) = result.coefficient_names .=> result.coefficient_values
MetricaBase.vcov(result::NegBinFitResult) = result.vcov_matrix
MetricaBase.stderror(result::NegBinFitResult) = result.stderror_values
MetricaBase.nobs(result::NegBinFitResult) = length(result.response_vector)
MetricaBase.dof(result::NegBinFitResult) = result.glance_table.dof
MetricaBase.r2(result::NegBinFitResult) = result.glance_table.metrics[:pseudo_r2]
MetricaBase.fitted(result::NegBinFitResult) = result.fitted_values
MetricaBase.residuals(result::NegBinFitResult) = result.response_vector - result.fitted_values

function MetricaBase.augment(result::NegBinFitResult)
    n = length(result.response_vector)
    residuals = result.response_vector - result.fitted_values
    var_values = result.fitted_values .+ result.dispersion .* result.fitted_values.^2
    pearson = residuals ./ sqrt.(max.(var_values, 1e-10))
    return MetricaBase.AugmentTable(
        Dict(:observation => collect(1.0:n), :fitted => result.fitted_values, :residual => residuals, :pearson_residual => pearson), n,
    )
end

function MetricaBase.predict(result::NegBinFitResult; newdata=nothing, interval=:none, level=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    η = X * result.coefficient_values
    λ = exp.(η)
    interval === :none && return λ
    se_eta = [sqrt(X[i, :]' * result.vcov_matrix * X[i, :]) for i in 1:size(X, 1)]
    z_crit = quantile(Normal(), 1 - (1 - level) / 2)
    return (predictions=λ, lower=exp.(η .- z_crit .* se_eta), upper=exp.(η .+ z_crit .* se_eta))
end
