# egarch.jl — EGARCH (Nelson 1991) 非对称指数波动模型
# log(h_t) = ω + Σ α_i (|z_{t-i}| - E|z|) + Σ γ_i z_{t-i} + Σ β_j log(h_{t-j})

struct EGARCHModel <: AbstractTimeSeriesModel
    variable::Symbol
    time_column::Symbol
    garch_p::Int
    garch_q::Int
    mean_type::Symbol
    max_iter::Int
    tol::Float64
    dist::Symbol
end

struct EGARCHFitResult <: AbstractTSFitResult
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

const EZ_ABS_GAUSSIAN = sqrt(2.0 / π)

function egarch_conditional_variances(e::Vector{Float64}, ω::Float64, α::Vector{Float64},
                                       γ::Vector{Float64}, β::Vector{Float64})
    T = length(e)
    p = length(α); q = length(β)
    h = Vector{Float64}(undef, T)
    persistence = sum(β)
    if persistence >= 1.0 - 1e-10
        return (false, h)
    end
    log_uncond = persistence < 1.0 ? ω / (1.0 - persistence) : ω
    @inbounds for t in 1:T
        ln_ht = ω
        for i in 1:p
            ti = t - i
            if ti >= 1
                z = e[ti] / sqrt(max(h[ti], 1e-18))
                ln_ht += α[i] * (abs(z) - EZ_ABS_GAUSSIAN) + γ[i] * z
            else
                ln_ht += α[i] * (0.0) + γ[i] * 0.0
            end
        end
        for j in 1:q
            tj = t - j
            ln_ht += β[j] * (tj >= 1 ? log(max(h[tj], 1e-18)) : log_uncond)
        end
        ht = exp(ln_ht)
        ht <= 1e-18 || !isfinite(ht) && return (false, h)
        h[t] = ht
    end
    return (true, h)
end

function egarch_loglik(e::Vector{Float64}, ω::Float64, α::Vector{Float64},
                        γ::Vector{Float64}, β::Vector{Float64})
    ok, h = egarch_conditional_variances(e, ω, α, γ, β)
    !ok && return NaN
    ll = 0.0
    @inbounds for t in eachindex(e)
        ll += -0.5 * (log(2 * pi * h[t]) + e[t]^2 / h[t])
    end
    return ll
end

function _pack_egarch_params(params::Vector{Float64}, p::Int, q::Int)
    ω = params[1] - 5.0  # ω 无约束
    α = abs.(params[2:p+1]) .* 0.5
    γ = params[p+2:2p+1]
    β = _softmax_scaled(params[2p+2:end], 0.95)
    return ω, α, γ, β
end

function fit_egarch_qmle(e::Vector{Float64}, p::Int, q::Int; max_iter::Int=8000, tol::Float64=1e-5)
    v0 = var(e)
    if !(v0 > 0)
        return (NaN, NaN, Float64[], Float64[], Float64[], false, 0, "var_zero", Float64[], fill(NaN, 1+2p+q))
    end
    n_params = 1 + 2 * p + q
    x0 = vcat(log(max(v0, 1e-8)), fill(0.1, p), zeros(q))  # ω, α, γ, β 初始值
    if length(x0) != n_params
        x0 = vcat(log(max(v0, 1e-8)), fill(0.1, n_params - 1))
    end
    function obj(x::Vector{Float64})
        ω, α, γ, β = _pack_egarch_params(x, p, q)
        -egarch_loglik(e, ω, α, γ, β)
    end
    r = Optim.optimize(obj, x0, BFGS(), Optim.Options(iterations=max_iter, f_reltol=tol, g_reltol=tol))
    xm = Optim.minimizer(r)
    ωm, αm, γm, βm = _pack_egarch_params(xm, p, q)
    ll = egarch_loglik(e, ωm, αm, γm, βm)
    converged = Optim.converged(r) && isfinite(ll)
    iters = r.iterations
    okh, h = egarch_conditional_variances(e, ωm, αm, γm, βm)
    !okh && (return (NaN, ωm, αm, γm, βm, false, iters, "invalid_variance", fill(NaN, length(e)), fill(NaN, n_params)))
    se_all = _opg_standard_errors(xm, obj, length(e))
    return (ll, ωm, αm, γm, βm, converged, iters, "BFGS", h, se_all)
end

function MetricaBase.fit(model::EGARCHModel, data::DataFrame)
    data_sorted = sort_by_time(data, model.time_column)
    y = Float64.(data_sorted[!, model.variable])
    n = length(y)
    p, q = model.garch_p, model.garch_q
    n < 60 && error("EGARCH 需要至少 60 个观测")

    if model.mean_type == :ar
        ar_order = min(5, div(n, 10)); lags_y = create_lags(y, ar_order)
        y_dep = lags_y[:, 1]; y_lag = lags_y[:, 2:end]
        ar_beta = y_lag \ y_dep; e_ar = y_dep .- (y_lag * ar_beta)
        mu = mean(e_ar); e = e_ar .- mu
    else
        mu = mean(y); e = y .- mu
    end
    ll, ω, α, γ, β, converged, iters, optname, h, se_all, hess_stat =
        fit_egarch_qmle(e, p, q; max_iter=model.max_iter, tol=model.tol, dist=model.dist)

    failure = converged ? nothing : (hess_stat != "ok" ? "singular_hessian" : nothing)
    warnings = MetricaBase.ModelWarning[]
    if !converged && isnothing(failure)
        push!(warnings, MetricaBase.ModelWarning(:egarch_not_converged,
            "EGARCH 优化未收敛", "", "可增大 max_iter。", MetricaBase.warning))
    end

    persistence = sum(β)
    uncond = persistence < 1.0 ? exp(ω / (1.0 - persistence)) : NaN
    k_params = 1 + 1 + 2 * p + q
    aic = isfinite(ll) ? (-2 * ll + 2 * k_params) : NaN
    bic = isfinite(ll) ? (-2 * ll + k_params * log(n)) : NaN

    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :nobs => n, :loglik => ll, :aic => aic, :bic => bic,
        :garch_p => p, :garch_q => q, :persistence => persistence,
        :unconditional_variance => uncond,
    )
    glance_table = MetricaBase.ModelGlance(Symbol("EGARCH($p,$q)"), n, 0, glance_metrics, warnings)

    se_valid = all(isfinite, se_all) && all(s -> s > 0, se_all)
    crows = MetricaBase.CoefRow[]
    push!(crows, MetricaBase.CoefRow(:mu, mu, nothing, nothing, nothing, nothing, nothing))
    se_ω = se_valid ? se_all[1] : nothing
    push!(crows, MetricaBase.CoefRow(:omega, ω, se_ω, se_valid ? ω/se_ω : nothing, se_valid ? 2*(1-cdf(Normal(), abs(ω/se_ω))) : nothing, se_valid ? ω-1.96*se_ω : nothing, se_valid ? ω+1.96*se_ω : nothing))
    for i in 1:length(α)
        se_i = se_valid ? se_all[1+i] : nothing
        push!(crows, MetricaBase.CoefRow(Symbol("alpha_$i"), α[i], se_i, nothing, nothing, nothing, nothing))
    end
    for i in 1:length(γ)
        idx = 1 + p + i
        se_i = se_valid ? se_all[idx] : nothing
        push!(crows, MetricaBase.CoefRow(Symbol("gamma_$i"), γ[i], se_i, nothing, nothing, nothing, nothing))
    end
    for j in 1:length(β)
        idx = 1 + 2p + j
        se_j = se_valid ? se_all[idx] : nothing
        push!(crows, MetricaBase.CoefRow(Symbol("beta_$j"), β[j], se_j, nothing, nothing, nothing, nothing))
    end

    tidy_table = MetricaBase.TidyTable(crows, "BFGS QMLE")
    return EGARCHFitResult(string(model.variable), p, q, mu, ω, α, γ, β, ll, aic, bic,
        persistence, uncond, h, e, y, converged, optname, iters, failure,
        glance_table, tidy_table, warnings)
end

MetricaBase.glance(r::EGARCHFitResult) = r.glance_table
MetricaBase.tidy(r::EGARCHFitResult) = r.tidy_table
MetricaBase.nobs(r::EGARCHFitResult) = r.glance_table.nobs

function MetricaBase.model_capabilities(r::EGARCHFitResult)::MetricaBase.ModelCapabilities
    return MetricaBase.ModelCapabilities(:partial, :volatility, [:arch, :garch, :gjr_garch, :egarch],
        ["QMLE (Gaussian) + BFGS"], [:loglik, :persistence, :std_errors, :conditional_volatility],
        [:var, :es, :forecast, :student_t], Symbol[], false,
        ["EGARCH 支持非对称指数波动。VaR/ES/预测为后续功能。"])
end

MetricaBase.augment(::EGARCHFitResult) = AugmentTable()

function result_to_payload(r::EGARCHFitResult; include_augment::Bool=true)
    preview_n = 50
    σ = sqrt.(max.(r.conditional_variance, 1e-18))
    diag = Dict{String, Any}("converged" => r.converged, "iterations" => r.iterations,
        "optimizer" => r.optimizer, "loglik" => r.loglik,
        "persistence" => r.persistence, "unconditional_variance" => r.unconditional_variance,
        "conditional_volatility_preview" => σ[1:min(end, preview_n)],
        "volatility_length" => length(r.conditional_variance),
        "garch_p" => r.garch_p, "garch_q" => r.garch_q, "failure_code" => r.failure_code)
    caps = MetricaBase.model_capabilities(r)
    payload = Dict{String, Any}("model_type" => "egarch", "variable" => r.variable_name,
        "garch_p" => r.garch_p, "garch_q" => r.garch_q, "nobs" => length(r.original_series),
        "mu" => r.mu, "omega" => r.omega, "alpha" => r.alpha, "gamma" => r.gamma, "beta" => r.beta,
        "loglik" => r.loglik, "aic" => r.aic, "bic" => r.bic,
        "glance" => Dict("model" => string(r.glance_table.model), "nobs" => r.glance_table.nobs,
            "metrics" => Dict(string(k) => v for (k, v) in r.glance_table.metrics)),
        "tidy" => Dict("rows" => [Dict("term" => string(row.name), "estimate" => row.estimate, "stderror" => row.stderror, "statistic" => row.statistic, "p_value" => row.pvalue, "ci_lower" => row.ci_lower, "ci_upper" => row.ci_upper) for row in r.tidy_table.rows]),
        "diagnostics" => diag,
        "model_capabilities" => MetricaBase.capabilities_to_dict(caps),
        "augment_status" => MetricaBase.build_augment_status(r; available=include_augment,
            columns_available=include_augment ? ["residual"] : String[],
            columns_unavailable=["fitted", "std_residual"], preview_included=include_augment,
            preview_rows=include_augment ? min(length(r.original_series), 50) : 0))
    if !isempty(r.warnings)
        payload["warnings"] = [Dict("code" => string(w.code), "title" => w.title, "detail" => w.detail, "hint" => w.hint, "severity" => string(w.severity)) for w in r.warnings]
    end
    if include_augment
        m = min(length(r.original_series), 50)
        payload["augment_preview"] = Dict("obs" => collect(1.0:m), "y" => r.original_series[1:m], "residual" => r.residuals[1:m], "conditional_volatility" => σ[1:m])
    end
    return payload
end
