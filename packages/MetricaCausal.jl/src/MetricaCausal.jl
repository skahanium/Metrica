module MetricaCausal

using CSV
using DataFrames
using Distributions
using LinearAlgebra
using MetricaBase
using MetricaDiscrete
using MetricaLinear
using MetricaPanel
using Statistics
using StatsModels

export AbstractCausalModel, AbstractCausalFitResult,
    DIDModel, EventStudyModel, IPWModel, PSMModel, AIPWModel,
    DIDFitResult, EventStudyFitResult, IPWFitResult, PSMFitResult, AIPWFitResult,
    TreatmentEffectSummary,
    fit_twfe, compare_estimates,
    fit, result_to_payload

# === 抽象类型 =============================================================

abstract type AbstractCausalModel <: MetricaBase.AbstractEconModel end
abstract type AbstractCausalFitResult <: MetricaBase.AbstractFittedModel end

# === 具体模型规格类型 =====================================================

struct DIDModel <: AbstractCausalModel
    formula::String
end

struct EventStudyModel <: AbstractCausalModel
    formula::String
end

struct IPWModel <: AbstractCausalModel
    formula::String
end

struct PSMModel <: AbstractCausalModel
    formula::String
end

struct AIPWModel <: AbstractCausalModel
    formula::String
end

# === 拟合结果类型 ==========================================================

struct DIDFitResult <: AbstractCausalFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    treat_effect::Float64
    treat_effect_se::Float64
    treat_effect_pvalue::Float64
    n_treated::Int
    n_control::Int
    n_pre::Int
    n_post::Int
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    loglikelihood::Float64
end

struct EventStudyFitResult <: AbstractCausalFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    period_coefficients::Vector{Float64}
    period_stderrors::Vector{Float64}
    period_labels::Vector{String}
    pre_trend_pvalue::Float64
    parallel_trends_supported::Bool
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    loglikelihood::Float64
end

struct IPWFitResult <: AbstractCausalFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    propensity_model::LogitFitResult
    ate::Float64; ate_se::Float64
    att::Float64; att_se::Float64
    atu::Float64; atu_se::Float64
    weights::Vector{Float64}
    loglikelihood::Float64
end

struct PSMFitResult <: AbstractCausalFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    propensity_model::LogitFitResult
    att::Float64; att_se::Float64
    n_matched::Int
    balance_table::DataFrame
    loglikelihood::Float64
end

struct AIPWFitResult <: AbstractCausalFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    ate::Float64; ate_se::Float64
    att::Float64; att_se::Float64
    outcome_model::Any  # NamedTuple{(:treated, :control)} 两个结果模型
    propensity_model::LogitFitResult
    loglikelihood::Float64
end

# === 处理效应汇总 ==========================================================

struct TreatmentEffectSummary
    method::Symbol
    ate::Float64; ate_se::Float64
    att::Float64; att_se::Float64
    atu::Float64; atu_se::Float64
    nobs_treated::Int; nobs_control::Int
end

function compare_estimates(estimates::Dict{Symbol, AbstractCausalFitResult})
    summaries = TreatmentEffectSummary[]
    for (method, result) in estimates
        if result isa DIDFitResult
            push!(summaries, TreatmentEffectSummary(method, result.treat_effect, result.treat_effect_se,
                result.treat_effect, result.treat_effect_se, result.treat_effect, result.treat_effect_se,
                result.n_treated, result.n_control))
        elseif result isa IPWFitResult
            push!(summaries, TreatmentEffectSummary(method, result.ate, result.ate_se,
                result.att, result.att_se, result.atu, result.atu_se, 0, 0))
        elseif result isa PSMFitResult
            push!(summaries, TreatmentEffectSummary(method, result.att, result.att_se,
                result.att, result.att_se, result.att, result.att_se, result.n_matched, 0))
        elseif result isa AIPWFitResult
            push!(summaries, TreatmentEffectSummary(method, result.ate, result.ate_se,
                result.att, result.att_se, result.ate, result.ate_se, 0, 0))
        end
    end
    return summaries
end

# 子模块
include("twfe.jl")
include("did.jl")
include("event_study.jl")
include("ipw.jl")
include("psm.jl")
include("doubly_robust.jl")
include("serialize.jl")

# === augment 桩：因果推断模型暂不支持增广诊断 ==================================
MetricaBase.augment(::DIDFitResult) = AugmentTable()
MetricaBase.augment(::EventStudyFitResult) = AugmentTable()
MetricaBase.augment(::IPWFitResult) = AugmentTable()
MetricaBase.augment(::PSMFitResult) = AugmentTable()
MetricaBase.augment(::AIPWFitResult) = AugmentTable()

# === MODEL_REGISTRY 注册 =====================================================

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}(
            "did" => DIDModel,
            "event_study" => EventStudyModel,
            "ipw" => IPWModel,
            "psm" => PSMModel,
            "aipw" => AIPWModel,
        ))
    end
end

end
