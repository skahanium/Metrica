# === 公式解析 ==================================================================

function parse_formula_term(formula::AbstractString)
    expr = try
        Meta.parse("@formula($(formula))")
    catch err
        return MetricaBase.ModelError(
            :formula_parse_failed,
            "公式解析失败",
            "无法解析公式字符串：$(sprint(showerror, err))",
            "请使用如 y ~ x1 + x2 的公式格式。",
        )
    end

    try
        return Core.eval(@__MODULE__, expr)
    catch err
        return MetricaBase.ModelError(
            :formula_parse_failed,
            "公式解析失败",
            "无法构造公式对象：$(sprint(showerror, err))",
            "请使用如 y ~ x1 + x2 的公式格式。",
        )
    end
end

function collect_term_symbols(term)
    symbols = Symbol[]
    append_term_symbols!(symbols, term)
    return unique(symbols)
end

function append_term_symbols!(symbols::Vector{Symbol}, term)
    if term isa StatsModels.Term
        push!(symbols, term.sym)
        return symbols
    end

    if term isa Tuple
        for item in term
            append_term_symbols!(symbols, item)
        end
        return symbols
    end

    if hasproperty(term, :lhs)
        append_term_symbols!(symbols, getproperty(term, :lhs))
    end

    if hasproperty(term, :rhs)
        append_term_symbols!(symbols, getproperty(term, :rhs))
    end

    return symbols
end

# === 警告构造 ==================================================================

function build_rows_dropped_warning(dropped_rows::Int)
    return MetricaBase.ModelWarning(
        :rows_dropped,
        "缺失值删样",
        "因模型相关列存在缺失值，已删除 $(dropped_rows) 行观测。",
        "请检查模型变量中的缺失分布。",
        MetricaBase.warning,
    )
end

# === 统计量计算 ================================================================

function compute_pvalues(statistics::Vector{Float64}, dof::Int)
    distribution = TDist(dof)
    return 2 .* (1 .- cdf.(distribution, abs.(statistics)))
end

function weighted_tss(y::Vector{Float64}, weights::Union{Nothing, Vector{Float64}})
    if isnothing(weights)
        y_mean = mean(y)
        return sum(abs2, y .- y_mean)
    end

    total_weight = sum(weights)
    y_mean = sum(weights .* y) / total_weight
    return sum(weights .* abs2.(y .- y_mean))
end

# === 流水线子步骤 ==============================================================

"""
验证模型所需列在数据集中均存在，权重列（若有）同样存在。

成功时返回 `nothing`；失败时返回 `ModelError`。
"""
function validate_model_columns(dataset, model_columns::Vector{Symbol}, weights::Union{Nothing, Symbol}, cluster::Union{Nothing, Symbol})
    available_columns = Set(Symbol.(names(dataset)))
    missing_columns = [name for name in model_columns if name ∉ available_columns]

    isempty(missing_columns) || return MetricaBase.ModelError(
        :unknown_variable,
        "模型变量不存在",
        "公式中的变量无法在数据集中找到：$(join(string.(missing_columns), ", "))。",
        "请检查公式中的变量名是否与数据列一致。",
    )

    if !isnothing(weights) && weights ∉ available_columns
        return MetricaBase.ModelError(
            :unknown_weight_variable,
            "权重变量不存在",
            "指定的权重变量无法在数据集中找到：$(weights)。",
            "请检查权重变量名是否与数据列一致。",
        )
    end

    if !isnothing(cluster) && cluster ∉ available_columns
        return MetricaBase.ModelError(
            :unknown_cluster_variable,
            "聚类变量不存在",
            "指定的聚类变量无法在数据集中找到：$(cluster)。",
            "请检查聚类变量名是否与数据列一致。",
        )
    end

    return nothing
end

"""
从数据集中筛除模型相关列中含缺失值的行，构建 `ModelFrame` 与 `ModelMatrix`。

返回 `(filtered_dataset, model_frame, model_matrix, X, y, weight_values, cluster_values, n_total, n_effective)`
或 `ModelError`。
"""
function prepare_model_data(dataset, model_formula, model_columns, weights::Union{Nothing, Symbol}, cluster::Union{Nothing, Symbol})
    required_columns = isnothing(weights) ? model_columns : unique([model_columns; weights])
    if !isnothing(cluster)
        required_columns = unique([required_columns; cluster])
    end
    filtered_dataset = dataset[completecases(dataset[:, required_columns]), :]
    n_total = nrow(dataset)
    n_effective = nrow(filtered_dataset)

    n_effective > 0 || return MetricaBase.ModelError(
        :empty_effective_sample,
        "有效样本为空",
        "在模型相关列完成缺失值删除后，没有剩余观测可用于拟合。",
        "请检查响应变量与解释变量中的缺失情况。",
    )

    model_frame = try
        ModelFrame(model_formula, filtered_dataset)
    catch err
        if err isa ArgumentError
            return MetricaBase.ModelError(
                :unknown_variable,
                "模型变量不存在",
                "公式中的变量无法在数据集中解析：$(sprint(showerror, err))",
                "请检查公式中的变量名是否与数据列一致。",
            )
        end

        rethrow(err)
    end

    model_matrix = ModelMatrix(model_frame)
    X = model_matrix.m
    y = Float64.(response(model_frame))

    weight_values = if isnothing(weights)
        nothing
    else
        wv = Float64.(filtered_dataset[!, weights])
        if any(value -> value <= 0, wv)
            return MetricaBase.ModelError(
                :invalid_weights,
                "权重无效",
                "WLS 权重必须严格大于 0。",
                "请检查权重变量中的零值或负值。",
            )
        end
        wv
    end

    cluster_values = if isnothing(cluster)
        nothing
    else
        filtered_dataset[!, cluster]
    end

    return (filtered_dataset, model_frame, model_matrix, X, y, weight_values, cluster_values, n_total, n_effective)
end

"""
验证设计矩阵是否满秩且自由度充足。

成功时返回 `nothing`；失败时返回 `ModelError`。
"""
function validate_design(X::Matrix{Float64}, ncoef::Int, nobs::Int)
    rank(X) == ncoef || return MetricaBase.ModelError(
        :singular_design,
        "设计矩阵奇异",
        "预测变量之间存在完全线性相关，模型无法唯一估计。",
        "请移除冗余变量或检查重复列后重试。",
    )

    dof = nobs - ncoef
    dof > 0 || return MetricaBase.ModelError(
        :insufficient_degrees_of_freedom,
        "自由度不足",
        "有效样本量不足以支撑当前模型参数个数。",
        "请减少参数数量或增加样本后重试。",
    )

    return nothing
end

"""
按权重转换设计矩阵与响应向量（WLS），或原样返回（OLS）。

返回 `(X_eff, y_eff, model_label)`。
"""
function apply_weights(X::Matrix{Float64}, y::Vector{Float64}, weight_values::Union{Nothing, Vector{Float64}})
    if isnothing(weight_values)
        return X, y, :ols
    end

    sqrt_w = sqrt.(weight_values)
    return X .* sqrt_w, y .* sqrt_w, :wls
end

"""
通过正规方程求解 OLS/WLS 系数，并计算拟合值与残差。

返回 `(coefficients, fitted, residuals, effective_residuals)`。
"""
function compute_ols_estimates(X::Matrix{Float64}, y::Vector{Float64}, X_eff::Matrix{Float64}, y_eff::Vector{Float64})
    coefficients = X_eff \ y_eff
    fitted = X * coefficients
    residuals = y - fitted
    effective_residuals = y_eff - (X_eff * coefficients)
    return coefficients, fitted, residuals, effective_residuals
end

"""
计算系数的方差-协方差矩阵与标准误。

`cluster_values` 仅在 `vcov === :cluster` 时使用，包含每个观测的聚类标识。

返回 `(vcov_matrix, stderror)` 或 `ModelError`。
"""
function compute_vcov(X_eff::Matrix{Float64}, effective_residuals::Vector{Float64}, nobs::Int, dof::Int, vcov::Symbol, cluster_values::Union{Nothing, AbstractVector})
    ncoef = size(X_eff, 2)
    xtx = transpose(X_eff) * X_eff
    xtx_inv = inv(xtx)
    rss = sum(abs2, effective_residuals)
    sigma2 = rss / dof

    vcov_matrix = if vcov === :classical
        sigma2 * xtx_inv
    elseif vcov === :HC1
        scale = nobs / dof
        meat = zeros(ncoef, ncoef)
        for index in 1:nobs
            xi = reshape(X_eff[index, :], :, 1)
            meat += effective_residuals[index]^2 .* (xi * transpose(xi))
        end
        scale .* (xtx_inv * meat * xtx_inv)
    elseif vcov === :cluster
        if isnothing(cluster_values)
            return MetricaBase.ModelError(
                :missing_cluster_variable,
                "缺少聚类变量",
                "cluster 协方差需要指定聚类变量。",
                "请在请求中提供 cluster_column 字段。",
            )
        end

        # 按聚类标识分组计算聚类稳健协方差
        unique_clusters = unique(cluster_values)
        G = length(unique_clusters)

        G > 1 || return MetricaBase.ModelError(
            :single_cluster,
            "聚类数量不足",
            "聚类稳健标准误要求至少包含 2 个聚类。",
            "当前数据仅包含 1 个聚类，请更换聚类变量或使用 classical/HC1。",
        )

        meat = zeros(ncoef, ncoef)
        for cluster_id in unique_clusters
            cluster_indices = findall(value -> isequal(value, cluster_id), cluster_values)
            Xg = X_eff[cluster_indices, :]
            eg = effective_residuals[cluster_indices]
            score_g = transpose(Xg) * eg
            meat += score_g * transpose(score_g)
        end

        # Stata 风格小样本修正: c = G/(G-1) * (N-1)/(N-k)
        correction = (G / (G - 1)) * ((nobs - 1) / dof)
        correction .* (xtx_inv * meat * xtx_inv)
    else
        return MetricaBase.ModelError(
            :unsupported_vcov,
            "协方差类型暂不支持",
            "当前仅支持 classical、HC1 与 cluster。",
            "请使用 `classical`、`HC1` 或 `cluster`。",
        )
    end

    stderror = sqrt.(diag(vcov_matrix))
    return vcov_matrix, stderror
end

"""
计算模型级摘要统计量：R²、调整 R²、RSS、TSS、sigma。
"""
function compute_glance_stats(y::Vector{Float64}, effective_residuals::Vector{Float64}, weight_values::Union{Nothing, Vector{Float64}}, dof::Int, nobs::Int)
    rss = sum(abs2, effective_residuals)
    tss = weighted_tss(y, weight_values)
    r2 = iszero(tss) ? 1.0 : 1 - rss / tss
    adj_r2 = if iszero(tss)
        1.0
    else
        1 - (rss / dof) / (tss / (nobs - 1))
    end
    sigma = sqrt(rss / dof)
    return r2, adj_r2, rss, tss, sigma
end

"""
将系数向量与相关统计量组装为 `TidyTable`。
"""
function assemble_tidy_table(coefficients::Vector{Float64}, stderror::Vector{Float64}, coefficient_names::Vector{Symbol}, dof::Int, vcov::Symbol)
    statistics = coefficients ./ stderror
    pvalues = compute_pvalues(statistics, dof)

    tidy_rows = [
        MetricaBase.CoefRow(
            coefficient_names[index],
            coefficients[index],
            stderror[index],
            statistics[index],
            pvalues[index],
        )
        for index in eachindex(coefficients)
    ]

    vcov_label = if vcov === :HC1
        "HC1"
    elseif vcov === :cluster
        "cluster"
    else
        "classical"
    end
    return MetricaBase.TidyTable(tidy_rows, vcov_label)
end

# === 主入口 ====================================================================

"""
使用给定模型规格与数据拟合模型。

返回 `AbstractFittedModel` 的子类型实例；若拟合失败则返回 `ModelError`。
"""
function fit_ols_file(
    path::AbstractString,
    formula::AbstractString;
    weights::Union{Nothing, Symbol}=nothing,
    vcov::Symbol=:classical,
    cluster::Union{Nothing, Symbol}=nothing,
)
    dataset = load_dataset(path)
    dataset isa MetricaBase.ModelError && return dataset

    model_formula = parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    model_columns = collect_term_symbols(model_formula)

    err = validate_model_columns(dataset, model_columns, weights, cluster)
    err isa MetricaBase.ModelError && return err

    prepared = prepare_model_data(dataset, model_formula, model_columns, weights, cluster)
    prepared isa MetricaBase.ModelError && return prepared

    (_, model_frame, _, X, y, weight_values, cluster_values, n_total, n_effective) = prepared
    nobs = length(y)
    ncoef = size(X, 2)

    err = validate_design(X, ncoef, nobs)
    err isa MetricaBase.ModelError && return err

    dof = nobs - ncoef
    X_eff, y_eff, model_label = apply_weights(X, y, weight_values)
    coefficients, fitted, residuals, effective_residuals = compute_ols_estimates(X, y, X_eff, y_eff)

    vcov_result = compute_vcov(X_eff, effective_residuals, nobs, dof, vcov, cluster_values)
    vcov_result isa MetricaBase.ModelError && return vcov_result
    vcov_matrix, stderror = vcov_result

    r2, adj_r2, rss, tss, sigma = compute_glance_stats(y, effective_residuals, weight_values, dof, nobs)
    coefficient_names = Symbol.(coefnames(model_frame))

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, build_rows_dropped_warning(dropped_rows))

    glance_table = MetricaBase.ModelGlance(
        model_label,
        nobs,
        dof,
        Dict{Symbol, MetricaBase.MetricValue}(
            :r2 => r2,
            :adj_r2 => adj_r2,
            :rss => rss,
            :tss => tss,
            :sigma => sigma,
        ),
        warnings,
    )

    tidy_table = assemble_tidy_table(coefficients, stderror, coefficient_names, dof, vcov)

    return OLSFitResult(
        String(formula),
        glance_table,
        tidy_table,
        Matrix{Float64}(X),
        copy(y),
        fitted,
        residuals,
        coefficient_names,
        vcov_matrix,
        stderror,
    )
end
