module MetricaTimeSeries

using DataFrames
using Distributions
using HypothesisTests
using LinearAlgebra
using MetricaBase
using Optim
using Statistics

export AbstractTimeSeriesModel, AbstractTSFitResult,
    ARIMAModel, ARIMAFitResult,
    ARCHModel, ARCHFitResult,
    GARCHModel, GARCHFitResult,
    GJRModel, GJRFitResult,
    EGARCHModel, EGARCHFitResult,
    forecast_arch, forecast_garch,
    compute_var, compute_es_normal, kupiec_test, compute_volatility_diagnostics,
    VARModel, VARFitResult,
    UnitRootModel, UnitRootFitResult,
    CointegrationModel, CointegrationFitResult,
    fit, result_to_payload,
    forecast, impulse_response, variance_decomposition,
    granger_causality, adf_test, pp_test, kpss_test,
    engle_granger_test, johansen_test,
    acf, pacf, ljung_box_test,
    build_time_series_model

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
include("volatility_fit.jl")
include("arch.jl")
include("garch.jl")
include("gjr_garch.jl")
include("egarch.jl")
include("arima.jl")
include("var.jl")
include("cointegration.jl")
include("forecast.jl")
include("volatility_forecast.jl")
include("serialize.jl")

# === 统一构造函数 ==========================================================

"""
    build_time_series_model(model_type::String, params::Dict) -> AbstractTimeSeriesModel

从 JSON 参数统一构造时间序列模型实例。

# 参数
- `model_type`: 模型类型字符串，支持 "arima"、"var"、"unitroot"、"cointegration"、"arch"、"garch"
- `params`: 参数字典，包含模型构造所需的字段

# 返回值
对应的模型实例

# 示例
```julia
params = Dict(
    "variable" => "gdp",
    "time_column" => "time",
    "order" => [1, 1, 0],
)
model = build_time_series_model("arima", params)
```
"""
function build_time_series_model(model_type::String, params::Dict)
    time_col = Symbol(get(params, "time_column", "time"))

    # 注意：Julia 中 `get(d, k, default)` 的 default 会被**立即求值**；
    # 不得写成 `get(..., error(...))`，否则无论键是否存在都会抛错。应使用 `get(() -> error(...), d, k)`。
    if model_type == "arima"
        var_sym = Symbol(get(() -> error("ARIMA 模型需要 variable 参数"), params, "variable"))
        order_arr = get(params, "order", [1, 1, 0])
        length(order_arr) == 3 || error("order 必须有 3 个元素 [p, d, q]")
        order_tuple = Tuple(Int.(order_arr))
        seasonal_arr = get(params, "seasonal_order", [0, 0, 0, 0])
        length(seasonal_arr) == 4 || error("seasonal_order 必须有 4 个元素 [P, D, Q, S]")
        seasonal_tuple = Tuple(Int.(seasonal_arr))
        ts_method = Symbol(get(params, "ts_method", "mle"))
        return ARIMAModel(
            variable=var_sym,
            time_column=time_col,
            order=order_tuple,
            seasonal_order=seasonal_tuple,
            method=ts_method,
        )

    elseif model_type == "var"
        vars_raw = get(() -> error("VAR 模型需要 variables 参数"), params, "variables")
        var_syms = Symbol.(String.(vars_raw))
        lags = Int(get(params, "lags", 1))
        return VARModel(
            variables=var_syms,
            time_column=time_col,
            lags=lags,
        )

    elseif model_type == "unitroot"
        var_sym = Symbol(get(() -> error("单位根检验需要 variable 参数"), params, "variable"))
        det = Symbol(get(params, "deterministic", "constant"))
        max_lags = Int(get(params, "lags", 0))
        return UnitRootModel(
            variable=var_sym,
            time_column=time_col,
            deterministic=det,
            max_lags=max_lags,
        )

    elseif model_type == "cointegration"
        vars_raw = get(() -> error("协整检验需要 variables 参数"), params, "variables")
        var_syms = Symbol.(String.(vars_raw))
        method = Symbol(get(params, "ts_method", "engle_granger"))
        lags = Int(get(params, "lags", 1))
        det = Symbol(get(params, "deterministic", "constant"))
        return CointegrationModel(
            variables=var_syms,
            time_column=time_col,
            method=method,
            lags=lags,
            deterministic=det,
        )

    elseif model_type == "arch"
        var_sym = Symbol(get(() -> error("ARCH 模型需要 variable 参数"), params, "variable"))
        raw_q = get(params, "arch_order", nothing)
        raw_q === nothing && error("ARCH 模型需要 arch_order 参数")
        arch_order = Int(raw_q)
        mi = Int(get(params, "garch_max_iter", 5000))
        tol = Float64(get(params, "garch_tol", 1e-5))
        dist = Symbol(get(params, "volatility_dist", "gaussian"))
        mt = Symbol(get(params, "mean_type", "constant"))
        return ARCHModel(variable=var_sym, time_column=time_col, arch_order=arch_order,
            mean_type=mt, max_iter=mi, tol=tol, dist=dist)

    elseif model_type == "garch"
        var_sym = Symbol(get(() -> error("GARCH 模型需要 variable 参数"), params, "variable"))
        gp = Int(get(params, "garch_p", 1)); gq = Int(get(params, "garch_q", 1))
        mi = Int(get(params, "garch_max_iter", 8000)); tol = Float64(get(params, "garch_tol", 1e-5))
        dist = Symbol(get(params, "volatility_dist", "gaussian"))
        mt = Symbol(get(params, "mean_type", "constant"))
        return GARCHModel(variable=var_sym, time_column=time_col, garch_p=gp, garch_q=gq,
            mean_type=mt, max_iter=mi, tol=tol, dist=dist)

    elseif model_type == "gjr_garch"
        var_sym = Symbol(get(() -> error("GJR-GARCH 模型需要 variable 参数"), params, "variable"))
        gp = Int(get(params, "garch_p", 1)); gq = Int(get(params, "garch_q", 1))
        mi = Int(get(params, "garch_max_iter", 8000)); tol = Float64(get(params, "garch_tol", 1e-5))
        dist = Symbol(get(params, "volatility_dist", "gaussian"))
        mt = Symbol(get(params, "mean_type", "constant"))
        return GJRModel(variable=var_sym, time_column=time_col, garch_p=gp, garch_q=gq,
            mean_type=mt, max_iter=mi, tol=tol, dist=dist)

    elseif model_type == "egarch"
        var_sym = Symbol(get(() -> error("EGARCH 模型需要 variable 参数"), params, "variable"))
        gp = Int(get(params, "garch_p", 1)); gq = Int(get(params, "garch_q", 1))
        mi = Int(get(params, "garch_max_iter", 8000)); tol = Float64(get(params, "garch_tol", 1e-5))
        dist = Symbol(get(params, "volatility_dist", "gaussian"))
        mt = Symbol(get(params, "mean_type", "constant"))
        return EGARCHModel(variable=var_sym, time_column=time_col, garch_p=gp, garch_q=gq,
            mean_type=mt, max_iter=mi, tol=tol, dist=dist)

    else
        error("未知时间序列模型类型：$model_type")
    end
end

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
        if isdefined(@__MODULE__, :ARCHModel)
            MetricaBase.MODEL_REGISTRY["arch"] = ARCHModel
        end
        if isdefined(@__MODULE__, :GARCHModel)
            MetricaBase.MODEL_REGISTRY["garch"] = GARCHModel
        end
    end
end

end # module MetricaTimeSeries
