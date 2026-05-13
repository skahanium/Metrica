# === IV/2SLS 估计器 ===========================================================

"""
工具变量/两阶段最小二乘模型规格。
"""
struct IVModel <: MetricaBase.AbstractLinearModel
    formula::String
    instruments::Vector{String}
    endog::Vector{String}
end

"""
IV/2SLS 拟合结果。
"""
struct IVFitResult <: MetricaBase.AbstractLinearFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    coefficient_names::Vector{Symbol}
    coef_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    first_stage_stats::Dict{Symbol, Float64}
    weak_instrument_warnings::Vector{MetricaBase.ModelWarning}
    second_stage_matrix::Matrix{Float64}
end

MetricaBase.glance(result::IVFitResult) = result.glance_table
MetricaBase.tidy(result::IVFitResult) = result.tidy_table
MetricaBase.coef(result::IVFitResult) = result.coefficient_names .=> result.coef_values
MetricaBase.vcov(result::IVFitResult) = result.vcov_matrix
MetricaBase.stderror(result::IVFitResult) = result.stderror_values
MetricaBase.nobs(result::IVFitResult) = length(result.response_vector)
MetricaBase.dof(result::IVFitResult) = length(result.response_vector) - length(result.coefficient_names)
MetricaBase.r2(result::IVFitResult) = result.glance_table.metrics[:r2]
MetricaBase.fitted(result::IVFitResult) = result.fitted_values
MetricaBase.residuals(result::IVFitResult) = result.residual_vector

function MetricaBase.augment(result::IVFitResult)
    nobs_val = length(result.response_vector)
    X = result.second_stage_matrix
    residuals = result.residual_vector

    sigma = sqrt(sum(abs2, residuals) / (nobs_val - size(X, 2)))
    std_residuals = sigma > 0 ? residuals ./ sigma : zeros(nobs_val)

    XtX = X' * X
    leverage = if det(XtX) > eps(Float64)
        XtX_inv = inv(XtX)
        [dot(X[i, :], XtX_inv * X[i, :]) for i in 1:nobs_val]
    else
        fill(NaN, nobs_val)
    end

    k = size(X, 2)
    cooks_d = fill(NaN, nobs_val)
    for i in 1:nobs_val
        if leverage[i] < 1.0 && sigma > 0
            cooks_d[i] = (std_residuals[i]^2 * leverage[i]) / (k * (1.0 - leverage[i])^2)
        end
    end

    return MetricaBase.AugmentTable(Dict(
        :observation => collect(1.0:nobs_val),
        :fitted => result.fitted_values,
        :residual => residuals,
        :std_residual => std_residuals,
        :leverage => leverage,
        :cooks_d => cooks_d,
    ), nobs_val)
end

function MetricaBase.predict(result::IVFitResult;
                             newdata::Union{Nothing,Matrix{Float64}}=nothing,
                             interval::Symbol=:none, level::Float64=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    predictions = X * result.coef_values
    interval === :none && return predictions

    n = length(result.response_vector)
    k = length(result.coefficient_names)
    dof_val = n - k
    t_crit = quantile(TDist(dof_val), 1 - (1 - level) / 2)
    sigma = result.glance_table.metrics[:sigma]
    # 使用第二阶段矩阵计算投影，与 2SLS vcov 口径一致
    XtX_inv = inv(result.second_stage_matrix' * result.second_stage_matrix)

    se_pred = if interval === :confidence
        [sqrt(sigma^2 * dot(X[i, :], XtX_inv * X[i, :])) for i in 1:size(X, 1)]
    else
        [sqrt(sigma^2 * (1 + dot(X[i, :], XtX_inv * X[i, :]))) for i in 1:size(X, 1)]
    end

    return (predictions=predictions, lower=predictions .- t_crit .* se_pred, upper=predictions .+ t_crit .* se_pred)
end

"""
    fit(IVModel, formula, data; instruments, endog, vcov, cluster_column)

使用统一接口拟合 IV/2SLS 模型。
"""
function MetricaBase.fit(::Type{IVModel}, formula::AbstractString, data;
                         instruments::Vector{String},
                         endog::Vector{String},
                         vcov::Symbol=:classical,
                         cluster_column::Union{Nothing,Symbol,String}=nothing)
    dataset = if data isa AbstractString
        loaded = load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    model_formula = parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    all_symbols = collect_term_symbols(model_formula)
    response_var = all_symbols[1]
    exog_vars = all_symbols[2:end]

    endog_syms = Symbol.(endog)
    for ev in endog_syms
        ev ∉ exog_vars && return MetricaBase.ModelError(
            :endog_not_in_formula, "内生变量不在公式中",
            "内生变量 $ev 未出现在公式的右侧。",
            "请检查 endog 参数中的变量名是否与公式一致。",
        )
    end

    inst_syms = Symbol.(instruments)
    available = Set(Symbol.(names(dataset)))
    for iv in inst_syms
        iv ∉ available && return MetricaBase.ModelError(
            :unknown_instrument_variable, "工具变量不存在",
            "工具变量 $iv 无法在数据集中找到。",
            "请检查工具变量名是否与数据列一致。",
        )
    end
    for ev in endog_syms
        ev ∉ available && return MetricaBase.ModelError(
            :unknown_endog_variable, "内生变量不存在",
            "内生变量 $ev 无法在数据集中找到。",
            "请检查内生变量名是否与数据列一致。",
        )
    end

    all_vars = unique(vcat([response_var], exog_vars, inst_syms))
    filtered = dataset[completecases(dataset[:, all_vars]), :]
    n_total = nrow(dataset)
    n_effective = nrow(filtered)
    n_effective > 0 || return MetricaBase.ModelError(
        :empty_effective_sample, "有效样本为空",
        "在模型相关列完成缺失值删除后，没有剩余观测可用于拟合。",
        "请检查变量中的缺失情况。",
    )

    nobs = n_effective
    y = Float64.(filtered[!, response_var])

    exog_only = [v for v in exog_vars if v ∉ endog_syms]
    X_exog = hcat(ones(nobs), [Float64.(filtered[!, v]) for v in exog_only]...)
    Z = hcat(ones(nobs), [Float64.(filtered[!, v]) for v in exog_only]...,
             [Float64.(filtered[!, v]) for v in inst_syms]...)
    X_endog = hcat([Float64.(filtered[!, v]) for v in endog_syms]...)

    # 欠识别: 工具变量数 < 内生变量数
    length(inst_syms) >= length(endog_syms) || return MetricaBase.ModelError(
        :underidentified_model, "模型欠识别",
        "工具变量数量 ($(length(inst_syms))) 少于内生变量数量 ($(length(endog_syms)))。",
        "请增加工具变量或减少内生变量。",
    )

    # 秩校验（对 Z 矩阵）
    k_second = length(exog_only) + length(endog_syms)  # 不含截距
    rank(Z) >= k_second + 1 || return MetricaBase.ModelError(
        :weak_rank_condition, "设计矩阵秩不足",
        "工具变量矩阵的秩不足以识别模型参数。",
        "请检查工具变量是否线性相关，或增加有效工具变量。",
    )

    # 自由度
    dof_val = nobs - (k_second + 1)
    dof_val > 0 || return MetricaBase.ModelError(
        :insufficient_degrees_of_freedom, "自由度不足",
        "有效样本量 ($nobs) 不足以支撑参数个数 ($(k_second+1))。",
        "请减少参数或增加样本。",
    )

    # 第一阶段
    Pi = Z \ X_endog
    X_endog_hat = Z * Pi

    # 第一阶段 F 统计量
    first_stage_stats = Dict{Symbol, Float64}()
    weak_warnings = MetricaBase.ModelWarning[]
    k_inst = length(inst_syms)
    k_exog = size(X_exog, 2)

    # 受约束模型：X_endog 仅对外生变量回归
    Pi_exog = X_exog \ X_endog
    X_endog_hat_exog = X_exog * Pi_exog

    for (idx, ev) in enumerate(endog_syms)
        # 无约束模型残差 RSS（外生 + 工具变量）
        resid_fs = X_endog[:, idx] - X_endog_hat[:, idx]
        rss_unrestricted = sum(abs2, resid_fs)
        # 受约束模型残差 RSS（仅外生变量）
        resid_restricted = X_endog[:, idx] - X_endog_hat_exog[:, idx]
        rss_restricted = sum(abs2, resid_restricted)
        # 增量 F 统计量：检验排除工具变量的联合显著性
        f_stat = if iszero(rss_unrestricted)
            Inf
        else
            raw_f = ((rss_restricted - rss_unrestricted) / k_inst) / (rss_unrestricted / (nobs - k_exog - k_inst))
            max(0.0, raw_f)
        end
        first_stage_stats[ev] = f_stat

        if f_stat < 10.0
            push!(weak_warnings, MetricaBase.ModelWarning(
                :weak_instrument, "弱工具变量警告",
                "内生变量 $ev 的第一阶段 F 统计量为 $(round(f_stat, digits=2))，低于 Staiger-Stock 经验阈值 10。",
                "弱工具变量会导致 2SLS 估计量偏误增大、标准误失真。请考虑使用更强的工具变量或 LIML。",
                MetricaBase.warning,
            ))
        end
    end

    # 第二阶段
    X_second = hcat(X_exog, X_endog_hat)
    coefficients = X_second \ y

    # 用原始解释变量计算拟合值和残差（结构残差口径）
    X_original = hcat(X_exog, X_endog)
    fitted = X_original * coefficients
    residuals = y - fitted

    coefficient_names_sym = Symbol.(vcat(["(Intercept)"], string.(exog_only), string.(endog_syms)))

    ncoef = length(coefficients)
    dof_val = nobs - ncoef
    # HC1 使用 GMM 最优 sandwich 口径：bread 与 meat 均反映 Z 投影
    # classical/cluster 仍使用第二阶段矩阵 X_second
    if vcov === :HC1
        vcov_result = compute_vcov(X_original, residuals, nobs, dof_val, vcov, nothing, Z)
    else
        vcov_result = compute_vcov(X_second, residuals, nobs, dof_val, vcov, nothing)
    end
    vcov_result isa MetricaBase.ModelError && return vcov_result
    vcov_mat, stderror = vcov_result

    rss = sum(abs2, residuals)
    tss = sum(abs2, y .- mean(y))
    r2_val = iszero(tss) ? 1.0 : 1 - rss / tss
    adj_r2 = iszero(tss) ? 1.0 : 1 - (rss / dof_val) / (tss / (nobs - 1))
    sigma = sqrt(rss / dof_val)

    # 结构方程整体 F 检验
    model_ss = tss - rss
    model_df = length(coefficients) - 1
    resid_df = dof_val
    f_stat = iszero(rss) ? Inf : (model_ss / model_df) / (rss / resid_df)
    f_pvalue = 1 - cdf(FDist(model_df, resid_df), f_stat)

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, build_rows_dropped_warning(dropped_rows))
    append!(warnings, weak_warnings)

    glance_table = MetricaBase.ModelGlance(:iv, nobs, dof_val,
        Dict{Symbol, MetricaBase.MetricValue}(
            :r2 => r2_val, :adj_r2 => adj_r2, :rss => rss, :tss => tss,
            :sigma => sigma, :f_stat => f_stat, :f_pvalue => f_pvalue),
        warnings)

    statistics = coefficients ./ stderror
    pvalues = 2 .* (1 .- cdf.(TDist(dof_val), abs.(statistics)))
    α = 0.05
    t_crit = quantile(TDist(dof_val), 1 - α / 2)
    vcov_label = vcov === :HC1 ? "HC1" : vcov === :cluster ? "cluster" : "classical"
    tidy_table = MetricaBase.TidyTable([
        MetricaBase.CoefRow(
            coefficient_names_sym[i], coefficients[i], stderror[i],
            statistics[i], pvalues[i],
            coefficients[i] - t_crit * stderror[i],
            coefficients[i] + t_crit * stderror[i])
        for i in eachindex(coefficients)
    ], vcov_label)

    return IVFitResult(String(formula), glance_table, tidy_table,
        coefficient_names_sym, coefficients, vcov_mat, stderror,
        X_original, copy(y), fitted, residuals,
        first_stage_stats, weak_warnings, X_second)
end
