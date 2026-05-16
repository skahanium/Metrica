# === MetricaBase 接口：glance / tidy / coef 等 =================================

function MetricaBase.nobs(r::SpatialFitResult)::Int
    return r.nobs
end

function MetricaBase.dof(r::SpatialFitResult)::Int
    return r.dof
end

function MetricaBase.coef(r::SpatialFitResult)::Vector{Pair{Symbol, Float64}}
    return r.coef
end

function MetricaBase.residuals(r::SpatialFitResult)::Vector{Float64}
    return r.residual
end

function MetricaBase.fitted(r::SpatialFitResult)::Vector{Float64}
    return r.fitted
end

function MetricaBase.stderror(r::SpatialFitResult)::Union{Nothing, Vector{Float64}}
    return r.stderror
end

function MetricaBase.glance(r::SpatialFitResult)::MetricaBase.ModelGlance
    mname = r.model_kind
    metrics = Dict{Symbol, MetricaBase.MetricValue}()
    metrics[:spatial_param] = r.spatial_param
    if r.loglik !== nothing
        ll = r.loglik::Float64
        metrics[:loglik] = ll
        n = r.nobs
        k = length(r.coef)
        metrics[:aic] = 2 * k - 2 * ll
        metrics[:bic] = k * log(n) - 2 * ll
    end
    return MetricaBase.ModelGlance(mname, r.nobs, r.dof, metrics, r.warnings)
end

function MetricaBase.tidy(r::SpatialFitResult)::MetricaBase.TidyTable
    rows = MetricaBase.CoefRow[]
    ses = r.stderror === nothing ? fill(nothing, length(r.coef)) : r.stderror
    for (i, pr) in enumerate(r.coef)
        name = pr[1]
        est = pr[2]
        raw_se = i <= length(ses) ? ses[i] : nothing
        se = raw_se === nothing ? nothing : (raw_se isa Float64 && isnan(raw_se) ? nothing : Float64(raw_se))
        tstat = se === nothing || se == 0.0 ? nothing : est / se
        push!(
            rows,
            MetricaBase.CoefRow(name, est, se, tstat, nothing, nothing, nothing),
        )
    end
    return MetricaBase.TidyTable(rows, r.vcov_label)
end

function MetricaBase.model_capabilities(r::SpatialFitResult)::MetricaBase.ModelCapabilities
    available = [:moran_i, :moran_ei, :moran_var, :moran_z, :moran_pvalue]
    effects = if r.model_kind in (:spatial_lag, :spatial_slx)
        [:direct_effects, :indirect_effects, :total_effects]
    else
        Symbol[]
    end
    unavailable = if r.model_kind == :spatial_error
        [:direct_effects, :indirect_effects, :total_effects, :lm_lag, :lm_error, :robust_lm_lag, :robust_lm_error]
    else
        [:lm_lag, :lm_error, :robust_lm_lag, :robust_lm_error]
    end
    return MetricaBase.ModelCapabilities(
        :implemented,
        :spatial,
        [:spatial_lag, :spatial_error, :spatial_slx],
        r.model_kind == :spatial_error ? ["Gaussian ML"] : (r.model_kind == :spatial_slx ? ["OLS"] : ["2SLS"]),
        available,
        unavailable,
        effects,
        true,
        ["SDM、SAC/SARAR、空间 Probit 与 GWR 尚未暴露为可调用模型。"],
    )
end
