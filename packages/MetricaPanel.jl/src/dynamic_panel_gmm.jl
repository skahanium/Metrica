# === Arellano–Bond 差分 GMM（首期：Difference GMM）===========================

"""
动态面板 GMM 模型规格（仅用于 `MODEL_REGISTRY` 与 Runtime 派发，字段由 `fit` kwargs 提供）。
"""
struct DynamicPanelGMMModel <: MetricaBase.AbstractPanelModel end

"""
差分 GMM 拟合结果（堆叠一阶差分方程；`fitted_values` 与 `residual_vector` 均在差分空间）。
"""
struct DynamicPanelGMMFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    panel_data::MetricaBase.PanelData
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    diagnostics::Dict{Symbol, Any}
    gmm_diagnostics::Dict{Symbol, Any}
    instrument_lags::Tuple{Int, Int}
    n_instruments::Int
    n_obs_diff::Int
end

MetricaBase.glance(result::DynamicPanelGMMFitResult) = result.glance_table
MetricaBase.tidy(result::DynamicPanelGMMFitResult) = result.tidy_table
MetricaBase.coef(result::DynamicPanelGMMFitResult) = result.coefficient_names .=> result.coefficient_values

function MetricaBase.augment(result::DynamicPanelGMMFitResult)
    nobs = length(result.fitted_values)
    k = length(result.coefficient_names)
    dof = nobs - k
    cols = Dict{Symbol, Vector{Float64}}(
        :observation => collect(1.0:nobs),
        :fitted => result.fitted_values,
        :residual => result.residual_vector,
    )
    if dof > 0
        sigma = sqrt(sum(abs2, result.residual_vector) / dof)
        sigma > 0 && (cols[:std_residual] = result.residual_vector ./ sigma)
    end
    return MetricaBase.AugmentTable(cols, nobs)
end

function _collect_rhs_exog_syms!(out::Vector{Symbol}, rhs::Any)
    if rhs isa StatsModels.Term
        push!(out, rhs.sym)
        return out
    end
    if rhs isa StatsModels.ConstantTerm
        return out
    end
    if rhs isa Tuple
        for p in rhs
            _collect_rhs_exog_syms!(out, p)
        end
        return out
    end
    if hasproperty(rhs, :lhs)
        _collect_rhs_exog_syms!(out, getproperty(rhs, :lhs))
    end
    if hasproperty(rhs, :rhs)
        _collect_rhs_exog_syms!(out, getproperty(rhs, :rhs))
    end
    return out
end

"""
对差分残差做「按个体聚类矩」的 Arellano–Bond 型 AR(`lag`) 检验（渐近正态）。
方差为各截面个体上同一滞后矩贡献的平方和（与主流软件小样本校正可能略有差异）。
"""
function _clustered_moment_ar_test(
    u::Vector{Float64},
    gid::Vector{Int},
    tloc::Vector{Int},
    lag::Int,
)::Tuple{Float64, Float64}
    groups = Dict{Int, Vector{Tuple{Int, Float64}}}()
    for i in eachindex(u)
        push!(get!(groups, gid[i], []), (tloc[i], u[i]))
    end
    S_total = 0.0
    Q = 0.0
    for g in values(groups)
        sort!(g, by = x -> x[1])
        uv = [x[2] for x in g]
        Sg = 0.0
        for j in (lag + 1):length(uv)
            Sg += uv[j] * uv[j - lag]
        end
        S_total += Sg
        Q += Sg^2
    end
    se = sqrt(Q + 1e-20)
    z = S_total / se
    p = 2 * (1 - cdf(Normal(0.0, 1.0), abs(z)))
    return z, p
end

function fit_dynamic_panel_gmm(
    panel_data::MetricaBase.PanelData,
    formula::String;
    instrument_lags::Tuple{Int, Int} = (2, 4),
    gmm_weight::AbstractString = "two_step",
    dpgmm_style::AbstractString = "difference",
    collapse_instruments::Bool = false,
)
    collapse_instruments && return MetricaBase.ModelError(
        :not_implemented,
        "collapse_instruments 尚未实现",
        "首期差分 GMM 不支持折叠工具集。",
        "请使用 collapse_instruments=false，或等待后续版本。",
    )
    style = lowercase(strip(String(dpgmm_style)))
    if style == "system"
        return MetricaBase.ModelError(
            :not_implemented,
            "System GMM 尚未实现",
            "首期仅支持差分 GMM（Arellano–Bond）。",
            "请将 dpgmm_style 设为 difference。",
        )
    end
    if style != "difference"
        return MetricaBase.ModelError(
            :invalid_dpgmm_style,
            "不支持的 dpgmm_style",
            "收到：$(dpgmm_style)。首期仅支持 difference。",
            "请使用 dpgmm_style=difference。",
        )
    end

    min_lag, max_lag = instrument_lags
    if min_lag < 1 || max_lag < min_lag
        return MetricaBase.ModelError(
            :invalid_instrument_lags,
            "instrument_lags 非法",
            "要求 1 ≤ min_lag ≤ max_lag，收到 ($(min_lag), $(max_lag))。",
            "请使用如 [2, 4] 的整数对。",
        )
    end

    gw = lowercase(strip(String(gmm_weight)))
    wsym = if gw == "one_step"
        :one_step
    elseif gw == "two_step"
        :two_step
    else
        return MetricaBase.ModelError(
            :invalid_gmm_weight,
            "不支持的 gmm_weight",
            "仅支持 one_step 或 two_step，收到：$(gmm_weight)。",
            "请省略该字段以使用默认 two_step。",
        )
    end

    fterm = MetricaLinear.parse_formula_term(formula)
    fterm isa MetricaBase.ModelError && return fterm
    if !hasproperty(fterm, :lhs) || !hasproperty(fterm, :rhs)
        return MetricaBase.ModelError(
            :formula_invalid,
            "公式结构无效",
            "动态面板 GMM 需要形如 y ~ x1 + x2 的公式。",
            "请检查公式左侧因变量与右侧严格外生解释变量。",
        )
    end
    lhs = fterm.lhs
    lhs isa StatsModels.Term || return MetricaBase.ModelError(
        :formula_invalid,
        "因变量须为单列符号",
        "公式左侧不是简单项。",
        "请使用 y ~ ... 形式。",
    )
    y_sym = lhs.sym
    exog_syms = unique(_collect_rhs_exog_syms!(Symbol[], fterm.rhs))

    data = DataFrame(panel_data.data)
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    need_cols = unique(vcat([y_sym], collect(exog_syms), [id_col, time_col]))
    for c in need_cols
        c ∉ propertynames(data) && return MetricaBase.ModelError(
            :unknown_column,
            "列不存在",
            "列 $(c) 不在面板数据中。",
            "请检查公式与 CSV 表头。",
        )
    end

    sub = select(data, need_cols)
    dropmissing!(sub)
    isempty(sub) && return MetricaBase.ModelError(
        :empty_sample,
        "有效样本为空",
        "删失缺失后无观测可用于差分 GMM。",
        "请检查缺失值与时期覆盖。",
    )

    sort!(sub, [id_col, time_col])
    raw_ids = sub[!, id_col]
    uid_list = unique(raw_ids)
    id_int_map = Dict{Any, Int}(uid => i for (i, uid) in enumerate(uid_list))
    n_groups = length(uid_list)

    # 每个截面内时期秩（1..T_i），用于 AR 检验排序
    t_local = zeros(Int, nrow(sub))
    for uid in uid_list
        m = raw_ids .== uid
        t_local[m] .= 1:count(m)
    end
    gid_row = [id_int_map[v] for v in raw_ids]

    n_lag_inst = max_lag - min_lag + 1
    n_exog = length(exog_syms)
    L = n_lag_inst + n_exog
    k = 1 + n_exog

    diff_y = Float64[]
    Xrows = Vector{Float64}[]
    Zrows = Vector{Float64}[]
    stack_gid = Int[]
    stack_tloc = Int[]

    for uid in uid_list
        m = raw_ids .== uid
        rows_idx = findall(m)
        ys = Float64.(sub[m, y_sym])
        Xex = isempty(exog_syms) ? zeros(Float64, length(ys), 0) :
              Matrix(Float64.(hcat([sub[m, x] for x in exog_syms]...)))
        T = length(ys)
        T < max_lag + 1 && continue
        for t in (max_lag + 1):T
            dy = ys[t] - ys[t - 1]
            dyl1 = ys[t - 1] - ys[t - 2]
            if n_exog > 0
                dx = Xex[t, :] .- Xex[t - 1, :]
            else
                dx = Float64[]
            end
            zlags = Float64[ys[t - ell] for ell in min_lag:max_lag]
            if !(isfinite(dy) && isfinite(dyl1) && all(isfinite, zlags) && all(isfinite, dx))
                continue
            end
            zrow = vcat(zlags, dx)
            xrow = vcat(dyl1, dx)
            push!(diff_y, dy)
            push!(Xrows, xrow)
            push!(Zrows, zrow)
            global_row = rows_idx[t]
            push!(stack_gid, gid_row[global_row])
            push!(stack_tloc, t_local[global_row])
        end
    end

    n_diff = length(diff_y)
    n_diff < k && return MetricaBase.ModelError(
        :insufficient_panel_depth,
        "差分样本不足",
        "有效差分观测 $(n_diff) 少于参数个数 $(k)（需更长面板或放宽 instrument_lags）。",
        "请增加时期或减小 max_lag。",
    )

    Xstack = zeros(Float64, n_diff, k)
    Zstack = zeros(Float64, n_diff, L)
    for i in 1:n_diff
        Xstack[i, :] = Xrows[i]
        Zstack[i, :] = Zrows[i]
    end
    ystack = diff_y

    gmm_res = MetricaGMM.linear_iv_gmm_stack(ystack, Xstack, Zstack; gmm_weight = wsym)
    gmm_res isa MetricaBase.ModelError && return gmm_res

    β = gmm_res.coef
    vcov_mat = gmm_res.vcov
    stderror = gmm_res.stderror
    u = gmm_res.residual
    fitted = Xstack * β

    coef_names = vcat([:L1Dy], [Symbol("D_", x) for x in exog_syms])

    z1, p1 = _clustered_moment_ar_test(u, stack_gid, stack_tloc, 1)
    z2, p2 = _clustered_moment_ar_test(u, stack_gid, stack_tloc, 2)

    # 弱工具：将 Δy_{t-1} 对全部工具做第一阶段式 F（教学用 Staiger–Stock 阈值）
    dyl1_col = Xstack[:, 1]
    Pi_fs = Zstack \ dyl1_col
    u_fs = dyl1_col - Zstack * Pi_fs
    rss_u = sum(abs2, u_fs)
    rss_r = sum(abs2, dyl1_col .- mean(dyl1_col))
    q_excl = n_lag_inst
    denom_df = max(n_diff - L, 1)
    f_l1dy = if iszero(rss_u) || q_excl <= 0
        NaN
    else
        max(0.0, ((rss_r - rss_u) / q_excl) / (rss_u / denom_df))
    end
    first_stage_stats = Dict{Symbol, Float64}(:L1Dy => max(0.0, f_l1dy))

    warnings = MetricaBase.ModelWarning[]
    if f_l1dy < 10.0 && isfinite(f_l1dy)
        push!(warnings, MetricaBase.ModelWarning(
            :weak_instrument,
            "弱工具变量提示",
            "滞后一阶差分因变量对工具矩阵的第一阶段 F 为 $(round(f_l1dy, digits=2))，低于经验阈值 10。",
            "短面板下 GMM 偏误风险较高，可尝试收紧 instrument_lags 或收集更长序列。",
            MetricaBase.warning,
        ))
    end
    if L > n_diff - 3
        push!(warnings, MetricaBase.ModelWarning(
            :many_instruments,
            "工具变量较多",
            "矩条件数 L=$(L) 与差分样本 n=$(n_diff) 接近，Hansen 检验可能过度乐观。",
            "可考虑缩小 instrument_lags 上界。",
            MetricaBase.info,
        ))
    end
    if p2 < 0.05
        push!(warnings, MetricaBase.ModelWarning(
            :ar2_serial_correlation,
            "AR(2) 检验提示",
            "差分残差二阶序列相关检验 p 值为 $(round(p2, digits=4))，在 5% 水平拒绝无相关。",
            "可能表明水平扰动项存在序列相关或模型设定不足。",
            MetricaBase.warning,
        ))
    end

    rss = sum(abs2, u)
    tss = sum(abs2, ystack .- mean(ystack))
    r2_val = iszero(tss) ? 1.0 : 1 - rss / tss
    dof_val = n_diff - k
    dof_val > 0 || return MetricaBase.ModelError(
        :insufficient_degrees_of_freedom,
        "自由度不足",
        "差分样本 $(n_diff) 不足以估计 $(k) 个系数。",
        "请增加个体或时期。",
    )
    adj_r2 = iszero(tss) ? 1.0 : 1 - (rss / dof_val) / (tss / (n_diff - 1))
    sigma = sqrt(rss / dof_val)

    n_times = length(unique(sub[!, time_col]))
    metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :r2 => r2_val,
        :adj_r2 => adj_r2,
        :rss => rss,
        :tss => tss,
        :sigma => sigma,
        :j_stat => gmm_res.j_statistic,
        :j_df => Float64(gmm_res.j_df),
        :n_moments => Float64(L),
        :n_params => Float64(k),
        :n_ids => Float64(n_groups),
        :n_times => Float64(n_times),
        :n_obs_diff => Float64(n_diff),
    )
    if gmm_res.j_df > 0 && !isnothing(gmm_res.j_pvalue)
        metrics[:j_pvalue] = gmm_res.j_pvalue
    end

    glance_table = MetricaBase.ModelGlance(:dynamic_panel_gmm, n_diff, dof_val, metrics, warnings)

    statistics = β ./ stderror
    pvalues = 2 .* (1 .- cdf.(TDist(dof_val), abs.(statistics)))
    t_crit = quantile(TDist(dof_val), 0.975)
    ci_low = β .- t_crit .* stderror
    ci_high = β .+ t_crit .* stderror
    tidy_rows = [
        MetricaBase.CoefRow(coef_names[i], β[i], stderror[i], statistics[i], pvalues[i], ci_low[i], ci_high[i])
        for i in eachindex(β)
    ]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "GMM $(wsym === :one_step ? "one_step" : "two_step")")

    gmm_diag = Dict{Symbol, Any}(
        :j_statistic => gmm_res.j_statistic,
        :j_df => gmm_res.j_df,
        :j_pvalue => gmm_res.j_pvalue,
        :n_moments => L,
        :n_params => k,
        :gmm_weight => String(gw),
        :weight_matrix_description => gmm_res.weight_matrix_description,
        :iterations => gmm_res.iterations,
    )

    diagnostics = Dict{Symbol, Any}(
        :ar1_test => Dict(:statistic => z1, :pvalue => p1, :description => "差分残差一阶序列相关（聚类矩，渐近正态）"),
        :ar2_test => Dict(:statistic => z2, :pvalue => p2, :description => "差分残差二阶序列相关（聚类矩，渐近正态）"),
        :hansen_j => Dict(
            :j_statistic => gmm_res.j_statistic,
            :j_df => gmm_res.j_df,
            :j_pvalue => gmm_res.j_pvalue,
        ),
        :n_instruments => L,
        :n_groups => n_groups,
        :n_periods => n_times,
        :n_obs_diff => n_diff,
        :instrument_lags => collect(instrument_lags),
        :dpgmm_style => style,
    )

    return DynamicPanelGMMFitResult(
        formula,
        glance_table,
        tidy_table,
        panel_data,
        fitted,
        u,
        coef_names,
        β,
        vcov_mat,
        stderror,
        diagnostics,
        gmm_diag,
        instrument_lags,
        L,
        n_diff,
    )
end

function MetricaBase.fit(
    ::Type{DynamicPanelGMMModel},
    formula::AbstractString,
    data;
    panel_id::Symbol,
    panel_time::Symbol,
    instrument_lags,
    gmm_weight::AbstractString = "two_step",
    dpgmm_style::AbstractString = "difference",
    collapse_instruments::Bool = false,
    vcov::Symbol = :classical,
    cluster_column = nothing,
    weights = nothing,
    fe_spec = nothing,
    kwargs...,
)
    df = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end
    panel_data = MetricaBase.PanelData(df, panel_id, panel_time)
    il = if instrument_lags isa Tuple{Int, Int}
        instrument_lags
    elseif instrument_lags isa AbstractVector && length(instrument_lags) == 2
        (Int(instrument_lags[1]), Int(instrument_lags[2]))
    else
        return MetricaBase.ModelError(
            :invalid_instrument_lags,
            "instrument_lags 格式错误",
            "需要长度为 2 的整数向量或元组。",
            "请传入如 [2, 4]。",
        )
    end
    return fit_dynamic_panel_gmm(
        panel_data,
        String(formula);
        instrument_lags = il,
        gmm_weight = gmm_weight,
        dpgmm_style = dpgmm_style,
        collapse_instruments = collapse_instruments,
    )
end