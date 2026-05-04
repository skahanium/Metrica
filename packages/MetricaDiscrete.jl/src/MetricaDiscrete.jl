module MetricaDiscrete

using CSV
using DataFrames
using Distributions
using LinearAlgebra
using MetricaBase
using MetricaLinear
using Statistics
using StatsModels

export AbstractDiscreteModel, AbstractDiscreteFitResult,
    LogitModel, ProbitModel, PoissonModel,
    OrderedLogitModel, MultinomialLogitModel, NegBinModel,
    LogitFitResult, ProbitFitResult, PoissonFitResult,
    OrderedLogitFitResult, MultinomialLogitFitResult, NegBinFitResult,
    fit, result_to_payload,
    ame, mem, lr_test, compare_aic_bic

# === 抽象类型 =============================================================

abstract type AbstractDiscreteModel <: MetricaBase.AbstractEconModel end
abstract type AbstractDiscreteFitResult <: MetricaBase.AbstractFittedModel end

# === 链接函数 =============================================================

struct Link
    name::Symbol
    linkfun::Function
    linkinv::Function
    mu_eta::Function
    variance::Function
    initialize::Function
end

const LOGIT_LINK = Link(
    :logit,
    η -> 1.0 ./ (1.0 .+ exp.(-η)),
    μ -> log.(μ ./ (1.0 .- μ)),
    μ -> μ .* (1.0 .- μ),
    μ -> μ .* (1.0 .- μ),
    (y, μ) -> log.(μ ./ (1.0 .- μ)) .+ (y .- μ) ./ (μ .* (1.0 .- μ)),
)

const PROBIT_LINK = let
    norm = Normal(0, 1)
    Link(
        :probit,
        η -> cdf.(norm, η),
        μ -> quantile.(norm, μ),
        μ -> pdf.(norm, quantile.(norm, μ)),
        μ -> μ .* (1.0 .- μ),
        (y, μ) -> begin
            η = quantile.(norm, μ)
            η .+ (y .- μ) ./ pdf.(norm, η)
        end,
    )
end

const LOG_LINK = Link(
    :log,
    η -> exp.(η),
    μ -> log.(μ),
    μ -> μ,
    μ -> μ,
    (y, μ) -> log.(μ) .+ (y .- μ) ./ μ,
)

# === 具体模型类型（占位）==================================================

struct LogitModel <: AbstractDiscreteModel
    formula::String
end

struct ProbitModel <: AbstractDiscreteModel
    formula::String
end

struct PoissonModel <: AbstractDiscreteModel
    formula::String
end

struct OrderedLogitModel <: AbstractDiscreteModel
    formula::String
end

struct MultinomialLogitModel <: AbstractDiscreteModel
    formula::String
    reference_category::Int
end

struct NegBinModel <: AbstractDiscreteModel
    formula::String
end

# === 拟合结果类型（占位）==================================================

struct LogitFitResult <: AbstractDiscreteFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    linear_predictor::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    deviance::Float64
    loglikelihood::Float64
    iterations::Int
    converged::Bool
end

struct ProbitFitResult <: AbstractDiscreteFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    linear_predictor::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    deviance::Float64
    loglikelihood::Float64
    iterations::Int
    converged::Bool
end

struct PoissonFitResult <: AbstractDiscreteFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    linear_predictor::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    deviance::Float64
    loglikelihood::Float64
    iterations::Int
    converged::Bool
end

struct OrderedLogitFitResult <: AbstractDiscreteFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Matrix{Float64}
    thresholds::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    deviance::Float64
    loglikelihood::Float64
    iterations::Int
    converged::Bool
    n_categories::Int
end

struct MultinomialLogitFitResult <: AbstractDiscreteFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Matrix{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_matrix::Matrix{Float64}
    vcov_matrices::Vector{Matrix{Float64}}
    stderror_matrix::Matrix{Float64}
    categories::Vector{Int}
    reference::Int
    loglikelihood::Float64
    converged::Bool
end

struct NegBinFitResult <: AbstractDiscreteFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    linear_predictor::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    dispersion::Float64
    deviance::Float64
    loglikelihood::Float64
    iterations::Int
    converged::Bool
end

# 子模块加载
include("irls.jl")
include("logit.jl")
include("probit.jl")
include("poisson.jl")
include("serialize.jl")
# include("ologit.jl")
# include("mlogit.jl")
# include("negbin.jl")
# include("margins.jl")
# include("model_selection.jl")

# __init__ 注册到 MODEL_REGISTRY
function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}(
            "logit" => LogitModel,
            "probit" => ProbitModel,
            "poisson" => PoissonModel,
            "ordered_logit" => OrderedLogitModel,
            "multinomial_logit" => MultinomialLogitModel,
            "negbin" => NegBinModel,
        ))
    end
end

end
