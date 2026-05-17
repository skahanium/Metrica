# === NLS 与门限回归拟合 =========================================================

using DataFrames
using Distributions: Normal, cdf
using FiniteDiff
using LinearAlgebra: dot, rank, diag, I, Symmetric
using Optim
using Random
using Statistics
using StatsModels: coefnames

const NLS_FAMILIES = ("exp_growth",)
const MIN_REGIME_N = 10
const MAX_THRESHOLD_GRID = 500

# 标量 RSS，供 Optim 使用
function _nls_objective(β::AbstractVector{<:Real}, y::Vector{Float64}, z::Vector{Float64})::Float64
    s = 0.0
    @inbounds for i in eachindex(y)
        μ = β[1] + β[2] * exp(β[3] * z[i])
        d = y[i] - μ
        s += d * d
    end
    return s
end

function MetricaBase.fit(
    ::Type{NLSModel},
    formula::AbstractString,
    data;
    nls_family::AbstractString = "exp_growth",
    nls_start = nothing,
    nls_max_iter::Int = 2000,
    nls_tol::Float64 = 1e-6,
)
    fam = lowercase(String(strip(nls_family)))
    if !(fam in NLS_FAMILIES)
        return MetricaBase.ModelError(
            :unsupported_nls_family,
            "不支持的 nls_family",
            "收到 `$(nls_family)`。首期仅支持 `exp_growth`（μ = β₁ + β₂ exp(β₃ z)）。",
            "请使用 family(exp_growth) 或省略 family。",
        )
    end
    nls_start === nothing &&
        return MetricaBase.ModelError(
            :missing_nls_start,
            "缺少 NLS 初值",
            "非线性最小二乘必须提供长度为 3 的初值向量 `nls_start`。",
            "请使用 start(β₁ β₂ β₃) 等形式传入三个浮点。",
        )
    β0 = Float64.(collect(nls_start))
    if length(β0) != 3
        return MetricaBase.ModelError(
            :invalid_nls_start,
            "初值长度错误",
            "exp_growth 需要 3 个初值，收到 $(length(β0)) 个。",
            "请提供 start(β₁ β₂ β₃)。",
        )
    end
    if any(!isfinite, β0)
        return MetricaBase.ModelError(:invalid_nls_start, "初值须全为有限实数。", "", "请检查 start(...) 中的数值。")
    end

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
    err = MetricaLinear.validate_model_columns(dataset, model_columns, nothing, nothing)
    err isa MetricaBase.ModelError && return err

    prepared = MetricaLinear.prepare_model_data(
        dataset, model_formula, model_columns, nothing, nothing,
    )
    prepared isa MetricaBase.ModelError && return prepared

    (filtered_dataset, model_frame, _, X, y, _, _, n_total, n_effective) = prepared
    nobs = length(y)
    p = size(X, 2)
    if p < 2
        return MetricaBase.ModelError(
            :nls_requires_regressor,
            "NLS 公式列数不足",
            "exp_growth 需要至少含截距与一个数值解释变量（z）。",
            "请使用 `y ~ x` 形式。",
        )
    end
    # 除截距外第一列作为 z（与专节一致）
    z = Float64.(X[:, 2])

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, MetricaLinear.build_rows_dropped_warning(dropped_rows))

    push!(
        warnings,
        MetricaBase.ModelWarning(
            :nls_se_not_implemented,
            "未输出渐近标准误",
            "首期 NLS 仅返回点估计；标准误列为空，避免与 OLS 的 vcov 语义混淆。",
            "后续专节可引入 delta 方法或自助法并显式声明推断口径。",
            MetricaBase.info,
        ),
    )

    obj(β) = _nls_objective(β, y, z)
    opts = Optim.Options(iterations = nls_max_iter, f_reltol = nls_tol)
    sol = Optim.optimize(obj, β0, NelderMead(), opts)
    βhat = Optim.minimizer(sol)
    rss = Optim.minimum(sol)
    converged = Optim.converged(sol)
    iters = Optim.iterations(sol)
    fcode = converged ? nothing : :optimizer_not_converged

    tidy_rows = [
        MetricaBase.CoefRow(:beta_1, βhat[1], nothing, nothing, nothing, nothing, nothing),
        MetricaBase.CoefRow(:beta_2, βhat[2], nothing, nothing, nothing, nothing, nothing),
        MetricaBase.CoefRow(:beta_3, βhat[3], nothing, nothing, nothing, nothing, nothing),
    ]
    if !converged
        push!(
            warnings,
            MetricaBase.ModelWarning(
                :nls_not_converged,
                "NLS 未收敛",
                "Optim 报告未收敛：可能初值不佳或目标病态。",
                "尝试调整初值或检查 z 与 y 的量纲。",
                MetricaBase.warning,
            ),
        )
    end

    metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :rss => rss,
        :objective_final => rss,
        :converged => converged ? 1.0 : 0.0,
        :iterations => Float64(iters),
    )
    dof = nobs - 3
    glance_table = MetricaBase.ModelGlance(:nls, nobs, dof, metrics, warnings)
    tidy_table = MetricaBase.TidyTable(tidy_rows, "nls_no_se")

    fitted = Vector{Float64}(undef, nobs)
    @inbounds for i in eachindex(y)
        fitted[i] = βhat[1] + βhat[2] * exp(βhat[3] * z[i])
    end
    residuals = y .- fitted

    diagnostics = Dict{Symbol, Any}(
        :converged => converged,
        :iterations => iters,
        :optimizer => "Optim.NelderMead",
        :objective_final => rss,
        :gradient_norm => nothing,
        :start_used => β0,
        :failure_code => fcode === nothing ? nothing : String(fcode),
        :nls_family => fam,
    )

    return NLSFitResult(
        String(formula),
        glance_table,
        tidy_table,
        fam,
        βhat,
        rss,
        converged,
        iters,
        "Optim.NelderMead",
        fcode,
        diagnostics,
        z,
        y,
        fitted,
        residuals,
    )
end

function _validate_monotone_threshold_grid(tg::Vector{Float64})
    any(!isfinite, tg) &&
        return MetricaBase.ModelError(
            :invalid_threshold_grid,
            "门限网格含非有限值",
            "`threshold_grid` 须全为有限实数。",
            "请检查 grid 中的 inf / nan。",
        )
    if length(tg) < 2
        return MetricaBase.ModelError(
            :invalid_threshold_grid,
            "门限网格点过少",
            "至少需要 2 个候选 γ。",
            "请增大 grid 点数。",
        )
    end
    for i in 2:length(tg)
        if tg[i] <= tg[i - 1]
            return MetricaBase.ModelError(
                :invalid_threshold_grid,
                "门限网格须严格递增",
                "收到非单调或含重复值的 `threshold_grid`（按输入顺序检查，不自动重排）。",
                "请使用 grid(min max n) 生成已排序、严格递增的数组。",
            )
        end
    end
    return nothing
end

function _ols_split_rss(y::Vector{Float64}, X::Matrix{Float64}, mask::BitVector)
    n = count(mask)
    n < MIN_REGIME_N && return Inf
    Xs = X[mask, :]
    ys = y[mask]
    rank(Xs) < size(Xs, 2) && return Inf
    β = Xs \ ys
    r = ys - Xs * β
    return sum(abs2, r)
end

function MetricaBase.fit(
    ::Type{ThresholdModel},
    formula::AbstractString,
    data;
    threshold_variable::AbstractString,
    threshold_grid::Vector{Float64},
    threshold_trim_frac::Float64 = 0.1,
)
    if !(0.0 <= threshold_trim_frac < 0.45)
        return MetricaBase.ModelError(
            :invalid_trim_frac,
            "trim 比例非法",
            "threshold_trim_frac 须在 [0, 0.45) 以保证各区制有足够样本。",
            "请使用 trim(0.1) 等合理值。",
        )
    end
    tg = copy(threshold_grid)
    if length(tg) < 2 || length(tg) > MAX_THRESHOLD_GRID
        return MetricaBase.ModelError(
            :invalid_threshold_grid,
            "门限网格长度非法",
            "须满足 2 ≤ length(threshold_grid) ≤ $(MAX_THRESHOLD_GRID)，收到 $(length(tg))。",
            "请缩小或拆分 grid。",
        )
    end
    g2 = tg
    gerr = _validate_monotone_threshold_grid(g2)
    gerr isa MetricaBase.ModelError && return gerr

    dataset = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    qsym = Symbol(String(strip(threshold_variable)))
    hasproperty(dataset, qsym) ||
        return MetricaBase.ModelError(
            :unknown_threshold_column,
            "切换变量列不存在",
            "数据集中找不到列 `$(qsym)`。",
            "请检查 qvar(...) 与数据集列名一致。",
        )

    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    model_columns = MetricaLinear.collect_term_symbols(model_formula)
    qsym in model_columns ||
        return MetricaBase.ModelError(
            :threshold_var_not_in_formula,
            "切换变量未进入公式",
            "门限变量 `$(qsym)` 须出现在 `formula` 右侧，以便 listwise 与 X 对齐。",
            "请将 `$(qsym)` 加入回归元。",
        )

    err = MetricaLinear.validate_model_columns(dataset, model_columns, nothing, nothing)
    err isa MetricaBase.ModelError && return err

    prepared = MetricaLinear.prepare_model_data(
        dataset, model_formula, model_columns, nothing, nothing,
    )
    prepared isa MetricaBase.ModelError && return prepared

    (filtered_dataset, model_frame, _, X, y, _, _, n_total, n_effective) = prepared
    q = Float64.(filtered_dataset[!, qsym])

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, MetricaLinear.build_rows_dropped_warning(dropped_rows))

    lo = Statistics.quantile(q, threshold_trim_frac)
    hi = Statistics.quantile(q, 1 - threshold_trim_frac)
    inner_mask = (q .>= lo) .& (q .<= hi)
    if count(inner_mask) < 2 * MIN_REGIME_N
        return MetricaBase.ModelError(
            :threshold_trim_too_aggressive,
            "修剪后样本不足",
            "trim 后可用于门限搜索的观测过少。",
            "请减小 trim 或增大样本。",
        )
    end

    # 仅保留 inner 上的候选 γ（与 q 取值区间求交）
    qmin = minimum(q[inner_mask])
    qmax = maximum(q[inner_mask])
    candidates = Float64[]
    for γ in g2
        if γ >= qmin && γ <= qmax
            push!(candidates, γ)
        end
    end
    if length(candidates) < 2
        return MetricaBase.ModelError(
            :invalid_threshold_grid,
            "候选门限过少",
            "与修剪后 q 范围求交后候选 γ 少于 2。",
            "请调整 grid 或 trim。",
        )
    end

    best_γ = candidates[1]
    best_rss = Inf
    for γ in candidates
        m1 = q .<= γ
        m2 = q .> γ
        n1 = count(m1)
        n2 = count(m2)
        (n1 < MIN_REGIME_N || n2 < MIN_REGIME_N) && continue
        r1 = _ols_split_rss(y, X, m1)
        r2 = _ols_split_rss(y, X, m2)
        (r1 == Inf || r2 == Inf) && continue
        R = r1 + r2
        if R < best_rss
            best_rss = R
            best_γ = γ
        end
    end
    if !isfinite(best_rss)
        return MetricaBase.ModelError(
            :threshold_fit_failed,
            "门限搜索失败",
            "所有候选 γ 下区制样本不足或设计矩阵秩亏。",
            "请放宽 trim、加密 grid 或检查共线。",
        )
    end

    m1 = q .<= best_γ
    m2 = q .> best_γ
    n1 = count(m1)
    n2 = count(m2)
    X1 = X[m1, :]
    X2 = X[m2, :]
    β1 = X1 \ y[m1]
    β2 = X2 \ y[m2]
    cnames = Symbol.(coefnames(model_frame))

    tidy_rows = MetricaBase.CoefRow[]
    for (i, nm) in enumerate(cnames)
        push!(tidy_rows, MetricaBase.CoefRow(Symbol("below_" * String(nm)), β1[i], nothing, nothing, nothing, nothing, nothing))
    end
    for (i, nm) in enumerate(cnames)
        push!(tidy_rows, MetricaBase.CoefRow(Symbol("above_" * String(nm)), β2[i], nothing, nothing, nothing, nothing, nothing))
    end
    push!(tidy_rows, MetricaBase.CoefRow(:gamma_hat, best_γ, nothing, nothing, nothing, nothing, nothing))

    metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :rss => best_rss,
        :gamma_hat => best_γ,
        :n_below => Float64(n1),
        :n_above => Float64(n2),
    )
    nobs = length(y)
    dof = nobs - 2 * size(X, 2) # 教学用粗略自由度，非严格 LR 理论
    glance_table = MetricaBase.ModelGlance(:threshold, nobs, dof, metrics, warnings)
    tidy_table = MetricaBase.TidyTable(tidy_rows, "piecewise_ols")

    diagnostics = Dict{Symbol, Any}(
        :gamma_hat => best_γ,
        :n_below => n1,
        :n_above => n2,
        :rss_piecewise => best_rss,
        :search_grid_meta => Dict{Symbol, Any}(
            :n_candidates => length(candidates),
            :trim_frac_applied => threshold_trim_frac,
            :grid_input_length => length(tg),
        ),
    )

    fitted = Vector{Float64}(undef, length(y))
    @inbounds for i in eachindex(y)
        fitted[i] = m1[i] ? dot(X[i, :], β1) : dot(X[i, :], β2)
    end
    residuals = y .- fitted

    return ThresholdFitResult(
        String(formula),
        glance_table,
        tidy_table,
        best_γ,
        n1,
        n2,
        best_rss,
        diagnostics,
        fitted,
        residuals,
    )
end

MetricaBase.glance(r::NLSFitResult) = r.glance_table
MetricaBase.tidy(r::NLSFitResult) = r.tidy_table
MetricaBase.glance(r::ThresholdFitResult) = r.glance_table
MetricaBase.tidy(r::ThresholdFitResult) = r.tidy_table

function MetricaBase.augment(r::NLSFitResult)
    n = r.glance_table.nobs
    return MetricaBase.AugmentTable(
        Dict{Symbol, Vector{Float64}}(
            :observation => collect(1.0:n),
            :fitted => r.fitted_values,
            :residual => r.residuals,
        ),
        n,
    )
end

function MetricaBase.augment(r::ThresholdFitResult)
    n = r.glance_table.nobs
    return MetricaBase.AugmentTable(
        Dict{Symbol, Vector{Float64}}(
            :observation => collect(1.0:n),
            :fitted => r.fitted_values,
            :residual => r.residuals,
        ),
        n,
    )
end

# === NLS 模型族：exp_growth, logistic, power, gompertz ==========================

const NLS_PREDICTORS = Dict{String, Tuple{Int, Function}}(
    "exp_growth" => (3, (b, x) -> b[1] + b[2] * exp(b[3] * x)),
    "logistic"   => (3, (b, x) -> b[1] / (1.0 + b[2] * exp(-b[3] * x))),
    "power"      => (2, (b, x) -> b[1] * x^b[2]),
    "gompertz"   => (3, (b, x) -> b[1] * exp(-b[2] * exp(-b[3] * x))),
)
const NLS_PARAM_NAMES = Dict{String, Vector{String}}(
    "exp_growth" => ["b1", "b2", "b3"],
    "logistic"   => ["Asym", "b2", "b3"],
    "power"      => ["a", "b"],
    "gompertz"   => ["Asym", "b2", "b3"],
)

function nls_fit_user(formula_str::String, data, start::Vector{Float64}; nls_family::String="exp_growth")
    haskey(NLS_PREDICTORS, nls_family) || return MetricaBase.ModelError(:nls_unknown_family,
        "不支持的 NLS 族: $nls_family", "支持: $(join(keys(NLS_PREDICTORS), ", "))", "")
    np, pred_fn = NLS_PREDICTORS[nls_family]
    length(start) == np || return MetricaBase.ModelError(:nls_start_length,
        "$nls_family 需要 $np 个初值，收到 $(length(start))", "", "")
    parsed = MetricaBase.parse_metrica_formula(formula_str)
    parsed isa MetricaBase.ModelError && return parsed
    yname, xnames = parsed; y = Float64.(data[!, Symbol(yname)])
    x = Float64.(data[!, Symbol(xnames[1])])
    function obj(b); rss = 0.0
        for i in eachindex(y); mu = pred_fn(b, x[i]); rss += (y[i] - mu)^2; end
        return rss
    end
    r = Optim.optimize(obj, start, BFGS(), Optim.Options(iterations=2000, f_reltol=1e-8, g_reltol=1e-8))
    b = Optim.minimizer(r); converged = Optim.converged(r); it = Optim.iterations(r)
    H = zeros(np, np); FiniteDiff.finite_difference_hessian!(H, obj, b)
    V = 2 * obj(b) / max(length(y) - np, 1) * inv(Symmetric(H + 1e-10 * I))
    se = sqrt.(max.(diag(V), 0.0))
    fitted = [pred_fn(b, x[i]) for i in eachindex(y)]; residuals = y - fitted
    diag_dict = Dict{Symbol, Any}(:converged => converged, :iterations => it, :optimizer => "BFGS",
        :objective_final => obj(b), :start_used => start, :parameter_covariance => V,
        :gradient_norm => nothing, :nls_family => nls_family)
    coefs = MetricaBase.CoefRow[]; pnames = NLS_PARAM_NAMES[nls_family]
    for i in eachindex(b)
        z = se[i] > 0 ? b[i] / se[i] : nothing
        pv = se[i] > 0 ? 2 * (1 - cdf(Normal(), abs(z))) : nothing
        push!(coefs, MetricaBase.CoefRow(Symbol(pnames[i]), b[i], se[i], z, pv, b[i]-1.96*se[i], b[i]+1.96*se[i]))
    end
    gl = MetricaBase.ModelGlance(:nls, length(y), length(y) - np,
        Dict{Symbol, MetricaBase.MetricValue}(:rss => obj(b)), MetricaBase.ModelWarning[])
    return NLSFitResult(formula_str, gl, MetricaBase.TidyTable(coefs, "BFGS"), nls_family,
        b, obj(b), converged, it, "BFGS", nothing, diag_dict, x, y, fitted, residuals)
end

function nls_multi_start(formula_str::String, data, nls_family::String="exp_growth"; n_starts::Int=10, seed::Int=42)
    haskey(NLS_PREDICTORS, nls_family) || return MetricaBase.ModelError(:nls_unknown_family, "", "", "")
    np = NLS_PREDICTORS[nls_family][1]; Random.seed!(seed)
    best_result = nothing; best_rss = Inf
    for s in 1:n_starts
        start = np == 2 ? randn(2) .* 0.5 .+ [1.0, 0.5] : randn(3) .* 0.5 .+ 1.0
        r = nls_fit_user(formula_str, data, start; nls_family=nls_family)
        r isa MetricaBase.ModelError && continue
        if r.residual_sum_squares < best_rss; best_rss = r.residual_sum_squares; best_result = r; end
    end
    best_result === nothing && return MetricaBase.ModelError(:nls_all_failed, "多起点均失败", "", "")
    best_result.diagnostics[:multi_start_attempts] = n_starts
    return best_result
end

# === Threshold 多门限 =========================================================
function fit_threshold_multi(data, formula::String, qvar::Symbol, n_thresholds::Int)
    isempty(n_thresholds) && n_thresholds == 0 && return MetricaBase.ModelError(:threshold_zero, "至少需要 1 个门限", "", "")
    n_thresholds > 3 && return MetricaBase.ModelError(:threshold_too_many, "最多支持 3 个门限", "", "")
    q = Float64.(data[\!, qvar]); n = length(q)
    threshold_grid = collect(range(quantile(q, 0.15), quantile(q, 0.85), length=200))
    best_rss = Inf; best_gammas = Float64[]
    for g1 in threshold_grid
        r1 = (q .<= g1); n1 = sum(r1)
        n1 < 10 && continue
        if n_thresholds == 1
            rss = MetricaNonlinear._ols_split_rss(Float64.(data[\!, Symbol(split(formula, "~")[1])]),
                hcat(ones(n), [Float64.(data[\!, Symbol(c)]) for c in split(split(formula, "~")[2], "+")]...), r1)
            if rss + Inf > 0 && (isempty(best_gammas) || rss < best_rss); best_rss = rss; best_gammas = [g1]; end
        end
    end
    isempty(best_gammas) && return MetricaBase.ModelError(:threshold_fit_failed_multi, "多门限搜索失败", "", "")
    return best_gammas, best_rss
end

# === Threshold Bootstrap CI ===================================================
function threshold_bootstrap_ci(data, formula::String, qvar::Symbol, n_boot::Int=100, seed::Int=42)
    Random.seed\!(seed); n = nrow(data); gammas = Float64[]
    q = Float64.(data[\!, qvar]); grid = collect(range(quantile(q, 0.15), quantile(q, 0.85), length=50))
    for b in 1:n_boot
        idx = rand(1:n, n); boot_df = data[idx, :]
        best_rss = Inf; best_g = NaN
        for g in grid
            r1 = Float64.(boot_df[\!, qvar]) .<= g
            sum(r1) < 10 && continue
            yb = Float64.(boot_df[\!, Symbol(split(formula, "~")[1])])
            Xb = hcat(ones(n), [Float64.(boot_df[\!, Symbol(c)]) for c in split(strip(split(formula, "~")[2]), "+")]...)
            b1 = Xb[r1, :] \ yb[r1]; b2 = Xb[.\!r1, :] \ yb[.\!r1]
            rss = sum(abs2, yb[r1] - Xb[r1, :] * b1) + sum(abs2, yb[.\!r1] - Xb[.\!r1, :] * b2)
            if rss < best_rss; best_rss = rss; best_g = g; end
        end
        isfinite(best_g) && push\!(gammas, best_g)
    end
    return Dict{Symbol, Any}(:lower => quantile(gammas, 0.025), :upper => quantile(gammas, 0.975), :mean => mean(gammas))
end

# === Threshold sup-Wald 检验 (Hansen 1996) ===================================
function threshold_sup_wald(data, formula::String, qvar::Symbol)
    q = Float64.(data[\!, qvar]); n = length(q)
    y = Float64.(data[\!, Symbol(split(formula, "~")[1])])
    X_covars = split(strip(split(formula, "~")[2]), "+")
    X = hcat(ones(n), [Float64.(data[\!, Symbol(c)]) for c in X_covars]...)
    grid = collect(range(quantile(q, 0.15), quantile(q, 0.85), length=50))
    X_full = hcat(X, X)
    beta_full = X_full \ y; u_full = y - X_full * beta_full
    sigma2 = dot(u_full, u_full) / (n - size(X_full, 2))
    max_wald = 0.0
    for g in grid
        r1 = q .<= g; n1 = sum(r1); n2 = n - n1
        n1 < 10 || n2 < 10 && continue
        b1 = X[r1, :] \ y[r1]; b2 = X[.\!r1, :] \ y[.\!r1]
        diff = b1 - b2
        V1 = inv(Symmetric(X[r1, :]' * X[r1, :] + 1e-10 * I)) .* sigma2
        V2 = inv(Symmetric(X[.\!r1, :]' * X[.\!r1, :] + 1e-10 * I)) .* sigma2
        W = dot(diff, Symmetric(V1 + V2 + 1e-10 * I) \ diff)
        if W > max_wald; max_wald = W; end
    end
    return Dict{Symbol, Any}(:sup_wald => max_wald, :method => "Sup-Wald (Hansen 1996)")
end
