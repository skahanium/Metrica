# === 多项 Logit 模型 ==========================================================

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

    (_, model_frame, _, X, y, _, _, _, _) = prepared
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

    err = MetricaLinear.validate_design(X, ncoef, nobs)
    err isa MetricaBase.ModelError && return err

    other_cats = setdiff(categories, [reference_category])
    coeff_matrix = zeros(J-1, ncoef)
    se_matrix = zeros(J-1, ncoef)
    vcov_list = Vector{Matrix{Float64}}()
    ll_total = 0.0

    # 从公式提取响应变量名
    response_sym = Symbol(split(formula, "~")[1] |> strip)
    for (k, cat) in enumerate(other_cats)
        y_binary = Float64.(y_int .== cat)
        df_binary = copy(dataset)
        df_binary[!, response_sym] = y_binary
        logit_result = MetricaBase.fit(LogitModel, formula, df_binary)
        logit_result isa MetricaBase.ModelError && return logit_result

        coeff_matrix[k, :] = logit_result.coefficient_values
        se_matrix[k, :] = logit_result.stderror_values
        push!(vcov_list, logit_result.vcov_matrix)
        ll_total += logit_result.loglikelihood
    end

    tidy_rows = MetricaBase.CoefRow[]
    for k in 1:(J-1)
        for j in 1:ncoef
            push!(tidy_rows, MetricaBase.CoefRow(
                Symbol("cat$(other_cats[k])_$(coefficient_names[j])"),
                coeff_matrix[k, j], se_matrix[k, j],
                coeff_matrix[k, j] / max(se_matrix[k, j], 1e-10), NaN,
            ))
        end
    end
    tidy_table = MetricaBase.TidyTable(tidy_rows, "MLE (one-vs-rest Logit)")

    glance_table = MetricaBase.ModelGlance(
        :multinomial_logit, nobs, nobs - (J-1)*ncoef,
        Dict{Symbol, MetricaBase.MetricValue}(:loglik => ll_total, :n_categories => J),
        MetricaBase.ModelWarning[],
    )

    # 预测概率矩阵
    fitted_matrix = zeros(nobs, J)
    for i in 1:nobs
        scores = zeros(J)
        scores[reference_category] = 0.0
        for (k, cat) in enumerate(other_cats)
            cat_idx = findfirst(==(cat), categories)
            scores[cat_idx] = dot(X[i, :], coeff_matrix[k, :])
        end
        exp_scores = exp.(scores .- maximum(scores))
        fitted_matrix[i, :] = exp_scores ./ sum(exp_scores)
    end

    return MultinomialLogitFitResult(
        String(formula), glance_table, tidy_table,
        Matrix{Float64}(X), y, fitted_matrix,
        coefficient_names, coeff_matrix, vcov_list, se_matrix,
        categories, reference_category, ll_total, true,
    )
end

MetricaBase.glance(result::MultinomialLogitFitResult) = result.glance_table
MetricaBase.tidy(result::MultinomialLogitFitResult) = result.tidy_table
MetricaBase.coef(result::MultinomialLogitFitResult) = result.tidy_table.rows .|> r -> r.name => r.estimate
MetricaBase.vcov(result::MultinomialLogitFitResult) = result.vcov_matrices[1]
MetricaBase.stderror(result::MultinomialLogitFitResult) = [r.stderror for r in result.tidy_table.rows]
MetricaBase.nobs(result::MultinomialLogitFitResult) = size(result.design_matrix, 1)
MetricaBase.dof(result::MultinomialLogitFitResult) = result.glance_table.dof
MetricaBase.r2(result::MultinomialLogitFitResult) = NaN
MetricaBase.fitted(result::MultinomialLogitFitResult) = mapslices(argmax, result.fitted_values, dims=2)[:]
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
    for i in 1:n
        scores = zeros(length(result.categories))
        scores[result.reference] = 0.0
        other_cats = setdiff(result.categories, [result.reference])
        for (k, cat) in enumerate(other_cats)
            cat_idx = findfirst(==(cat), result.categories)
            scores[cat_idx] = dot(X[i, :], result.coefficient_matrix[k, :])
        end
        exp_scores = exp.(scores .- maximum(scores))
        probs[i, :] = exp_scores ./ sum(exp_scores)
    end
    return mapslices(argmax, probs, dims=2)[:]
end
