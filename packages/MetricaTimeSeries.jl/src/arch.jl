# arch.jl — ARCH(q) 常数均值 + Gaussian QMLE

"""
    ARCHModel <: AbstractTimeSeriesModel

ARCH(q) 波动率模型规格（常数均值）。
"""
struct ARCHModel <: AbstractTimeSeriesModel
    variable::Symbol
    time_column::Symbol
    arch_order::Int
    max_iter::Int
    tol::Float64
end

"""
    ARCHFitResult <: AbstractTSFitResult

ARCH 拟合结果。
"""
struct ARCHFitResult <: AbstractTSFitResult
    variable_name::String
    arch_order::Int
    mu::Float64
    omega::Float64
    alpha::Vector{Float64}
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

function ARCHModel(;
    variable::Symbol,
    time_column::Symbol,
    arch_order::Int,
    max_iter::Int = 5000,
    tol::Float64 = 1e-5,
)
    return ARCHModel(variable, time_column, arch_order, max_iter, tol)
end

function _arch_min_nobs(q::Int)
    return 30 + 5 * q
end

function MetricaBase.fit(model::ARCHModel, data::DataFrame)
    data_sorted = sort_by_time(data, model.time_column)
    y = Float64.(data_sorted[!, model.variable])
    n = length(y)
    q = model.arch_order
    if q < 1
        error("arch_order 须为不小于 1 的整数")
    end
    if q > 12
        error("arch_order 超过实现上界 12")
    end
    nmin = _arch_min_nobs(q)
    if n < nmin
        error("ARCH(q=$q) 需要至少 $nmin 个有效观测，当前 n=$n")
    end

    mu = mean(y)
    e = y .- mu

    ll, ω, α, converged, iters, optname, h = fit_arch_qmle(e, q; max_iter=model.max_iter, tol=model.tol)
    failure = nothing
    warnings = MetricaBase.ModelWarning[]

    if !isfinite(ll) || !all(isfinite, h)
        failure = "fit_failed"
        push!(
            warnings,
            MetricaBase.ModelWarning(
                :arch_fit_failed,
                "ARCH 优化或方差递推失败",
                "对数似然非有限或条件方差非正。",
                "检查序列是否为常数、样本是否过短或尝试调整 garch_max_iter / garch_tol。",
                MetricaBase.warning,
            ),
        )
    elseif !converged
        failure = "optimizer_not_converged"
        push!(
            warnings,
            MetricaBase.ModelWarning(
                :arch_not_converged,
                "ARCH 优化未收敛",
                "数值优化在迭代上限内未满足收敛判据。",
                "可增大 garch_max_iter 或放宽容差。",
                MetricaBase.warning,
            ),
        )
    end

    persistence = isempty(α) ? 0.0 : sum(α)
    uncond = (isfinite(ω) && persistence < 1.0 - 1e-8) ? _arch_unconditional_variance(ω, α) : NaN

    k = 1 + 1 + q
    aic = isfinite(ll) ? (-2 * ll + 2 * k) : NaN
    bic = isfinite(ll) ? (-2 * ll + k * log(n)) : NaN

    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :nobs => n,
        :loglik => ll,
        :aic => aic,
        :bic => bic,
        :arch_order => float(q),
        :persistence => persistence,
        :unconditional_variance => uncond,
    )
    glance_table = MetricaBase.ModelGlance(Symbol("ARCH($q)"), n, 0, glance_metrics, warnings)

    coef_rows = MetricaBase.CoefRow[]
    push!(coef_rows, MetricaBase.CoefRow(:mu, mu, nothing, nothing, nothing, nothing, nothing))
    push!(coef_rows, MetricaBase.CoefRow(:omega, ω, nothing, nothing, nothing, nothing, nothing))
    for i in 1:length(α)
        push!(coef_rows, MetricaBase.CoefRow(Symbol("alpha_$i"), α[i], nothing, nothing, nothing, nothing, nothing))
    end
    tidy_table = MetricaBase.TidyTable(coef_rows, "std.error")

    return ARCHFitResult(
        string(model.variable),
        q,
        mu,
        ω,
        α,
        ll,
        aic,
        bic,
        persistence,
        uncond,
        h,
        e,
        y,
        converged,
        optname,
        iters,
        failure,
        glance_table,
        tidy_table,
        warnings,
    )
end

function MetricaBase.glance(r::ARCHFitResult)
    return r.glance_table
end

function MetricaBase.tidy(r::ARCHFitResult)
    return r.tidy_table
end

function MetricaBase.nobs(r::ARCHFitResult)
    return r.glance_table.nobs
end

function result_to_payload(r::ARCHFitResult; include_augment::Bool = true)
    preview_n = 50
    σ = sqrt.(max.(r.conditional_variance, 1e-18))
    std_resid = [abs(σ[i]) > 1e-18 ? r.residuals[i] / σ[i] : 0.0 for i in 1:length(σ)]
    prev_h = r.conditional_variance[1:min(end, preview_n)]
    diag = Dict{String, Any}(
        "converged" => r.converged,
        "iterations" => r.iterations,
        "optimizer" => r.optimizer,
        "loglik" => r.loglik,
        "persistence" => r.persistence,
        "unconditional_variance" => r.unconditional_variance,
        "conditional_volatility_preview" => sqrt.(max.(prev_h, 1e-18)),
        "volatility_length" => length(r.conditional_variance),
        "arch_order" => r.arch_order,
        "failure_code" => r.failure_code,
    )

    payload = Dict{String, Any}(
        "model_type" => "arch",
        "variable" => r.variable_name,
        "arch_order" => r.arch_order,
        "nobs" => length(r.original_series),
        "mu" => r.mu,
        "omega" => r.omega,
        "alpha" => r.alpha,
        "loglik" => r.loglik,
        "aic" => r.aic,
        "bic" => r.bic,
        "glance" => Dict(
            "model" => string(r.glance_table.model),
            "nobs" => r.glance_table.nobs,
            "metrics" => Dict(string(k) => v for (k, v) in r.glance_table.metrics),
        ),
        "tidy" => Dict(
            "rows" => [
                Dict(
                    "term" => string(row.name),
                    "estimate" => row.estimate,
                    "stderror" => row.stderror,
                    "statistic" => row.statistic,
                    "p_value" => row.pvalue,
                    "ci_lower" => row.ci_lower,
                    "ci_upper" => row.ci_upper,
                )
                for row in r.tidy_table.rows
            ],
        ),
        "diagnostics" => diag,
    )

    if !isempty(r.warnings)
        payload["warnings"] = [
            Dict(
                "code" => string(w.code),
                "title" => w.title,
                "detail" => w.detail,
                "hint" => w.hint,
                "severity" => string(w.severity),
            )
            for w in r.warnings
        ]
    end

    if include_augment
        m = min(length(r.original_series), 50)
        payload["augment_preview"] = Dict(
            "obs" => collect(1.0:m),
            "y" => r.original_series[1:m],
            "residual" => r.residuals[1:m],
            "conditional_volatility" => sqrt.(max.(r.conditional_variance[1:m], 1e-18)),
            "std_residual" => std_resid[1:m],
        )
    end

    return payload
end
