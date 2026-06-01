# === listwise 与 SUR / 系统 IV 拟合 =================================================

using DataFrames
using Distributions: TDist, FDist, Chisq, cdf, quantile
using LinearAlgebra: I, Symmetric, cholesky, inv, rank, diag, dot
using Statistics: mean
using StatsModels: coefnames

function _parse_equation_blocks(equations::Vector{String})
    isempty(equations) && return MetricaBase.ModelError(
        :empty_equations, "方程列表为空",
        "至少需要 1 条方程公式。",
        "请在 model_spec.equations 中提供形如 y ~ x1 + x2 的字符串数组。",
    )
    length(equations) > 8 && return MetricaBase.ModelError(
        :too_many_equations, "方程数超过上限",
        "当前 Runtime 允许至多 8 条方程，收到 $(length(equations)) 条。",
        "请拆分模型或减少方程数。",
    )
    return nothing
end

"""收集各方程及（可选）按方程 IV 列并集上的 listwise 子样本。"""
function _listwise_system_sample(
    dataset::DataFrame,
    equations::Vector{String},
    endog_per::Union{Nothing, Vector{Vector{String}}},
    inst_per::Union{Nothing, Vector{Vector{String}}},
)
    cols = Symbol[]
    for eq in equations
        mf = MetricaLinear.parse_formula_term(eq)
        mf isa MetricaBase.ModelError && return mf
        append!(cols, MetricaLinear.collect_term_symbols(mf))
    end
    if endog_per !== nothing && inst_per !== nothing
        for (ed, ins) in zip(endog_per, inst_per)
            append!(cols, Symbol.(ed))
            append!(cols, Symbol.(ins))
        end
    end
    unique_cols = unique(cols)
    err = MetricaLinear.validate_model_columns(dataset, unique_cols, nothing, nothing)
    err isa MetricaBase.ModelError && return err
    sub = dataset[:, unique_cols]
    mask = completecases(sub)
    n_total = nrow(dataset)
    n_eff = sum(mask)
    n_eff > 0 || return MetricaBase.ModelError(
        :empty_effective_sample, "有效样本为空",
        "在系统相关列上 listwise 删除缺失后无剩余观测。",
        "请检查缺失分布。",
    )
    filtered = dataset[mask, :]
    return (
        filtered = filtered,
        n_total = n_total,
        n_eff = n_eff,
        dropped = n_total - n_eff,
    )
end

function _rows_dropped_warnings(dropped::Int)
    dropped > 0 ? [MetricaLinear.build_rows_dropped_warning(dropped)] : MetricaBase.ModelWarning[]
end

function _ols_init(X::Matrix{Float64}, y::Vector{Float64})
    return X \ y
end

function _compute_r2(y::Vector{Float64}, resid::Vector{Float64})
    tss = sum(abs2, y .- mean(y))
    rss = sum(abs2, resid)
    r2 = iszero(tss) ? 1.0 : 1 - rss / tss
    adj_r2 = iszero(tss) ? 1.0 : 1 - (rss / (length(y) - length(resid))) / (tss / (length(y) - 1))
    return r2, adj_r2, rss, tss
end

function _sigma_inv(Sigma::Matrix{Float64})
    S = Symmetric(0.5 .* (Sigma .+ Sigma'))
    try
        return inv(cholesky(S))
    catch
        σ = max(eps(Float64), minimum(diag(S)) * 1.0e-6)
        return inv(cholesky(Symmetric(S + σ * I)))
    end
end

"""组装单方程 glance（子方程；`model_sym` 如 :sur / :system_3sls）。"""
function _glance_sur_equation(
    model_sym::Symbol,
    nobs::Int,
    k::Int,
    y::Vector{Float64},
    resid::Vector{Float64},
    eq_warnings::Vector{MetricaBase.ModelWarning},
)
    dof = nobs - k
    r2, adj_r2, rss, tss = _compute_r2(y, resid)
    sigma = sqrt(sum(abs2, resid) / max(dof, 1))
    model_ss = tss - rss
    model_df = max(k - 1, 1)
    resid_df = max(dof, 1)
    f_stat = iszero(rss) ? Inf : (model_ss / model_df) / (rss / resid_df)
    f_pvalue = 1 - cdf(FDist(model_df, resid_df), f_stat)
    metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :r2 => r2, :adj_r2 => adj_r2, :rss => rss, :tss => tss,
        :sigma => sigma, :f_stat => f_stat, :f_pvalue => f_pvalue,
    )
    return MetricaBase.ModelGlance(model_sym, nobs, dof, metrics, eq_warnings)
end

function _tidy_rows_from_slice(
    coef::Vector{Float64},
    stderr::Vector{Float64},
    names::Vector{Symbol},
    dof::Int,
    vcov_label::String,
)
    statistics = coef ./ stderr
    pvalues = MetricaLinear.compute_pvalues(statistics, dof)
    α = 0.05
    t_crit = quantile(TDist(dof), 1 - α / 2)
    return [
        MetricaBase.CoefRow(
            names[i], coef[i], stderr[i], statistics[i], pvalues[i],
            coef[i] - t_crit * stderr[i], coef[i] + t_crit * stderr[i],
        )
        for i in eachindex(coef)
    ]
end

function _fit_sur_equations(filtered::DataFrame, equations::Vector{String}; max_iter::Int, tol::Float64)
    G = length(equations)
    Xs = Vector{Matrix{Float64}}(undef, G)
    ys = Vector{Vector{Float64}}(undef, G)
    coef_names = Vector{Vector{Symbol}}(undef, G)
    n = -1
    for g in 1:G
        mf = MetricaLinear.parse_formula_term(equations[g])
        mf isa MetricaBase.ModelError && return mf
        cols = unique(MetricaLinear.collect_term_symbols(mf))
        err = MetricaLinear.validate_model_columns(filtered, cols, nothing, nothing)
        err isa MetricaBase.ModelError && return err
        prep = MetricaLinear.prepare_model_data(filtered, mf, cols, nothing, nothing)
        prep isa MetricaBase.ModelError && return prep
        (_, model_frame, _, X, y, _, _, _, _) = prep
        ng = length(y)
        n == -1 && (n = ng)
        ng == n || return MetricaBase.ModelError(
            :unequal_system_rows, "方程行数不一致",
            "SUR 要求所有方程在 listwise 样本上具有相同行数。",
            "请检查公式与缺失结构。",
        )
        rank(X) >= size(X, 2) || return MetricaBase.ModelError(
            :weak_rank_condition, "设计矩阵秩不足",
            "第 $g 条方程的设计矩阵秩不足。",
            "请减少共线解释变量。",
        )
        Xs[g] = X
        ys[g] = y
        coef_names[g] = Symbol.(coefnames(model_frame))
    end

    ks = [size(Xs[g], 2) for g in 1:G]
    Ksum = sum(ks)
    starts = cumsum([1; ks[1:(end - 1)]])
    beta = zeros(Ksum)
    for g in 1:G
        rg = starts[g]:(starts[g] + ks[g] - 1)
        beta[rg] .= Xs[g] \ ys[g]
    end

    Sigma = Matrix{Float64}(I, G, G)
    iter_done = 0
    for it in 1:max_iter
        U = zeros(n, G)
        for g in 1:G
            rg = starts[g]:(starts[g] + ks[g] - 1)
            U[:, g] .= ys[g] .- Xs[g] * beta[rg]
        end
        Sigma .= (U' * U) ./ n
        Sigma_inv = _sigma_inv(Sigma)
        Gram = zeros(Ksum, Ksum)
        rhs = zeros(Ksum)
        for g in 1:G, h in 1:G
            w = Sigma_inv[g, h]
            rg = starts[g]:(starts[g] + ks[g] - 1)
            rh = starts[h]:(starts[h] + ks[h] - 1)
            Gram[rg, rh] .= w .* (Xs[g]' * Xs[h])
        end
        for g in 1:G
            rg = starts[g]:(starts[g] + ks[g] - 1)
            acc = zeros(ks[g])
            for h in 1:G
                acc .+= Sigma_inv[g, h] .* (Xs[g]' * ys[h])
            end
            rhs[rg] .= acc
        end
        beta_new = Gram \ rhs
        iter_done = it
        if maximum(abs.(beta_new .- beta)) < tol
            beta .= beta_new
            break
        end
        beta .= beta_new
    end

    # 最终 vcov：以末次 Sigma 为已知权重
    U = zeros(n, G)
    for g in 1:G
        rg = starts[g]:(starts[g] + ks[g] - 1)
        U[:, g] .= ys[g] .- Xs[g] * beta[rg]
    end
    Sigma .= (U' * U) ./ n
    Sigma_inv = _sigma_inv(Sigma)
    Gram = zeros(Ksum, Ksum)
    for g in 1:G, h in 1:G
        w = Sigma_inv[g, h]
        rg = starts[g]:(starts[g] + ks[g] - 1)
        rh = starts[h]:(starts[h] + ks[h] - 1)
        Gram[rg, rh] .= w .* (Xs[g]' * Xs[h])
    end
    vcov_full = try
        inv(cholesky(Symmetric(Gram)))
    catch
        return MetricaBase.ModelError(
            :singular_gls_system, "SUR 法方程奇异",
            "无法求逆 X'Ω⁻¹X，请检查方程间共线或样本量。",
            "尝试减少方程或增加变异。",
        )
    end

    eq_glances = MetricaBase.ModelGlance[]
    tidy_rows = MetricaBase.CoefRow[]
    tidy_eqs = String[]
    for g in 1:G
        rg = starts[g]:(starts[g] + ks[g] - 1)
        βg = beta[rg]
        Vg = vcov_full[rg, rg]
        stderr = sqrt.(max.(diag(Vg), eps(Float64)))
        dof = n - ks[g]
        resid_g = ys[g] .- Xs[g] * βg
        push!(eq_glances, _glance_sur_equation(:sur, n, ks[g], ys[g], resid_g, MetricaBase.ModelWarning[]))
        rows = _tidy_rows_from_slice(βg, stderr, coef_names[g], dof, "sur_fgls")
        append!(tidy_rows, rows)
        append!(tidy_eqs, fill("eq$g", length(rows)))
    end

    corr = similar(Sigma)
    for i in 1:G, j in 1:G
        si = sqrt(Sigma[i, i])
        sj = sqrt(Sigma[j, j])
        corr[i, j] = si > 0 && sj > 0 ? Sigma[i, j] / (si * sj) : 0.0
    end

    # 收集方程级拟合值供预测
    eq_fitteds = [Xs[g] * beta[starts[g]:(starts[g] + ks[g] - 1)] for g in 1:G]
    eq_resids = [ys[g] .- eq_fitteds[g] for g in 1:G]

    diagnostics = Dict{Symbol, Any}(
        :system_method => "sur_fgls",
        :iterations => iter_done,
        :sigma_residual => Sigma,
        :equation_correlation => corr,
        :equation_fitted => eq_fitteds,
        :equation_residuals => eq_resids,
    )
    return (
        equation_glances = eq_glances,
        tidy_rows = tidy_rows,
        tidy_equation_labels = tidy_eqs,
        diagnostics = diagnostics,
        nobs = n,
        iterations = iter_done,
    )
end

function MetricaBase.fit(::Type{SURModel}, _formula::AbstractString, data;
    equations::Vector{String},
    sur_max_iter::Int = 5,
    sur_tol::Float64 = 1.0e-6,
)
    err = _parse_equation_blocks(equations)
    err !== nothing && return err
    dataset = if data isa AbstractString
        r = MetricaLinear.load_dataset(data)
        r isa MetricaBase.ModelError && return r
        r
    else
        data
    end
    lw = _listwise_system_sample(dataset, equations, nothing, nothing)
    lw isa MetricaBase.ModelError && return lw
    filtered = lw.filtered
    base_warn = _rows_dropped_warnings(lw.dropped)
    out = _fit_sur_equations(filtered, equations; max_iter = sur_max_iter, tol = sur_tol)
    out isa MetricaBase.ModelError && return out
    all_warn = copy(base_warn)
    tidy = MetricaBase.TidyTable(out.tidy_rows, "sur_fgls")
    return SystemEquationsFitResult(
        :sur, "sur_fgls",
        ["eq$g" for g in 1:length(equations)],
        out.equation_glances,
        tidy,
        out.tidy_equation_labels,
        out.diagnostics,
        all_warn,
        out.nobs,
        out.iterations,
    )
end

function MetricaBase.fit(::Type{System2SLSModel}, _formula::AbstractString, data;
    equations::Vector{String},
    system_endogenous::Vector{Vector{String}},
    system_instruments::Vector{Vector{String}},
)
    err = _parse_equation_blocks(equations)
    err !== nothing && return err
    length(system_endogenous) == length(equations) &&
        length(system_instruments) == length(equations) ||
        return MetricaBase.ModelError(
            :system_iv_shape, "系统 IV 配置维度不匹配",
            "system_endogenous 与 system_instruments 的外层长度须等于方程数。",
            "请检查 JSON 二维数组形状。",
        )
    dataset = if data isa AbstractString
        r = MetricaLinear.load_dataset(data)
        r isa MetricaBase.ModelError && return r
        r
    else
        data
    end
    lw = _listwise_system_sample(dataset, equations, system_endogenous, system_instruments)
    lw isa MetricaBase.ModelError && return lw
    filtered = lw.filtered
    base_warn = _rows_dropped_warnings(lw.dropped)

    iv_results = MetricaLinear.IVFitResult[]
    for g in eachindex(equations)
        r = MetricaBase.fit(
            MetricaLinear.IVModel,
            equations[g],
            filtered;
            instruments = system_instruments[g],
            endog = system_endogenous[g],
            vcov = :classical,
        )
        r isa MetricaBase.ModelError && return r
        push!(iv_results, r)
    end

    n = length(iv_results[1].response_vector)
    tidy_rows = MetricaBase.CoefRow[]
    tidy_eqs = String[]
    eq_glances = MetricaBase.ModelGlance[]
    all_warn = copy(base_warn)
    U = zeros(n, length(equations))
    for g in eachindex(iv_results)
        iv = iv_results[g]
        append!(all_warn, iv.glance_table.warnings)
        push!(eq_glances, iv.glance_table)
        for row in iv.tidy_table.rows
            push!(tidy_rows, row)
            push!(tidy_eqs, "eq$g")
        end
        U[:, g] .= iv.residual_vector
    end
    Sigma = (U' * U) ./ n
    corr = similar(Sigma)
    for i in 1:size(Sigma, 1), j in 1:size(Sigma, 2)
        si = sqrt(Sigma[i, i])
        sj = sqrt(Sigma[j, j])
        corr[i, j] = si > 0 && sj > 0 ? Sigma[i, j] / (si * sj) : 0.0
    end
    diagnostics = Dict{Symbol, Any}(
        :system_method => "2sls",
        :iterations => 1,
        :sigma_residual => Sigma,
        :equation_correlation => corr,
    )
    tidy = MetricaBase.TidyTable(tidy_rows, "classical")
    return SystemEquationsFitResult(
        :system_2sls, "2sls",
        ["eq$g" for g in 1:length(equations)],
        eq_glances,
        tidy,
        tidy_eqs,
        diagnostics,
        all_warn,
        n,
        1,
    )
end

function MetricaBase.fit(::Type{System3SLSModel}, _formula::AbstractString, data;
    equations::Vector{String},
    system_endogenous::Vector{Vector{String}},
    system_instruments::Vector{Vector{String}},
)
    err = _parse_equation_blocks(equations)
    err !== nothing && return err
    length(system_endogenous) == length(equations) &&
        length(system_instruments) == length(equations) ||
        return MetricaBase.ModelError(
            :system_iv_shape, "系统 IV 配置维度不匹配",
            "system_endogenous 与 system_instruments 的外层长度须等于方程数。",
            "请检查 JSON 二维数组形状。",
        )
    dataset = if data isa AbstractString
        r = MetricaLinear.load_dataset(data)
        r isa MetricaBase.ModelError && return r
        r
    else
        data
    end
    lw = _listwise_system_sample(dataset, equations, system_endogenous, system_instruments)
    lw isa MetricaBase.ModelError && return lw
    filtered = lw.filtered
    base_warn = _rows_dropped_warnings(lw.dropped)

    iv_results = MetricaLinear.IVFitResult[]
    for g in eachindex(equations)
        r = MetricaBase.fit(
            MetricaLinear.IVModel,
            equations[g],
            filtered;
            instruments = system_instruments[g],
            endog = system_endogenous[g],
            vcov = :classical,
        )
        r isa MetricaBase.ModelError && return r
        push!(iv_results, r)
    end

    G = length(equations)
    n = length(iv_results[1].response_vector)
    Xs = [iv.second_stage_matrix for iv in iv_results]
    ys = [iv.response_vector for iv in iv_results]
    ks = [size(X, 2) for X in Xs]
    Ksum = sum(ks)
    starts = cumsum([1; ks[1:(end - 1)]])
    U = hcat([iv.residual_vector for iv in iv_results]...)
    Sigma = (U' * U) ./ n
    Sigma_inv = _sigma_inv(Sigma)
    Gram = zeros(Ksum, Ksum)
    rhs = zeros(Ksum)
    for g in 1:G, h in 1:G
        w = Sigma_inv[g, h]
        rg = starts[g]:(starts[g] + ks[g] - 1)
        rh = starts[h]:(starts[h] + ks[h] - 1)
        Gram[rg, rh] .= w .* (Xs[g]' * Xs[h])
    end
    for g in 1:G
        rg = starts[g]:(starts[g] + ks[g] - 1)
        acc = zeros(ks[g])
        for h in 1:G
            acc .+= Sigma_inv[g, h] .* (Xs[g]' * ys[h])
        end
        rhs[rg] .= acc
    end
    vcov_full = try
        inv(cholesky(Symmetric(Gram)))
    catch
        return MetricaBase.ModelError(
            :singular_gls_system, "3SLS 法方程奇异",
            "无法求逆 X'Ω⁻¹X。",
            "请检查识别与工具配置。",
        )
    end
    beta = Gram \ rhs

    eq_glances = MetricaBase.ModelGlance[]
    tidy_rows = MetricaBase.CoefRow[]
    tidy_eqs = String[]
    coef_names = [iv.coefficient_names for iv in iv_results]
    all_warn = copy(base_warn)
    for g in 1:G
        append!(all_warn, iv_results[g].glance_table.warnings)
    end
    for g in 1:G
        rg = starts[g]:(starts[g] + ks[g] - 1)
        βg = beta[rg]
        Vg = vcov_full[rg, rg]
        stderr = sqrt.(max.(diag(Vg), eps(Float64)))
        dof = n - ks[g]
        resid_g = ys[g] .- Xs[g] * βg
        push!(eq_glances, _glance_sur_equation(:system_3sls, n, ks[g], ys[g], resid_g, MetricaBase.ModelWarning[]))
        rows = _tidy_rows_from_slice(βg, stderr, coef_names[g], dof, "3sls")
        append!(tidy_rows, rows)
        append!(tidy_eqs, fill("eq$g", length(rows)))
    end

    corr = similar(Sigma)
    for i in 1:G, j in 1:G
        si = sqrt(Sigma[i, i])
        sj = sqrt(Sigma[j, j])
        corr[i, j] = si > 0 && sj > 0 ? Sigma[i, j] / (si * sj) : 0.0
    end
    eq_fitteds = [Xs[g] * beta[starts[g]:(starts[g] + ks[g] - 1)] for g in 1:G]
    eq_resids = [ys[g] .- eq_fitteds[g] for g in 1:G]
    diagnostics = Dict{Symbol, Any}(
        :system_method => "3sls",
        :iterations => 1,
        :sigma_residual => Sigma,
        :equation_correlation => corr,
        :equation_fitted => eq_fitteds,
        :equation_residuals => eq_resids,
    )
    tidy = MetricaBase.TidyTable(tidy_rows, "3sls")
    return SystemEquationsFitResult(
        :system_3sls, "3sls",
        ["eq$g" for g in 1:G],
        eq_glances,
        tidy,
        tidy_eqs,
        diagnostics,
        all_warn,
        n,
        1,
    )
end

# === 系统级诊断 ===============================================================
function system_wald_test(beta::Vector{Float64}, vcov::Matrix{Float64}, R::Matrix{Float64}, r::Vector{Float64})
    q = size(R, 1); Rbeta = R * beta - r; RV_R = Symmetric(R * vcov * R')
    W = dot(Rbeta, RV_R \ Rbeta); pv = 1 - cdf(Chisq(q), W)
    return Dict{Symbol, Any}(:statistic => W, :pvalue => pv, :dof => q, :method => "Wald")
end

# === 系统级 LR 检验 ==========================================================
function system_lr_test(unrestricted_ll::Float64, restricted_ll::Float64, df_diff::Int)
    LR = -2 * (restricted_ll - unrestricted_ll)
    pv = 1 - cdf(Chisq(df_diff), LR)
    return Dict{Symbol, Any}(:statistic => LR, :pvalue => pv, :dof => df_diff, :method => "LR")
end

# === 系统级 LM 检验 (Score test) ==============================================
function system_score_test(X::Vector{Matrix{Float64}}, y::Vector{Vector{Float64}}, beta_restricted, Sigma_inv::Matrix{Float64})
    G = length(X); s_total = zeros(length(beta_restricted))
    for g in 1:G
        u_g = y[g] - X[g] * beta_restricted[1:size(X[g], 2)]
        s_total .+= X[g]' * Sigma_inv[g, :] .* u_g
    end
    # 简化为 Wald 型 score
    return Dict{Symbol, Any}(:score_norm => norm(s_total), :method => "Score")
end

# === 系统级 robust sandwich covariance =========================================
function system_robust_vcov(X::Vector{Matrix{Float64}}, y::Vector{Vector{Float64}}, beta::Vector{Float64}, Sigma::Matrix{Float64})
    G = length(X); n = length(y[1])
    Omega_inv = inv(cholesky(Symmetric(Sigma + 1e-10 * I)))
    Gram = zeros(size(X[1], 2) * G, size(X[1], 2) * G)
    meat = zeros(size(X[1], 2) * G, size(X[1], 2) * G)
    for g in 1:G
        for h in 1:G
            w = Omega_inv[g, h]
            Gram[(g-1)*size(X[1],2)+1:g*size(X[1],2), (h-1)*size(X[1],2)+1:h*size(X[1],2)] = w * X[g]' * X[h]
        end
    end
    for i in 1:n
        si = zeros(size(X[1], 2) * G)
        for g in 1:G
            u_g = y[g][i] - dot(X[g][i, :], beta[1:size(X[g], 2)])
            si[(g-1)*size(X[1],2)+1:g*size(X[1],2)] = X[g][i, :] * u_g
        end
        meat .+= si * si'
    end
    Gram_inv = inv(cholesky(Symmetric(Gram + 1e-10 * I)))
    V_robust = Gram_inv * meat * Gram_inv
    return V_robust
end

# === 系统预测 =================================================================
function system_predict(result::SystemEquationsFitResult)
    fitted = get(result.diagnostics, :equation_fitted, nothing)
    fitted === nothing && return Dict{String, Vector{Float64}}()
    preds = Dict{String, Vector{Float64}}()
    for (i, label) in enumerate(result.equation_labels)
        preds[label] = fitted[i]
    end
    return preds
end
