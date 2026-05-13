# === 有序 Logit 模型 ==========================================================

"""
有序 Logit 对数似然。
P(Y ≤ j) = 1 / (1 + exp(-(τⱼ - Xβ)))
P(Y = j) = P(Y ≤ j) - P(Y ≤ j-1)
"""
function ologit_loglikelihood(X, y::Vector{Int}, β::Vector{Float64}, τ::Vector{Float64})
    n = size(X, 1)
    η = X * β
    ll = 0.0
    for i in 1:n
        yi = y[i]
        cumprob = [1.0 / (1.0 + exp(-(τ[j] - η[i]))) for j in 1:length(τ)]
        pushfirst!(cumprob, 0.0)
        push!(cumprob, 1.0)
        prob = cumprob[yi+1] - cumprob[yi]
        prob = clamp(prob, 1e-15, 1.0)
        ll += log(prob)
    end
    return ll
end

function ologit_thresholds(γ::Vector{Float64})
    τ = similar(γ)
    τ[1] = γ[1]
    for j in 2:length(γ)
        τ[j] = τ[j - 1] + exp(γ[j])
    end
    return τ
end

function ologit_threshold_params(τ::Vector{Float64})
    γ = similar(τ)
    γ[1] = τ[1]
    for j in 2:length(τ)
        γ[j] = log(max(τ[j] - τ[j - 1], 1e-8))
    end
    return γ
end

function MetricaBase.fit(::Type{OrderedLogitModel}, formula::AbstractString, data;
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

    (_, model_frame, _, X_raw, y, _, _, n_total, n_effective) = prepared
    raw_coefficient_names = Symbol.(StatsModels.coefnames(model_frame))
    keep_columns = findall(name -> name != Symbol("(Intercept)"), raw_coefficient_names)
    X = Matrix{Float64}(X_raw[:, keep_columns])
    coefficient_names = raw_coefficient_names[keep_columns]
    nobs = length(y)
    ncoef = size(X, 2)
    y_int = Int.(round.(y))

    categories = sort(unique(y_int))
    J = length(categories)
    if J < 3
        return MetricaBase.ModelError(:insufficient_categories, "有序 Logit 要求至少 3 个类别", "当前响应变量只有 $(J) 个类别。", "若有 2 个类别，请使用二分类 Logit。")
    end
    # 重映射类别到 1:J
    cat_to_idx = Dict(categories[i] => i for i in 1:J)
    y_idx = [cat_to_idx[yi] for yi in y_int]

    if ncoef > 0
        err = MetricaLinear.validate_design(X, ncoef, nobs)
        err isa MetricaBase.ModelError && return err
    end

    ntau = J - 1

    # 初始值
    β_init = ncoef == 0 ? Float64[] : X \ y
    β_init = ncoef == 0 ? β_init : β_init ./ max(norm(β_init) / 0.5, 1.0)
    τ_init = quantile.(Normal(), (1:ntau) ./ J)
    γ_init = ologit_threshold_params(Float64.(τ_init))

    # 负对数似然（转为最小化问题）
    function negll(θ)
        βθ = θ[1:ncoef]
        τθ = ologit_thresholds(θ[(ncoef+1):end])
        -ologit_loglikelihood(X, y_idx, βθ, τθ)
    end

    θ_init = vcat(β_init, γ_init)

    # 使用 Optim.jl L-BFGS 优化
    result = try
        Optim.optimize(negll, θ_init, Optim.LBFGS())
    catch e
        return MetricaBase.ModelError(:ologit_opt_error, "有序 Logit 优化失败", sprint(showerror, e), "请检查数据质量。")
    end

    converged = Optim.converged(result)
    θ_opt = Optim.minimizer(result)

    β = θ_opt[1:ncoef]
    τ = ologit_thresholds(θ_opt[(ncoef+1):end])
    n_total_params = ncoef + ntau

    ll_final = -Optim.minimum(result)

    # Hessian via finite difference at optimum
    ϵ = 1e-5
    hess_final = zeros(n_total_params, n_total_params)
    ll0 = ll_final
    for j in 1:n_total_params
        for k in j:n_total_params
            θ1 = copy(θ_opt); θ1[j] += ϵ; θ1[k] += ϵ
            θ2 = copy(θ_opt); θ2[j] += ϵ
            θ3 = copy(θ_opt); θ3[k] += ϵ
            ll1 = ologit_loglikelihood(X, y_idx, θ1[1:ncoef], ologit_thresholds(θ1[(ncoef+1):end]))
            ll2 = ologit_loglikelihood(X, y_idx, θ2[1:ncoef], ologit_thresholds(θ2[(ncoef+1):end]))
            ll3 = ologit_loglikelihood(X, y_idx, θ3[1:ncoef], ologit_thresholds(θ3[(ncoef+1):end]))
            h = (ll1 - ll2 - ll3 + ll0) / ϵ^2
            hess_final[j, k] = h
            hess_final[k, j] = h
        end
    end

    vcov_full = try
        inv(-hess_final)
    catch
        pinv(-hess_final)
    end
    vcov_matrix = vcov_full[1:ncoef, 1:ncoef]
    se_values = sqrt.(max.(diag(vcov_matrix), 0.0))

    dof = nobs - n_total_params
    z_stats = β ./ se_values
    pvalues = 2 .* (1 .- cdf.(Normal(), abs.(z_stats)))

    α_ci = 0.05
    z_crit = quantile(Normal(), 1 - α_ci / 2)

    null_ll = ologit_null_loglikelihood(y_idx, J)
    pseudo_r2 = 1 - (-ll_final) / max(-null_ll, 1e-10)
    aic = 2 * n_total_params - 2 * ll_final
    bic = n_total_params * log(nobs) - 2 * ll_final

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, MetricaLinear.build_rows_dropped_warning(dropped_rows))

    glance_table = MetricaBase.ModelGlance(
        :ordered_logit, nobs, dof,
        Dict{Symbol, MetricaBase.MetricValue}(
            :pseudo_r2 => pseudo_r2, :loglik => ll_final, :aic => aic, :bic => bic, :n_categories => J,
        ),
        warnings,
    )

    tidy_rows = [MetricaBase.CoefRow(coefficient_names[i], β[i], se_values[i], z_stats[i], pvalues[i], β[i] - z_crit * se_values[i], β[i] + z_crit * se_values[i]) for i in 1:ncoef]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "MLE (L-BFGS)")

    η = X * β
    fitted_matrix = zeros(nobs, J)
    for i in 1:nobs
        cumprob = [1.0 / (1.0 + exp(-(τ[j] - η[i]))) for j in 1:length(τ)]
        pushfirst!(cumprob, 0.0)
        push!(cumprob, 1.0)
        for j in 1:J
            fitted_matrix[i, j] = cumprob[j+1] - cumprob[j]
        end
    end

    return OrderedLogitFitResult(
        String(formula), glance_table, tidy_table,
        Matrix{Float64}(X), y, fitted_matrix,
        τ, coefficient_names, β,
        vcov_matrix, se_values,
        -2.0 * ll_final, ll_final, Optim.iterations(result), converged, J,
    )
end

function ologit_null_loglikelihood(y::Vector{Int}, n_cat::Int)
    props = [count(==(c), y) / length(y) for c in 1:n_cat]
    return sum(count(==(c), y) * log(max(props[c], 1e-15)) for c in 1:n_cat)
end

MetricaBase.glance(result::OrderedLogitFitResult) = result.glance_table
MetricaBase.tidy(result::OrderedLogitFitResult) = result.tidy_table
MetricaBase.coef(result::OrderedLogitFitResult) = result.coefficient_names .=> result.coefficient_values
MetricaBase.vcov(result::OrderedLogitFitResult) = result.vcov_matrix
MetricaBase.stderror(result::OrderedLogitFitResult) = result.stderror_values
MetricaBase.nobs(result::OrderedLogitFitResult) = length(result.response_vector)
MetricaBase.dof(result::OrderedLogitFitResult) = result.glance_table.dof
MetricaBase.r2(result::OrderedLogitFitResult) = result.glance_table.metrics[:pseudo_r2]
MetricaBase.fitted(result::OrderedLogitFitResult) = mapslices(argmax, result.fitted_values, dims=2)[:]
MetricaBase.residuals(result::OrderedLogitFitResult) = result.response_vector .- MetricaBase.fitted(result)
function MetricaBase.predict(result::OrderedLogitFitResult; newdata=nothing, interval=:none, level=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    η = X * result.coefficient_values
    probs = zeros(size(X, 1), result.n_categories)
    for i in 1:size(X, 1)
        cumprob = [1.0 / (1.0 + exp(-(result.thresholds[j] - η[i]))) for j in 1:length(result.thresholds)]
        pushfirst!(cumprob, 0.0); push!(cumprob, 1.0)
        for j in 1:result.n_categories
            probs[i, j] = cumprob[j+1] - cumprob[j]
        end
    end
    return mapslices(argmax, probs, dims=2)[:]
end
function MetricaBase.augment(result::OrderedLogitFitResult)
    n = length(result.response_vector)
    cols = Dict{Symbol, Vector{Float64}}(:observation => collect(1.0:n), :predicted_class => MetricaBase.fitted(result))
    for j in 1:result.n_categories
        cols[Symbol("prob_cat$(j)")] = result.fitted_values[:, j]
    end
    return MetricaBase.AugmentTable(cols, n)
end
