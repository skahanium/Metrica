struct BayesLinearModel <: MetricaBase.AbstractEconModel end

struct BayesFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    posterior_mean::Vector{Float64}
    posterior_sd::Vector{Float64}
    credible_lower::Vector{Float64}
    credible_upper::Vector{Float64}
    coef_names::Vector{Symbol}
    inference_mode::String              # "analytical" | "mcmc"
    prior_family::String                # "normal_independent"
    sigma2_known::Bool
    sigma2_value::Float64               # NaN if unknown
    log_marginal_likelihood::Union{Nothing, Float64}
    n_obs::Int
    n_coef::Int
    seed_used::Union{Nothing, Int}
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
end
