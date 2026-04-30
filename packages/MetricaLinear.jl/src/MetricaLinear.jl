module MetricaLinear

using CSV
using DataFrames
using Distributions
using JSON3
using LinearAlgebra
using Statistics
using StatsModels
using MetricaBase
using MetricaOutput

export OLSModel, OLSFitResult, PHASE_1_MODELS, fit_ols_file, inspect_dataset, result_to_payload

const PHASE_1_MODELS = (:OLS,)

"""
第一条参考线性模型的规格对象。
"""
struct OLSModel <: MetricaBase.AbstractEconModel
    formula::String
end

"""
第一条真实 OLS 链路的结构化拟合结果。
"""
struct OLSFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
end

MetricaBase.glance(result::OLSFitResult) = result.glance_table
MetricaBase.tidy(result::OLSFitResult) = result.tidy_table

include("io.jl")
include("ols.jl")
include("serialize.jl")

end
