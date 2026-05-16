# === 线性 IV-GMM（一步 / 两步最优权重）========================================

"""
线性 IV-GMM 模型规格（与 IV 相同的数据矩阵构造，估计量为 GMM）。
"""
struct GMMLinearModel <: MetricaBase.AbstractLinearModel
    formula::String
    instruments::Vector{String}
    endog::Vector{String}
end

"""
线性 GMM 拟合结果。
"""
struct GMMLinearFitResult <: MetricaBase.AbstractLinearFitResult
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
    # GMM 诊断：Hansen J、矩条件数、权重矩阵说明等（序列化键名见 runtime-protocol）。
    gmm_diagnostics::Dict{Symbol, Any}
end

MetricaBase.glance(result::GMMLinearFitResult) = result.glance_table
MetricaBase.tidy(result::GMMLinearFitResult) = result.tidy_table
MetricaBase.coef(result::GMMLinearFitResult) = result.coefficient_names .=> result.coef_values
MetricaBase.vcov(result::GMMLinearFitResult) = result.vcov_matrix
MetricaBase.stderror(result::GMMLinearFitResult) = result.stderror_values
MetricaBase.nobs(result::GMMLinearFitResult) = length(result.response_vector)
MetricaBase.dof(result::GMMLinearFitResult) = length(result.response_vector) - length(result.coefficient_names)
MetricaBase.r2(result::GMMLinearFitResult) = result.glance_table.metrics[:r2]
MetricaBase.fitted(result::GMMLinearFitResult) = result.fitted_values
MetricaBase.residuals(result::GMMLinearFitResult) = result.residual_vector

function MetricaBase.augment(result::GMMLinearFitResult)
    nobs_val = length(result.response_vector)
    X = result.design_matrix
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

function MetricaBase.predict(result::GMMLinearFitResult;
                             newdata::Union{Nothing, Matrix{Float64}} = nothing,
                             interval::Symbol = :none, level::Float64 = 0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    predictions = X * result.coef_values
    interval === :none && return predictions

    n = length(result.response_vector)
    k = length(result.coefficient_names)
    dof_val = n - k
    t_crit = quantile(TDist(dof_val), 1 - (1 - level) / 2)
    sigma = result.glance_table.metrics[:sigma]
    XtX_inv = inv(result.design_matrix' * result.design_matrix)

    se_pred = if interval === :confidence
        [sqrt(sigma^2 * dot(X[i, :], XtX_inv * X[i, :])) for i in 1:size(X, 1)]
    else
        [sqrt(sigma^2 * (1 + dot(X[i, :], XtX_inv * X[i, :]))) for i in 1:size(X, 1)]
    end

    return (predictions = predictions, lower = predictions .- t_crit .* se_pred, upper = predictions .+ t_crit .* se_pred)
end

function _load_dataset(path::AbstractString)
    isfile(path) || return MetricaBase.ModelError(
        :dataset_not_found,
        "数据文件不存在",
        "指定的 CSV 文件不存在，无法读取数据。",
        "请确认文件路径后重试。",
    )
    try
        return CSV.read(path, DataFrame)
    catch err
        return MetricaBase.ModelError(
            :csv_parse_failed,
            "CSV 解析失败",
            "CSV 文件无法被正确解析：$(sprint(showerror, err))",
            "请检查分隔符、表头与编码是否正确。",
        )
    end
end

function _parse_gmm_weight(s::AbstractString)
    key = lowercase(strip(String(s)))
    if key == "one_step"
        return :one_step
    elseif key == "two_step"
        return :two_step
    end
    return MetricaBase.ModelError(
        :invalid_gmm_weight,
        "不支持的 GMM 权重步长",
        "gmm_weight 只能为 one_step 或 two_step，收到：$(s)。",
        "请使用 weight(two_step) 或 weight(one_step)。",
    )
end

"""
    fit(GMMLinearModel, formula, data; instruments, endog, gmm_weight)

线性 IV-GMM：`gmm_weight` 为 `"one_step"`（W=(Z'Z)^{-1}）或 `"two_step"`（异方差稳健最优权重）。
"""
function MetricaBase.fit(::Type{GMMLinearModel}, formula::AbstractString, data;
                         instruments::Vector{String},
                         endog::Vector{String},
                         gmm_weight::AbstractString = "two_step")

    wmode = _parse_gmm_weight(gmm_weight)
    wmode isa MetricaBase.ModelError && return wmode

    dataset = if data isa AbstractString
        loaded = _load_dataset(data)
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
            :endog_not_in_formula,
            "内生变量不在公式中",
            "内生变量 $ev 未出现在公式的右侧。",
            "请检查 endog 参数中的变量名是否与公式一致。",
        )
    end

    inst_syms = Symbol.(instruments)
    available = Set(Symbol.(names(dataset)))
    for iv in inst_syms
        iv ∉ available && return MetricaBase.ModelError(
            :unknown_instrument_variable,
            "工具变量不存在",
            "工具变量 $iv 无法在数据集中找到。",
            "请检查工具变量名是否与数据列一致。",
        )
    end
    for ev in endog_syms
        ev ∉ available && return MetricaBase.ModelError(
            :unknown_endog_variable,
            "内生变量不存在",
            "内生变量 $ev 无法在数据集中找到。",
            "请检查内生变量名是否与数据列一致。",
        )
    end

    all_vars = unique(vcat([response_var], exog_vars, inst_syms))
    filtered = dataset[completecases(dataset[:, all_vars]), :]
    n_total = nrow(dataset)
    n_effective = nrow(filtered)
    n_effective > 0 || return MetricaBase.ModelError(
        :empty_effective_sample,
        "有效样本为空",
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
    X = hcat(X_exog, X_endog)

    length(inst_syms) >= length(endog_syms) || return MetricaBase.ModelError(
        :underidentified_model,
        "模型欠识别",
        "工具变量数量 ($(length(inst_syms))) 少于内生变量数量 ($(length(endog_syms)))。",
        "请增加工具变量或减少内生变量。",
    )

    k_second = length(exog_only) + length(endog_syms)
    rank(Z) >= k_second + 1 || return MetricaBase.ModelError(
        :weak_rank_condition,
        "设计矩阵秩不足",
        "工具变量矩阵的秩不足以识别模型参数。",
        "请检查工具变量是否线性相关，或增加有效工具变量。",
    )

    L = size(Z, 2)
    k = size(X, 2)
    L < k && return MetricaBase.ModelError(
        :underidentified_model,
        "模型欠识别",
        "矩条件数 L=$(L) 小于待估参数数 k=$(k)。",
        "请增加外生工具或减少结构方程中的待估系数。",
    )

    # 第一阶段 F（与 IV 相同规则，用于弱工具警告）
    first_stage_stats = Dict{Symbol, Float64}()
    weak_warnings = MetricaBase.ModelWarning[]
    k_inst = length(inst_syms)
    k_exog = size(X_exog, 2)
    Pi = Z \ X_endog
    X_endog_hat = Z * Pi
    Pi_exog = X_exog \ X_endog
    X_endog_hat_exog = X_exog * Pi_exog

    for (idx, ev) in enumerate(endog_syms)
        resid_fs = X_endog[:, idx] - X_endog_hat[:, idx]
        rss_unrestricted = sum(abs2, resid_fs)
        resid_restricted = X_endog[:, idx] - X_endog_hat_exog[:, idx]
        rss_restricted = sum(abs2, resid_restricted)
        f_stat = if iszero(rss_unrestricted)
            Inf
        else
            raw_f = ((rss_restricted - rss_unrestricted) / k_inst) / (rss_unrestricted / (nobs - k_exog - k_inst))
            max(0.0, raw_f)
        end
        first_stage_stats[ev] = f_stat

        if f_stat < 10.0
            push!(weak_warnings, MetricaBase.ModelWarning(
                :weak_instrument,
                "弱工具变量警告",
                "内生变量 $ev 的第一阶段 F 统计量为 $(round(f_stat, digits=2))，低于 Staiger-Stock 经验阈值 10。",
                "弱工具变量会导致 GMM 估计量偏误增大、标准误失真。请考虑使用更强的工具变量。",
                MetricaBase.warning,
            ))
        end
    end

    ZtZ = Z' * Z
    W = _inv_sym_pd(
        ZtZ,
        :singular_weight_matrix,
        "权重矩阵奇异",
        "一步 GMM 权重 (Z'Z)^{-1} 不可逆：",
        "请检查工具变量是否完全共线或样本量是否过小。",
    )
    W isa MetricaBase.ModelError && return W

    local W_final
    local β
    local u

    if wmode === :one_step || (wmode === :two_step && L == k)
        W_final = W
        β = _solve_gmm_beta(X, Z, y, W_final)
        β isa MetricaBase.ModelError && return β
        u = y - X * β
        iterations = 1
        weight_description = if wmode === :one_step
            "one_step: W = (Z'Z)^{-1}"
        else
            "two_step 请求在恰识别 (L=k) 下退化为一步权重：W = (Z'Z)^{-1}（稳健矩协方差 Ω̂ 不可逆，无法构造第二步最优权重）。"
        end
    else
        # 过识别：两步 GMM
        β1 = _solve_gmm_beta(X, Z, y, W)
        β1 isa MetricaBase.ModelError && return β1
        u1 = y - X * β1
        Ω = _moment_covariance(Z, u1, nobs)
        # 异方差稳健 Ω 在小样本上可能接近奇异，做极小对角收缩以保证可逆
        n_Ω = size(Ω, 1)
        jitter = 1e-10 * (tr(Ω) / max(n_Ω, 1) + 1e-12)
        Ωreg = Symmetric(Ω + jitter * I)
        W2 = _inv_sym_pd(
            Ωreg,
            :singular_weight_matrix,
            "权重矩阵奇异",
            "两步 GMM 的稳健矩协方差 Ω 不可逆：",
            "请检查矩条件共线性或第一阶段残差是否退化。",
        )
        W2 isa MetricaBase.ModelError && return W2
        iterations = 2
        weight_description = "two_step: W = Ω̂^{-1}，Ω̂ 为基于第一步残差的异方差稳健矩协方差 (Z'DZ)/n。"
        W_final = W2
        β = _solve_gmm_beta(X, Z, y, W_final)
        β isa MetricaBase.ModelError && return β
        u = y - X * β
    end

    # 协方差：sandwich，Ω 用最终残差
    Ω_hat = _moment_covariance(Z, u, nobs)
    vcov_mat = _gmm_vcov(X, Z, W_final, Ω_hat, nobs)
    vcov_mat isa MetricaBase.ModelError && return vcov_mat

    stderror = sqrt.(max.(0.0, diag(vcov_mat)))

    # Hansen–Sargan J
    g = (Z' * u) ./ nobs
    j_stat = nobs * dot(g, W_final * g)
    overid_df = L - k
    j_pvalue = if overid_df > 0
        1 - cdf(Chisq(overid_df), j_stat)
    else
        nothing
    end

    coefficient_names_sym = Symbol.(vcat(["(Intercept)"], string.(exog_only), string.(endog_syms)))

    rss = sum(abs2, u)
    tss = sum(abs2, y .- mean(y))
    r2_val = iszero(tss) ? 1.0 : 1 - rss / tss
    dof_val = nobs - k
    dof_val > 0 || return MetricaBase.ModelError(
        :insufficient_degrees_of_freedom,
        "自由度不足",
        "有效样本量 ($nobs) 不足以支撑参数个数 ($k)。",
        "请减少参数或增加样本。",
    )
    adj_r2 = iszero(tss) ? 1.0 : 1 - (rss / dof_val) / (tss / (nobs - 1))
    sigma = sqrt(rss / dof_val)

    model_ss = tss - rss
    model_df = k - 1
    resid_df = dof_val
    f_stat = iszero(rss) ? Inf : (model_ss / model_df) / (rss / resid_df)
    f_pvalue = 1 - cdf(FDist(model_df, resid_df), f_stat)

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, build_rows_dropped_warning(dropped_rows))
    append!(warnings, weak_warnings)

    metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :r2 => r2_val,
        :adj_r2 => adj_r2,
        :rss => rss,
        :tss => tss,
        :sigma => sigma,
        :f_stat => f_stat,
        :f_pvalue => f_pvalue,
        :j_stat => j_stat,
        :j_df => Float64(overid_df),
        :n_moments => Float64(L),
        :n_params => Float64(k),
    )
    if overid_df > 0 && !isnothing(j_pvalue)
        metrics[:j_pvalue] = j_pvalue
    end

    glance_table = MetricaBase.ModelGlance(:gmm_linear, nobs, dof_val, metrics, warnings)

    statistics = β ./ stderror
    pvalues = 2 .* (1 .- cdf.(TDist(dof_val), abs.(statistics)))
    α = 0.05
    t_crit = quantile(TDist(dof_val), 1 - α / 2)
    tidy_table = MetricaBase.TidyTable([
        MetricaBase.CoefRow(
            coefficient_names_sym[i], β[i], stderror[i],
            statistics[i], pvalues[i],
            β[i] - t_crit * stderror[i],
            β[i] + t_crit * stderror[i],
        )
        for i in eachindex(β)
    ], "GMM $(wmode === :one_step ? "one_step" : "two_step")")

    gmm_diag = Dict{Symbol, Any}(
        :j_statistic => j_stat,
        :j_df => overid_df,
        :j_pvalue => j_pvalue,
        :n_moments => L,
        :n_params => k,
        :overidentifying_restrictions => overid_df,
        :gmm_weight => wmode === :one_step ? "one_step" : "two_step",
        :weight_matrix_description => weight_description,
        :iterations => iterations,
        :exactly_identified => overid_df == 0,
    )

    return GMMLinearFitResult(
        String(formula),
        glance_table,
        tidy_table,
        coefficient_names_sym,
        β,
        vcov_mat,
        stderror,
        X,
        copy(y),
        X * β,
        u,
        first_stage_stats,
        weak_warnings,
        gmm_diag,
    )
end
