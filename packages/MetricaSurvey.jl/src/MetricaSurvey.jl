module MetricaSurvey

using CSV
using DataFrames
using Distributions
using JSON3
using LinearAlgebra
using MetricaBase
using MetricaLinear
using MetricaDiscrete
using Statistics
using StatsModels

export AbstractSurveyModel, AbstractSurveyFitResult,
    SurveyDesign,
    SurveyOLSModel, SurveyLogitModel, SurveyProbitModel, SurveyPoissonModel,
    SurveyOLSFitResult, SurveyLogitFitResult, SurveyProbitFitResult, SurveyPoissonFitResult,
    DEFFResult,
    fit, result_to_payload,
    design_effect, strata_summary

# === 抽象类型 ==================================================================

abstract type AbstractSurveyModel <: MetricaBase.AbstractEconModel end
abstract type AbstractSurveyFitResult <: MetricaBase.AbstractFittedModel end

# === SurveyDesign：抽样设计元数据包装器 ==========================================

struct SurveyDesign
    data::DataFrame
    weights_column::Symbol
    strata_column::Union{Nothing, Symbol}
    psu_column::Union{Nothing, Symbol}
    fpc_column::Union{Nothing, Symbol}
end

# === 具体模型类型 ===============================================================

struct SurveyOLSModel <: AbstractSurveyModel
    formula::String
end

struct SurveyLogitModel <: AbstractSurveyModel
    formula::String
end

struct SurveyProbitModel <: AbstractSurveyModel
    formula::String
end

struct SurveyPoissonModel <: AbstractSurveyModel
    formula::String
end

# === 拟合结果类型 ===============================================================

struct SurveyOLSFitResult <: AbstractSurveyFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    ols_result::MetricaLinear.OLSFitResult
    survey_vcov::Matrix{Float64}
    survey_se::Vector{Float64}
    design_effects::Vector{Float64}
    effective_n::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
end

struct SurveyLogitFitResult <: AbstractSurveyFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    discrete_result::MetricaDiscrete.LogitFitResult
    survey_vcov::Matrix{Float64}
    survey_se::Vector{Float64}
    design_effects::Vector{Float64}
    effective_n::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
end

struct SurveyProbitFitResult <: AbstractSurveyFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    discrete_result::MetricaDiscrete.ProbitFitResult
    survey_vcov::Matrix{Float64}
    survey_se::Vector{Float64}
    design_effects::Vector{Float64}
    effective_n::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
end

struct SurveyPoissonFitResult <: AbstractSurveyFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    discrete_result::MetricaDiscrete.PoissonFitResult
    survey_vcov::Matrix{Float64}
    survey_se::Vector{Float64}
    design_effects::Vector{Float64}
    effective_n::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
end

# === DEFF 结果 =================================================================

struct DEFFResult
    coefficient::Vector{String}
    deff::Vector{Float64}
    n_eff::Vector{Float64}
    srs_se::Vector{Float64}
    survey_se::Vector{Float64}
end

# === 子模块 ====================================================================

include("survey_design.jl")
include("survey_ols.jl")
include("survey_glm.jl")
include("deff.jl")
include("serialize.jl")

# === 模型注册 ==================================================================

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}(
            "survey_ols" => SurveyOLSModel,
            "survey_logit" => SurveyLogitModel,
            "survey_probit" => SurveyProbitModel,
            "survey_poisson" => SurveyPoissonModel,
        ))
    end
end

end
