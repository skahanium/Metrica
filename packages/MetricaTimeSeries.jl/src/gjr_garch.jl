# gjr_garch.jl — GJR-GARCH (Glosten-Jagannathan-Runkle) 杠杆效应波动模型
# h_t = ω + Σ α_i ε_{t-i}² + Σ γ_i I(ε_{t-i}<0) ε_{t-i}² + Σ β_j h_{t-j}

struct GJRModel <: AbstractTimeSeriesModel
    variable::Symbol
    time_column::Symbol
    garch_p::Int
    garch_q::Int
    mean_type::Symbol
    max_iter::Int
    tol::Float64
    dist::Symbol
end

struct GJRFitResult <: AbstractTSFitResult
    variable_name::String
    garch_p::Int
    garch_q::Int
    mu::Float64
    omega::Float64
    alpha::Vector{Float64}
    gamma::Vector{Float64}
    beta::Vector{Float64}
    loglik::Float64
    aic::Float64
    bic::Float64
    persistence::Float64
    unconditional_variance::Float64
    conditional_variance::Vector{Float64}
    residuals::Vector{Float64}
    original_series::Vector{Float64}
    converged::Bool
    optimizer::String
    iterations::Int
    failure_code::Union{Nothing,String}
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    warnings::Vector{MetricaBase.ModelWarning}
end

function GJRModel(;
    variable::Symbol,
    time_column::Symbol,
    garch_p::Int = 1,
    garch_q::Int = 1,
    mean_type::Symbol = :constant,
    max_iter::Int = 8000,
    tol::Float64 = 1e-5,
    dist::Symbol = :gaussian,
)
    return GJRModel(variable, time_column, garch_p, garch_q, mean_type, max_iter, tol, dist)
end

function _gjr_unconditional_variance(ω::Float64, α::Vector{Float64}, γ::Vector{Float64}, β::Vector{Float64})
    s = sum(α) + 0.5 * sum(γ) + sum(β)
    s >= 1.0 - 1e-10 && return NaN
    return ω / (1.0 - s)
end

function gjr_garch_conditional_variances(e::Vector{Float64}, ω::Float64, α::Vector{Float64}, γ::Vector{Float64}, β::Vector{Float64})
    T = length(e)
    p = length(α); q = length(β)
    h = Vector{Float64}(undef, T)
    if ω <= 0 || any(x -> x < 0, [α; γ; β]) || sum(α) + 0.5 * sum(γ) + sum(β) >= 1.0 - 1e-10
        return (false, h)
    end
    uncond = _gjr_unconditional_variance(ω, α, γ, β)
    (!isfinite(uncond) || uncond <= 0) && return (false, h)
    @inbounds for t in 1:T
        ht = ω
        for i in 1:p
            ti = t - i
            ei = ti >= 1 ? e[ti] : sqrt(uncond)
            ht += α[i] * ei^2 + γ[i] * (ei < 0 ? ei^2 : 0.0)
        end
        for j in 1:q
            tj = t - j
            ht += β[j] * (tj >= 1 ? h[tj] : uncond)
        end
        ht <= 1e-18 && return (false, h)
        h[t] = ht
    end
    return (true, h)
end

function gjr_garch_loglik(e::Vector{Float64}, ω::Float64, α::Vector{Float64}, γ::Vector{Float64}, β::Vector{Float64})
    ok, h = gjr_garch_conditional_variances(e, ω, α, γ, β)
    !ok && return NaN
    ll = 0.0
    @inbounds for t in eachindex(e)
        ll += -0.5 * (log(2 * pi * h[t]) + e[t]^2 / h[t])
    end
    return ll
end

function _pack_gjr_params(logω::Float64, uab::Vector{Float64}, p::Int, q::Int)
    ω = exp(logω)
    w = _softmax_scaled(uab, 0.99)
    length(w) == 2 * p + q || error("GJR 参数长度须等于 2p+q")
    α = w[1:p]
    γ = w[p + 1:2p]
    β = w[2p + 1:end]
    return ω, α, γ, β
end

function fit_gjr_garch_qmle(e::Vector{Float64}, p::Int, q::Int; max_iter::Int=8000, tol::Float64=1e-5, dist::Symbol=:gaussian)
    v0 = var(e)
    if !(v0 > 0)
        return (NaN, NaN, Float64[], Float64[], Float64[], false, 0, "var_zero", Float64[], fill(NaN, 1+2p+q))
    end
    x0 = vcat(log(0.05 * max(v0, 1e-8)), zeros(2 * p + q))
    function obj(x::Vector{Float64})
        ω, α, γ, β = _pack_gjr_params(x[1], x[2:end], p, q)
        -gjr_garch_loglik(e, ω, α, γ, β)
    end
    r = Optim.optimize(obj, x0, BFGS(), Optim.Options(iterations=max_iter, f_reltol=tol, g_abstol=tol))
    xm = Optim.minimizer(r)
    ωm, αm, γm, βm = _pack_gjr_params(xm[1], xm[2:end], p, q)
    ll = gjr_garch_loglik(e, ωm, αm, γm, βm)
    converged = Optim.converged(r) && isfinite(ll)
    iters = r.iterations
    okh, h = gjr_garch_conditional_variances(e, ωm, αm, γm, βm)
    !okh && (return (NaN, ωm, αm, γm, βm, false, iters, "invalid_variance", fill(NaN, length(e)), fill(NaN, 1+2p+q), "invalid_variance"))
    n = length(e)
    se_all, hess_stat = _opg_standard_errors(xm, obj, n)
    return (ll, ωm, αm, γm, βm, converged, iters, "BFGS", h, se_all, hess_stat)
end

function MetricaBase.fit(model::GJRModel, data::DataFrame)
    data_sorted = sort_by_time(data, model.time_column)
    y = Float64.(data_sorted[!, model.variable])
    n = length(y)
    p, q = model.garch_p, model.garch_q
    nmin = 50 + 5 * (p + q)
    n < nmin && error("GJR-GARCH($p,$q) 需要至少 $nmin 个有效观测，当前 n=$n")

    if model.mean_type == :ar
        ar_order = min(5, div(n, 10))
        lags_y = create_lags(y, ar_order)
        y_dep = lags_y[:, 1]; y_lag = lags_y[:, 2:end]
        ar_beta = y_lag \ y_dep
        e_ar = y_dep .- (y_lag * ar_beta)
        mu = mean(e_ar); e = e_ar .- mu
    else
        mu = mean(y); e = y .- mu
    end
    ll, ω, α, γ, β, converged, iters, optname, h, se_all, hess_stat =
        fit_gjr_garch_qmle(e, p, q; max_iter=model.max_iter, tol=model.tol, dist=model.dist)

    failure = converged ? nothing : (hess_stat != "ok" ? "singular_hessian" : nothing)
    warnings = MetricaBase.ModelWarning[]
    if hess_stat != "ok"
        push!(warnings, MetricaBase.ModelWarning(:singular_hessian, "Hessian 不可逆，OPG 标准误不可信", hess_stat, "", MetricaBase.warning))
    end
    if !converged
        push!(warnings, MetricaBase.ModelWarning(:gjr_not_converged,
            "GJR-GARCH 优化未收敛", "", "可增大 max_iter。", MetricaBase.warning))
    end

    persistence = sum(α) + 0.5 * sum(γ) + sum(β)
    uncond = _gjr_unconditional_variance(ω, α, γ, β)
    k_params = 1 + 1 + 2 * p + q
    aic = isfinite(ll) ? (-2 * ll + 2 * k_params) : NaN
    bic = isfinite(ll) ? (-2 * ll + k_params * log(n)) : NaN

    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :nobs => n, :loglik => ll, :aic => aic, :bic => bic,
        :garch_p => p, :garch_q => q, :persistence => persistence,
        :unconditional_variance => uncond,
    )
    glance_table = MetricaBase.ModelGlance(Symbol("GJR($p,$q)"), n, 0, glance_metrics, warnings)

    se_valid = all(isfinite, se_all) && all(s -> s > 0, se_all)
    crows = MetricaBase.CoefRow[]
    push!(crows, MetricaBase.CoefRow(:mu, mu, nothing, nothing, nothing, nothing, nothing))
    push_se(i, est) = se_valid ?
        MetricaBase.CoefRow(:omega, est, se_all[i], est / se_all[i], 2*(1-cdf(Normal(), abs(est/se_all[i]))), est-1.96*se_all[i], est+1.96*se_all[i]) :
        MetricaBase.CoefRow(:omega, est, nothing, nothing, nothing, nothing, nothing)
    push!(crows, push_se(1, ω))
    for i in 1:length(α)
        se_i = se_valid ? se_all[1+i] : nothing
        push!(
            crows,
            MetricaBase.CoefRow(
                Symbol("alpha_$i"),
                α[i],
                se_i,
                se_valid ? α[i] / se_i : nothing,
                se_valid ? 2 * (1 - cdf(Normal(), abs(α[i] / se_i))) : nothing,
                se_valid ? α[i] - 1.96 * se_i : nothing,
                se_valid ? α[i] + 1.96 * se_i : nothing,
            ),
        )
    end
    for i in 1:length(γ)
        idx = 1 + p + i
        push!(crows, MetricaBase.CoefRow(Symbol("gamma_$i"), γ[i], se_valid ? se_all[idx] : nothing, nothing, nothing, nothing, nothing))
    end
    for j in 1:length(β)
        idx = 1 + 2p + j
        push!(crows, MetricaBase.CoefRow(Symbol("beta_$j"), β[j], se_valid ? se_all[idx] : nothing, nothing, nothing, nothing, nothing))
    end

    tidy_table = MetricaBase.TidyTable(crows, "BFGS QMLE")

    return GJRFitResult(string(model.variable), p, q, mu, ω, α, γ, β, ll, aic, bic,
        persistence, uncond, h, e, y, converged, optname, iters, failure,
        glance_table, tidy_table, warnings)
end

MetricaBase.glance(r::GJRFitResult) = r.glance_table
MetricaBase.tidy(r::GJRFitResult) = r.tidy_table
MetricaBase.nobs(r::GJRFitResult) = r.glance_table.nobs

function MetricaBase.model_capabilities(r::GJRFitResult)::MetricaBase.ModelCapabilities
    return MetricaBase.ModelCapabilities(:partial, :volatility, [:arch, :garch, :gjr_garch],
        ["QMLE (Gaussian) + BFGS"], [:loglik, :persistence, :std_errors, :conditional_volatility],
        [:var, :es, :forecast, :egarch, :student_t], Symbol[], false,
        ["GJR-GARCH 支持杠杆效应。VaR/ES/预测为后续功能。"])
end

MetricaBase.augment(::GJRFitResult) = AugmentTable()

function result_to_payload(r::GJRFitResult; include_augment::Bool=true)
    preview_n = 50
    σ = sqrt.(max.(r.conditional_variance, 1e-18))
    diag = Dict{String, Any}(
        "converged" => r.converged, "iterations" => r.iterations,
        "optimizer" => r.optimizer, "loglik" => r.loglik,
        "persistence" => r.persistence, "unconditional_variance" => r.unconditional_variance,
        "conditional_volatility_preview" => σ[1:min(end, preview_n)],
        "volatility_length" => length(r.conditional_variance),
        "garch_p" => r.garch_p, "garch_q" => r.garch_q, "failure_code" => r.failure_code,
    )
    caps = MetricaBase.model_capabilities(r)
    payload = Dict{String, Any}(
        "model_type" => "gjr_garch", "variable" => r.variable_name,
        "garch_p" => r.garch_p, "garch_q" => r.garch_q, "nobs" => length(r.original_series),
        "mu" => r.mu, "omega" => r.omega, "alpha" => r.alpha,
        "gamma" => r.gamma, "beta" => r.beta,
        "loglik" => r.loglik, "aic" => r.aic, "bic" => r.bic,
        "glance" => Dict("model" => string(r.glance_table.model), "nobs" => r.glance_table.nobs,
            "metrics" => Dict(string(k) => v for (k, v) in r.glance_table.metrics)),
        "tidy" => Dict("rows" => [
            Dict("term" => string(row.name), "estimate" => row.estimate, "stderror" => row.stderror,
                 "statistic" => row.statistic, "p_value" => row.pvalue,
                 "ci_lower" => row.ci_lower, "ci_upper" => row.ci_upper)
            for row in r.tidy_table.rows]),
        "diagnostics" => diag,
        "model_capabilities" => MetricaBase.capabilities_to_dict(caps),
        "augment_status" => MetricaBase.build_augment_status(r; available=include_augment,
            columns_available=include_augment ? ["residual"] : String[],
            columns_unavailable=["fitted", "std_residual"], preview_included=include_augment,
            preview_rows=include_augment ? min(length(r.original_series), 50) : 0),
    )
    if !isempty(r.warnings)
        payload["warnings"] = [Dict("code" => string(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint, "severity" => string(w.severity)) for w in r.warnings]
    end
    if include_augment
        m = min(length(r.original_series), 50)
        payload["augment_preview"] = Dict("obs" => collect(1.0:m), "y" => r.original_series[1:m],
            "residual" => r.residuals[1:m], "conditional_volatility" => σ[1:m])
    end
    return payload
end
