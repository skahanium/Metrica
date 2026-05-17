# === Cox PH：Breslow 并列 + 部分似然（Optim + ForwardDiff 海森）====================

"""将事件列规范为 0/1 整数；无法识别时返回 nothing。"""
function coerce_event01(v)::Union{Nothing, Int}
    if v isa Bool
        return v ? 1 : 0
    end
    if v isa Integer
        vi = Int(v)
        return vi == 0 || vi == 1 ? vi : nothing
    end
    if v isa AbstractFloat
        vf = Float64(v)
        if vf ≈ 0.0
            return 0
        elseif vf ≈ 1.0
            return 1
        end
    end
    return nothing
end

function _first_risk_index(t_ord::Vector{Float64}, tau::Float64)::Union{Nothing, Int}
    epsv = 1.0e-12
    for i in eachindex(t_ord)
        if t_ord[i] >= tau - epsv
            return i
        end
    end
    return nothing
end

function log_partial_likelihood(
    beta::Vector{Float64},
    X::Matrix{Float64},
    t_ord::Vector{Float64},
    e_ord::Vector{Int};
    ties::Symbol=:efron,
)::Float64
    n = length(t_ord)
    p = size(X, 2)
    p == 0 || p == length(beta) || return -Inf
    ll = 0.0; j = 1
    while j <= n
        e_ord[j] == 0 && (j += 1; continue)
        tau = t_ord[j]; j0 = j
        while j <= n && t_ord[j] ≈ tau && e_ord[j] == 1; j += 1 end
        d = j - j0
        first_risk = _first_risk_index(t_ord, tau)
        first_risk === nothing && return -Inf
        r0 = first_risk:n; Xr = X[r0, :]; eta = Xr * beta; mx = maximum(eta)
        er = exp.(eta .- mx); s0 = sum(er)
        s0 <= 0 && return -Inf
        k = collect(j0:(j - 1))
        xf_sum = vec(sum(X[k, :], dims=1))
        if ties == :efron && d > 1
            for m in 0:(d - 1)
                w = m / d
                er_fail = exp.(Xr[k, :] * beta .- mx)
                sf = sum(er_fail)
                s0m = s0 - w * sf
                s0m > 0 || (ll = -Inf; break)
                ll -= log(s0m) + mx
            end
            ll += dot(xf_sum, beta)
        else
            ll += dot(xf_sum, beta) - d * (log(s0) + mx)
        end
    end
    return ll
end

function breslow_baseline_preview(
    beta::Vector{Float64},
    X::Matrix{Float64},
    t_ord::Vector{Float64},
    e_ord::Vector{Int},
    max_points::Int = 30,
)::Vector{Pair{Float64, Float64}}
    n = length(t_ord)
    H = 0.0
    out = Pair{Float64, Float64}[]
    j = 1
    while j <= n
        if e_ord[j] == 0
            j += 1
            continue
        end
        tau = t_ord[j]
        j0 = j
        while j <= n && t_ord[j] ≈ tau && e_ord[j] == 1
            j += 1
        end
        d = j - j0
        first_risk = _first_risk_index(t_ord, tau)
        first_risk === nothing && break
        r0 = first_risk:n
        Xr = X[r0, :]
        eta = Xr * beta
        mx = maximum(eta)
        s0 = sum(exp.(eta .- mx)) * exp(mx)
        s0 <= 0 && break
        H += d / s0
        if length(out) < max_points
            push!(out, tau => H)
        end
    end
    return out
end

"""
    fit_duration_cox(df, formula, time_col, event_col)

- `formula`：须为 `ph ~ x1 + x2` 形式，`ph` 占位，仅右侧列须存在于 `df`。
- `time_col` / `event_col`：列名字符串。
"""
function fit_duration_cox(
    df::DataFrame,
    formula::AbstractString,
    time_col::AbstractString,
    event_col::AbstractString;
    ties::Symbol=:efron,
    cluster_col::Union{Nothing, AbstractString}=nothing,
    strata_col::Union{Nothing, AbstractString}=nothing,
)::Union{CoxFitResult, MetricaBase.ModelError}
    tc = String(strip(time_col))
    ec = String(strip(event_col))
    isempty(tc) &&
        return MetricaBase.ModelError(:duration_missing_time, "缺少时间列", "", "请设置 duration_time_column。")
    isempty(ec) &&
        return MetricaBase.ModelError(:duration_missing_event, "缺少事件列", "", "请设置 duration_event_column。")

    parsed = MetricaBase.parse_metrica_formula(formula)
    parsed isa MetricaBase.ModelError && return parsed
    _yplaceholder, xnames = parsed
    isempty(xnames) &&
        return MetricaBase.ModelError(:duration_no_covariates, "Cox 模型至少需要一个协变量", "", "请使用 ph ~ x1 或更多协变量。")

    needcols = unique(vcat([tc, ec], String.(xnames)))
    missingcols = setdiff(needcols, names(df))
    !isempty(missingcols) &&
        return MetricaBase.ModelError(
            :duration_missing_columns,
            "数据缺少列",
            join(missingcols, ", "),
            "请检查公式与时间/事件列名。",
        )

    sub = select(df, Symbol.(needcols))
    subcc = dropmissing(sub)
    nrow(subcc) == 0 &&
        return MetricaBase.ModelError(:duration_empty_sample, "有效样本为空", "", "请检查缺失值。")

    n = nrow(subcc)
    n > 10_000 &&
        return MetricaBase.ModelError(:duration_n_too_large, "样本量超过首期上界", "n > 10000", "请抽样或拆分。")

    timev = Float64.(subcc[!, Symbol(tc)])
    evraw = subcc[!, Symbol(ec)]
    event = zeros(Int, n)
    for i in 1:n
        c = coerce_event01(evraw[i])
        c === nothing &&
            return MetricaBase.ModelError(
                :duration_invalid_event,
                "事件列取值无效",
                string(evraw[i]),
                "事件列须为 0/1 或布尔值。",
            )
        event[i] = c
    end

    for i in 1:n
        !isfinite(timev[i]) &&
            return MetricaBase.ModelError(:duration_nonfinite_time, "时间非有限数", string(timev[i]), "请检查时间列。")
        timev[i] < 0 &&
            return MetricaBase.ModelError(:duration_negative_time, "时间为负", string(timev[i]), "时间须为非负数。")
        timev[i] == 0 &&
            return MetricaBase.ModelError(:duration_zero_time, "时间为零", "", "首期要求时间为正；请改用左截断二期方案。")
    end

    ne = sum(event)
    ne == 0 &&
        return MetricaBase.ModelError(:duration_no_events, "无事件发生", "", "事件列须至少有一个 1。")

    p = length(xnames)
    X = zeros(Float64, n, p)
    for (j, xn) in enumerate(xnames)
        X[:, j] .= Float64.(subcc[!, Symbol(xn)])
    end

    # 并列：同时间下事件优先于删失（左连续风险集常规处理）
    ord = sortperm(1:n, by = i -> (timev[i], -event[i]))
    t_ord = timev[ord]
    e_ord = event[ord]
    X_o = X[ord, :]

    neg_ll(β) = -log_partial_likelihood(β, X_o, t_ord, e_ord; ties=ties)
    β0 = zeros(p)
    opt = Optim.optimize(neg_ll, β0, Optim.NelderMead(), Optim.Options(iterations=15_000, f_reltol=1e-7))
    βhat = Optim.minimizer(opt)
    ll = log_partial_likelihood(βhat, X_o, t_ord, e_ord; ties=ties)
    converged = Optim.converged(opt)
    iters = Optim.iterations(opt)

    H = zeros(Float64, p, p)
    FiniteDiff.finite_difference_hessian!(H, neg_ll, βhat)
    Hs = Symmetric(H); evmin = minimum(eigvals(Matrix(Hs)))
    evmin < 1e-10 && (Hs = Hs + (1e-8 - evmin) * I)
    covb = try inv(Matrix(Hs))
    catch; return MetricaBase.ModelError(:cox_singular_information, "信息矩阵接近奇异", "无法求逆海森", "请检查协变量完全共线性或事件过少。") end
    se = sqrt.(clamp.(diag(covb), 0.0, Inf))

    # Cluster robust SE
    if cluster_col !== nothing
        cluster_ids = subcc[!, Symbol(String(cluster_col))]
        c_unique = unique(cluster_ids)
        n_cluster = length(c_unique)
        se_cluster = if n_cluster >= 2 && n_cluster < n
            G = zeros(n_cluster, p)
            for (ci, cid) in enumerate(c_unique)
                c_idx = findall(cluster_ids .== cid)
                for i in c_idx
                    xi = X_o[i, :]; zi = dot(xi, βhat)
                    ri = _first_risk_index(t_ord, t_ord[i])
                    ri === nothing && continue
                    risk_idx = ri:n; Xr = X_o[risk_idx, :]; eta = Xr * βhat
                    mx = maximum(eta); er = exp.(eta .- mx); s0 = sum(er)
                    x_bar = vec(sum(Xr .* er, dims=1)) ./ s0
                    G[ci, :] .+= e_ord[i] * (xi .- x_bar)
                end
            end
            Vc = covb * (G' * G) * covb
            se_c = sqrt.(clamp.(diag(Vc), 0.0, Inf))
            se_c
        else
            nothing
        end
    else
        se_cluster = nothing
    end

    preview = breslow_baseline_preview(βhat, X_o, t_ord, e_ord, 30)
    surv = baseline_survival(preview)

    # Strata: 分层基线风险
    strata_hazards = nothing
    if strata_col !== nothing
        strata_hazards = Dict{String, Any}()
        strata_vals = subcc[!, Symbol(String(strata_col))]
        for sv in unique(strata_vals)
            s_idx = strata_vals .== sv
            Xs = X_o[s_idx, :]; ts = t_ord[s_idx]; es = e_ord[s_idx]
            prev_s = breslow_baseline_preview(βhat, Xs, ts, es, 10)
            strata_hazards[String(sv)] = [Dict("time" => p.first, "cumulative_hazard" => p.second) for p in prev_s]
        end
    end

    # Schoenfeld 残差 + PH 检验
    ph_diag = nothing
    if p > 0
        sr, sr_times = schoenfeld_residuals(βhat, X_o, t_ord, e_ord)
        if size(sr, 1) > p + 1
            global_test = ph_global_test(sr, sr_times)
            var_tests = ph_variable_tests(sr, sr_times)
            ph_diag = Dict{Symbol, Any}(:global_test => global_test, :variable_tests => var_tests)
        end
    end

    k_params = p
    aic = -2 * ll + 2 * k_params
    bic = -2 * ll + k_params * log(n)

    diagd = Dict{Symbol, Any}(
        :n_obs => n, :n_events => ne, :n_censored => n - ne,
        :censoring_fraction => (n - ne) / max(n, 1),
        :risk_set_ties_method => String(ties),
        :converged => converged, :iterations => iters,
        :loglikelihood => ll, :aic => aic, :bic => bic,
        :baseline_hazard_summary => Dict{Symbol, Any}(
            :n_event_times => length(preview),
            :preview => [Dict("time" => pr.first, "cumulative_hazard" => pr.second) for pr in preview],
            :ties_method => String(ties),
        ),
        :baseline_survival_preview => [Dict("time" => pr.first, "survival" => pr.second) for pr in surv],
        :ph_diagnostics => ph_diag,
        :cluster_se => se_cluster !== nothing ? se_cluster : nothing,
        :strata_hazards => strata_hazards,
    )

    # Build CoxFitResult — add se_cluster as extra field via diagnostics only
    # (CoxFitResult has se for the base SE; cluster SE lives in diagnostics)
    return CoxFitResult(
        :duration_cox,
        Symbol.(xnames),
        βhat,
        se,
        ll,
        n,
        ne,
        n - ne,
        converged,
        iters,
        preview,
        diagd,
        MetricaBase.ModelWarning[],
    )
end
