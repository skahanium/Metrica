# === 多项 Logit 模型 ==========================================================

"""
    mnl_negloglik(θ_flat, X, y_idx, J, ncoef)

多项 Logit 联合负对数似然。

参数 `θ_flat` 展平为向量：[β₂'; β₃'; ...; β_J']，
其中 βⱼ 为第 j 个非基准类别的系数向量（含截距）。
基准类别的线性预测恒为 0。

对数似然：LL = Σᵢ Σⱼ yᵢⱼ log(pᵢⱼ)
其中 pᵢⱼ = exp(ηᵢⱼ) / Σₖ exp(ηᵢₖ)，ηᵢ₁ = 0（基准类别）。
"""
function mnl_negloglik(θ_flat::Vector{Float64}, X::Matrix{Float64},
                       y_idx::Vector{Int}, J::Int, ncoef::Int)
    nobs = size(X, 1)
    n_nonref = J - 1

    # 从展平向量重建系数矩阵：(n_nonref × ncoef)
    β_matrix = reshape(θ_flat, ncoef, n_nonref)'

    nll = 0.0
    for i in 1:nobs
        # η[i,j]：基准类别 j=1 时 η=0
        η = zeros(J)
        for k in 1:n_nonref
            η[k + 1] = dot(X[i, :], β_matrix[k, :])
        end
        # 数值稳定 softmax
        η_max = maximum(η)
        exp_η = exp.(η .- η_max)
        sum_exp = sum(exp_η)
        log_p = (η .- η_max) .- log(sum_exp)
        nll -= log_p[y_idx[i]]
    end
    return nll
end

function MetricaBase.fit(::Type{MultinomialLogitModel}, formula::AbstractString, data;
                          reference_category::Int=1, vcov::Symbol=:classical,
                          cluster_column::Union{Nothing,Symbol,String}=nothing)
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

    (_, model_frame, _, X, y, _, cluster_values, n_total, n_effective) = prepared
    nobs = size(X, 1)
    ncoef = size(X, 2)
    y_int = Int.(round.(y))
    coefficient_names = Symbol.(StatsModels.coefnames(model_frame))

    categories = sort(unique(y_int))
    J = length(categories)
    if J < 3
        return MetricaBase.ModelError(:insufficient_categories, "多项 Logit 要求至少 3 个类别。", "当前只有 $J 个类别。", "若有 2 个类别，请使用二分类 Logit。")
    end
    if !(reference_category in categories)
        return MetricaBase.ModelError(:invalid_reference, "基准类别不在数据中。", "类别 $reference_category 不在响应变量中。", "")
    end

    if vcov ∉ (:classical,)
        return MetricaBase.ModelError(
            :unsupported_vcov,
            "多项 Logit 协方差类型暂不支持",
            "当前仅支持 :classical。HC1 与 cluster 将在后续版本中实现。",
            "请使用 :classical。",
        )
    end

    err = MetricaLinear.validate_design(X, ncoef, nobs)
    err isa MetricaBase.ModelError && return err

    # 将原始类别映射到索引 1:J
    cat_to_idx = Dict(categories[i] => i for i in 1:J)
    y_idx = [cat_to_idx[yi] for yi in y_int]

    other_cats = setdiff(categories, [reference_category])
    n_nonref = J - 1

    # 用 one-vs-rest Logit 系数作为初始值
    θ_init = zeros(ncoef * n_nonref)
    response_sym = Symbol(split(formula, "~")[1] |> strip)
    for (k, cat) in enumerate(other_cats)
        y_binary = Float64.(y_int .== cat)
        df_binary = copy(dataset)
        df_binary[!, response_sym] = y_binary
        logit_result = MetricaBase.fit(LogitModel, formula, df_binary)
        if !(logit_result isa MetricaBase.ModelError)
            θ_init[((k-1)*ncoef + 1):(k*ncoef)] = logit_result.coefficient_values
        end
    end

    # 联合负对数似然
    function negll(θ_flat::Vector{Float64})
        mnl_negloglik(θ_flat, X, y_idx, J, ncoef)
    end

    # Optim.jl L-BFGS 优化
    result = try
        Optim.optimize(negll, θ_init, Optim.LBFGS())
    catch e
        return MetricaBase.ModelError(:mlogit_opt_error, "多项 Logit 优化失败", sprint(showerror, e), "请检查数据质量。")
    end

    converged = Optim.converged(result)
    θ_opt = Optim.minimizer(result)
    ll_final = -Optim.minimum(result)
    iterations = Optim.iterations(result)

    # 从展平向量重建系数矩阵
    coeff_matrix = reshape(θ_opt, ncoef, n_nonref)'

    # Hessian 通过有限差分计算
    n_total_params = n_nonref * ncoef
    ϵ = 1e-5
    hess = zeros(n_total_params, n_total_params)
    ll0 = -Optim.minimum(result)
    for j in 1:n_total_params
        for k in j:n_total_params
            θ1 = copy(θ_opt); θ1[j] += ϵ; θ1[k] += ϵ
            θ2 = copy(θ_opt); θ2[j] += ϵ
            θ3 = copy(θ_opt); θ3[k] += ϵ
            ll1 = -negll(θ1)
            ll2 = -negll(θ2)
            ll3 = -negll(θ3)
            h = (ll1 - ll2 - ll3 + ll0) / ϵ^2
            hess[j, k] = h
            hess[k, j] = h
        end
    end

    vcov_full = try
        inv(-hess)
    catch
        pinv(-hess)
    end

    # 联合方差-协方差矩阵
    vcov_joint = Matrix{Float64}(vcov_full)

    # 从联合 vcov 提取每个非基准类别的标准误
    se_matrix = zeros(n_nonref, ncoef)
    for k in 1:n_nonref
        idx = ((k-1)*ncoef + 1):(k*ncoef)
        se_matrix[k, :] = sqrt.(max.(diag(vcov_joint[idx, idx]), 0.0))
    end

    # z 统计量和 p 值
    z_matrix = coeff_matrix ./ max.(se_matrix, 1e-10)
    p_matrix = 2 .* (1 .- cdf.(Normal(), abs.(z_matrix)))

    # 整理 tidy 表
    tidy_rows = MetricaBase.CoefRow[]
    for k in 1:n_nonref
        for j in 1:ncoef
            push!(tidy_rows, MetricaBase.CoefRow(
                Symbol("cat$(other_cats[k])_$(coefficient_names[j])"),
                coeff_matrix[k, j], se_matrix[k, j],
                z_matrix[k, j], p_matrix[k, j],
            ))
        end
    end
    tidy_table = MetricaBase.TidyTable(tidy_rows, "MLE (joint softmax)")

    # 预测概率矩阵
    fitted_matrix = zeros(nobs, J)
    for i in 1:nobs
        η = zeros(J)
        for k in 1:n_nonref
            cat_idx = findfirst(==(other_cats[k]), categories)
            η[cat_idx] = dot(X[i, :], coeff_matrix[k, :])
        end
        exp_η = exp.(η .- maximum(η))
        fitted_matrix[i, :] = exp_η ./ sum(exp_η)
    end

    # null 对数似然（仅截距模型）
    props = [count(==(c), y_idx) / nobs for c in 1:J]
    null_ll = sum(count(==(c), y_idx) * log(max(props[c], 1e-15)) for c in 1:J)
    pseudo_r2 = 1 - (-ll_final) / max(-null_ll, 1e-10)
    aic = 2 * n_total_params - 2 * ll_final
    bic = n_total_params * log(nobs) - 2 * ll_final

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, MetricaLinear.build_rows_dropped_warning(dropped_rows))

    if !converged
        push!(warnings, MetricaBase.ModelWarning(
            :mlogit_not_converged, "多项 Logit 未收敛",
            "L-BFGS 优化在最大次数内未收敛，结果可能不可靠。",
            "请检查数据质量或增加最大迭代次数。",
            MetricaBase.warning,
        ))
    end

    glance_table = MetricaBase.ModelGlance(
        :multinomial_logit, nobs, nobs - n_total_params,
        Dict{Symbol, MetricaBase.MetricValue}(
            :loglik => ll_final, :n_categories => J,
            :pseudo_r2 => pseudo_r2, :aic => aic, :bic => bic,
        ),
        warnings,
    )

    return MultinomialLogitFitResult(
        String(formula), glance_table, tidy_table,
        Matrix{Float64}(X), y, fitted_matrix,
        coefficient_names, coeff_matrix,
        Matrix{Float64}[vcov_joint], se_matrix,
        categories, reference_category, ll_final,
        iterations, converged,
    )
end

MetricaBase.glance(result::MultinomialLogitFitResult) = result.glance_table
MetricaBase.tidy(result::MultinomialLogitFitResult) = result.tidy_table
MetricaBase.coef(result::MultinomialLogitFitResult) = result.tidy_table.rows .|> r -> r.name => r.estimate
MetricaBase.vcov(result::MultinomialLogitFitResult) = result.vcov_matrices[1]
MetricaBase.stderror(result::MultinomialLogitFitResult) = [r.stderror for r in result.tidy_table.rows]
MetricaBase.nobs(result::MultinomialLogitFitResult) = size(result.design_matrix, 1)
MetricaBase.dof(result::MultinomialLogitFitResult) = result.glance_table.dof
MetricaBase.r2(result::MultinomialLogitFitResult) = result.glance_table.metrics[:pseudo_r2]
MetricaBase.fitted(result::MultinomialLogitFitResult) =
    [result.categories[argmax(result.fitted_values[i, :])] for i in 1:size(result.fitted_values, 1)]
MetricaBase.residuals(result::MultinomialLogitFitResult) = result.response_vector .- MetricaBase.fitted(result)
function MetricaBase.augment(result::MultinomialLogitFitResult)
    n = size(result.design_matrix, 1)
    cols = Dict{Symbol, Vector{Float64}}(:observation => collect(1.0:n))
    for j in 1:length(result.categories)
        cols[Symbol("prob_cat$(result.categories[j])")] = result.fitted_values[:, j]
    end
    return MetricaBase.AugmentTable(cols, n)
end
function MetricaBase.predict(result::MultinomialLogitFitResult; newdata=nothing, interval=:none, level=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    n = size(X, 1)
    probs = zeros(n, length(result.categories))
    other_cats = setdiff(result.categories, [result.reference])
    for i in 1:n
        scores = zeros(length(result.categories))
        scores[result.reference] = 0.0
        for (k, cat) in enumerate(other_cats)
            cat_idx = findfirst(==(cat), result.categories)
            scores[cat_idx] = dot(X[i, :], result.coefficient_matrix[k, :])
        end
        exp_scores = exp.(scores .- maximum(scores))
        probs[i, :] = exp_scores ./ sum(exp_scores)
    end
    return mapslices(argmax, probs, dims=2)[:]
end
