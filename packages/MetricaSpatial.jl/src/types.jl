# === 空间计量拟合结果类型 =====================================================

struct SpatialFitResult
    model_kind::Symbol
    coef::Vector{Pair{Symbol, Float64}}
    stderror::Union{Nothing, Vector{Float64}}
    vcov_label::String
    residual::Vector{Float64}
    fitted::Vector{Float64}
    nobs::Int
    dof::Int
    spatial_param::Float64
    spatial_param_name::Symbol
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
    loglik::Union{Nothing, Float64}
end

struct GWRFitResult
    formula::String
    nobs::Int
    ncoef::Int
    coef_names::Vector{Symbol}
    local_coefficients::Matrix{Float64}
    local_stderrors::Union{Nothing, Matrix{Float64}}
    local_tvalues::Union{Nothing, Matrix{Float64}}
    local_r2::Vector{Float64}
    fitted::Vector{Float64}
    residual::Vector{Float64}
    bandwidth::Float64
    bandwidth_selection::String
    bandwidth_score::Float64
    kernel::String
    adaptive::Bool
    distance_metric::String
    effective_parameters::Float64
    sigma2::Float64
    aicc::Float64
    hat_diag::Vector{Float64}
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
end

struct GTWRFitResult
    formula::String
    nobs::Int
    ncoef::Int
    coef_names::Vector{Symbol}
    local_coefficients::Matrix{Float64}
    local_stderrors::Union{Nothing, Matrix{Float64}}
    local_tvalues::Union{Nothing, Matrix{Float64}}
    local_r2::Vector{Float64}
    fitted::Vector{Float64}
    residual::Vector{Float64}
    bandwidth::Float64
    bandwidth_selection::String
    bandwidth_score::Float64
    kernel::String
    adaptive::Bool
    distance_metric::String
    time_scale::Float64
    time_column::String
    time_range::Vector{Float64}
    spatiotemporal_distance_summary::Dict{Symbol, Any}
    effective_parameters::Float64
    sigma2::Float64
    aicc::Float64
    hat_diag::Vector{Float64}
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
end

struct ProbitFitResult
    formula::String
    nobs::Int
    ncoef::Int
    coef_names::Vector{Symbol}
    posterior_mean::Vector{Float64}
    posterior_sd::Vector{Float64}
    credible_lower::Vector{Float64}
    credible_upper::Vector{Float64}
    rho_mean::Float64
    rho_sd::Float64
    rho_credible_lower::Float64
    rho_credible_upper::Float64
    n_iter::Int
    n_warmup::Int
    n_chains::Int
    rhat::Union{Nothing, Vector{Float64}}
    ess::Union{Nothing, Vector{Float64}}
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
end
