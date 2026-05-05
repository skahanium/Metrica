module MetricaTimeSeries

using DataFrames
using Distributions
using HypothesisTests
using LinearAlgebra
using MetricaBase
using Optim
using StateSpaceModels
using Statistics

export AbstractTimeSeriesModel, AbstractTSFitResult,
    ARIMAModel, ARIMAFitResult,
    VARModel, VARFitResult,
    UnitRootModel, UnitRootFitResult,
    CointegrationModel, CointegrationFitResult,
    fit, result_to_payload,
    forecast, impulse_response, variance_decomposition,
    granger_causality, adf_test, pp_test, kpss_test,
    engle_granger_test, johansen_test,
    acf, pacf, ljung_box_test

# === 抽象类型 =============================================================

"""
    AbstractTimeSeriesModel <: AbstractEconModel

所有时间序列模型规格的抽象父类型。
"""
abstract type AbstractTimeSeriesModel <: MetricaBase.AbstractEconModel end

"""
    AbstractTSFitResult <: AbstractFittedModel

所有时间序列模型拟合结果的抽象父类型。
"""
abstract type AbstractTSFitResult <: MetricaBase.AbstractFittedModel end

# === 时间索引工具 ==========================================================

"""
    sort_by_time(data::DataFrame, time_column::Symbol) -> DataFrame

按时间列排序数据，返回排序后的 DataFrame。
"""
function sort_by_time(data::DataFrame, time_column::Symbol)
    return sort(data, time_column)
end

"""
    create_lags(y::Vector{Float64}, max_lags::Int) -> Matrix{Float64}

创建滞后矩阵。返回 (n - max_lags) × (max_lags + 1) 矩阵，
第一列为 y[t]，后续列为 y[t-1], y[t-2], ...。
"""
function create_lags(y::Vector{Float64}, max_lags::Int)
    n = length(y)
    result = zeros(n - max_lags, max_lags + 1)
    for i in 1:(n - max_lags)
        result[i, 1] = y[i + max_lags]
        for j in 1:max_lags
            result[i, j + 1] = y[i + max_lags - j]
        end
    end
    return result
end

"""
    difference(y::Vector{Float64}, d::Int=1) -> Vector{Float64}

对序列进行 d 阶差分。
"""
function difference(y::Vector{Float64}, d::Int=1)
    result = copy(y)
    for _ in 1:d
        result = diff(result)
    end
    return result
end

"""
    standardize_series(y::Vector{Float64}) -> Vector{Float64}

标准化序列（零均值、单位方差）。
"""
function standardize_series(y::Vector{Float64})
    μ = mean(y)
    σ = std(y)
    return σ > 0 ? (y .- μ) ./ σ : zeros(length(y))
end

"""
    remove_missing_pairs(y::Vector, X::Matrix) -> (Vector, Matrix)

同时移除 y 和 X 中含缺失值的观测。
"""
function remove_missing_pairs(y::Vector, X::Matrix)
    valid = .!ismissing.(y) .& vec(.!any(ismissing.(X), dims=2))
    return y[valid], X[valid, :]
end

# === 顺序加载各模块 =======================================================

include("unitroot.jl")
include("arima.jl")
include("var.jl")
include("cointegration.jl")
include("forecast.jl")
include("serialize.jl")

# === 注册到 MetricaBase MODEL_REGISTRY ====================================

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        # 各类型在对应模块中定义后注册
        if isdefined(@__MODULE__, :ARIMAModel)
            MetricaBase.MODEL_REGISTRY["arima"] = ARIMAModel
        end
        if isdefined(@__MODULE__, :VARModel)
            MetricaBase.MODEL_REGISTRY["var"] = VARModel
        end
        if isdefined(@__MODULE__, :UnitRootModel)
            MetricaBase.MODEL_REGISTRY["unitroot"] = UnitRootModel
        end
        if isdefined(@__MODULE__, :CointegrationModel)
            MetricaBase.MODEL_REGISTRY["cointegration"] = CointegrationModel
        end
    end
end

end # module MetricaTimeSeries
