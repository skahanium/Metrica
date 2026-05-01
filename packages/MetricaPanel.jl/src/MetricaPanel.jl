module MetricaPanel

using DataFrames
using Distributions
using LinearAlgebra
using MetricaBase
using Statistics
using StatsModels

export PanelModel, PanelFitResult, fit_panel, result_to_payload

"""
面板模型规格对象。

包含面板拟合所需的所有参数：公式、个体标识、时间标识和估计方法。
"""
struct PanelModel <: MetricaBase.AbstractPanelModel
    formula::String
    id_col::Symbol
    time_col::Symbol
    method::Symbol  # :fe, :re, :fd, :between
end

"""
面板模型的结构化拟合结果。

承载面板拟合后的所有结果载荷，包括摘要、系数表、拟合值和残差。
"""
struct PanelFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    panel_data::MetricaBase.PanelData
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
    method::Symbol
end

MetricaBase.glance(result::PanelFitResult) = result.glance_table
MetricaBase.tidy(result::PanelFitResult) = result.tidy_table

function MetricaBase.augment(result::PanelFitResult)
    nobs = length(result.fitted_values)
    return MetricaBase.AugmentTable(
        Dict(
            :observation => collect(1.0:nobs),
            :fitted => result.fitted_values,
            :residual => result.residual_vector,
        ),
        nobs,
    )
end

"""
    fit_panel(panel_data::PanelData, formula::String; method::Symbol=:fe)

面板模型拟合入口。

根据 `method` 参数选择估计方法：
- `:fe` — 固定效应（默认）
- `:re` — 随机效应
- `:fd` — 一阶差分
- `:between` — 组间估计

返回 `PanelFitResult`。
"""
function fit_panel(panel_data::MetricaBase.PanelData, formula::String; method::Symbol=:fe)
    if method === :fe
        return fit_fe(panel_data, formula)
    else
        error("面板估计方法 :$method 尚未实现")
    end
end

include("fe.jl")
include("serialize.jl")

end
