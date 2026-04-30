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

function build_rows_dropped_warning(dropped_rows::Int)
    return MetricaBase.ModelWarning(
        :rows_dropped,
        "缺失值删样",
        "因模型相关列存在缺失值，已删除 $(dropped_rows) 行观测。",
        "请检查模型变量中的缺失分布。",
        MetricaBase.warning,
    )
end

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

function fit_ols_file(
    path::AbstractString,
    formula::AbstractString;
    weights::Union{Nothing, Symbol}=nothing,
    vcov::Symbol=:classical,
)
    dataset = load_dataset(path)
    dataset isa MetricaBase.ModelError && return dataset

    model_formula = parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    model_columns = collect_term_symbols(model_formula)
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

    required_columns = isnothing(weights) ? model_columns : unique([model_columns; weights])
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
    nobs = length(y)
    ncoef = size(X, 2)

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

    weight_values = isnothing(weights) ? nothing : Float64.(filtered_dataset[!, weights])
    if !isnothing(weight_values) && any(value -> value <= 0, weight_values)
        return MetricaBase.ModelError(
            :invalid_weights,
            "权重无效",
            "WLS 权重必须严格大于 0。",
            "请检查权重变量中的零值或负值。",
        )
    end

    X_eff = X
    y_eff = y
    model_label = :ols
    if !isnothing(weight_values)
        sqrt_w = sqrt.(weight_values)
        X_eff = X .* sqrt_w
        y_eff = y .* sqrt_w
        model_label = :wls
    end

    coefficients = X_eff \ y_eff
    fitted = X * coefficients
    residuals = y - fitted
    effective_residuals = y_eff - (X_eff * coefficients)
    rss = sum(abs2, effective_residuals)
    tss = weighted_tss(y, weight_values)
    r2 = iszero(tss) ? 1.0 : 1 - rss / tss
    adj_r2 = if iszero(tss)
        1.0
    else
        1 - (rss / dof) / (tss / (nobs - 1))
    end

    xtx = transpose(X_eff) * X_eff
    xtx_inv = inv(xtx)
    sigma2 = rss / dof
    vcov_matrix = if vcov === :classical
        sigma2 * xtx_inv
    elseif vcov === :HC1
        scale = nobs / dof
        meat = zeros(size(X_eff, 2), size(X_eff, 2))
        for index in 1:nobs
            xi = reshape(X_eff[index, :], :, 1)
            meat += effective_residuals[index]^2 .* (xi * transpose(xi))
        end
        scale .* (xtx_inv * meat * xtx_inv)
    else
        return MetricaBase.ModelError(
            :unsupported_vcov,
            "协方差类型暂不支持",
            "当前仅支持 classical 与 HC1。",
            "请先使用 `classical` 或 `HC1`。",
        )
    end
    stderror = sqrt.(diag(vcov_matrix))
    statistics = coefficients ./ stderror
    pvalues = compute_pvalues(statistics, dof)
    coefficient_names = Symbol.(coefnames(model_frame))

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
            :sigma => sqrt(sigma2),
        ),
        warnings,
    )

    tidy_table = MetricaBase.TidyTable(
        tidy_rows,
        vcov === :HC1 ? "HC1" : "classical",
    )

    return OLSFitResult(
        String(formula),
        glance_table,
        tidy_table,
        Matrix{Float64}(X),
        copy(y),
        fitted,
        residuals,
        coefficient_names,
    )
end
