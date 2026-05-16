# === Metrica Runtime 时间序列 Julia 桥接入口 =================================
# 本脚本使用 MetricaTimeSeries.jl 自身 project 运行，避免与主 Runtime project
# 中的 Optim 版本约束冲突。
# ==============================================================================

using CSV
using DataFrames
using JSON3
using MetricaBase
using MetricaTimeSeries

request = JSON3.read(ARGS[1])
dataset_path = String(request.dataset_ref.path)
model_type = String(request.model_spec.model_type)

function tuple3_from_json(value, fallback::Tuple{Int,Int,Int})
    isnothing(value) && return fallback
    values = Int.(collect(value))
    length(values) == 3 || return fallback
    return (values[1], values[2], values[3])
end

function tuple4_from_json(value, fallback::Tuple{Int,Int,Int,Int})
    isnothing(value) && return fallback
    values = Int.(collect(value))
    length(values) == 4 || return fallback
    return (values[1], values[2], values[3], values[4])
end

# 与主桥接一致：非有限浮点数序列化为 null，避免 JSON3 拒绝写入。
function sanitize_json_floats(x::AbstractFloat)
    return isfinite(x) ? x : nothing
end
sanitize_json_floats(x::Integer) = x
sanitize_json_floats(x::Bool) = x
sanitize_json_floats(x::AbstractString) = x
sanitize_json_floats(::Nothing) = nothing
function sanitize_json_floats(x::AbstractDict)
    Dict(k => sanitize_json_floats(v) for (k, v) in pairs(x))
end
function sanitize_json_floats(x::AbstractVector)
    map(sanitize_json_floats, x)
end
sanitize_json_floats(x) = x

function runtime_fit_envelope(result_payload::AbstractDict)
    Dict{String, Any}(
        "status" => "success",
        "messages" => Any[],
        "result_payload" => result_payload,
        "artifacts" => Any[],
    )
end

function fit_time_series_model(model_type::String, model_spec, data)
    time_column = Symbol(String(model_spec.time_column))
    if model_type == "arima"
        model = MetricaTimeSeries.ARIMAModel(
            variable=Symbol(String(model_spec.variable)),
            time_column=time_column,
            order=tuple3_from_json(get(model_spec, :order, nothing), (1, 1, 1)),
            seasonal_order=tuple4_from_json(get(model_spec, :seasonal_order, nothing), (0, 0, 0, 0)),
            method=Symbol(String(get(model_spec, :ts_method, "mle"))),
        )
        return MetricaBase.fit(model, data)
    elseif model_type == "var"
        model = MetricaTimeSeries.VARModel(
            variables=Symbol.(String.(collect(model_spec.variables))),
            time_column=time_column,
            lags=Int(model_spec.lags),
        )
        return MetricaBase.fit(model, data)
    elseif model_type == "unitroot"
        model = MetricaTimeSeries.UnitRootModel(
            variable=Symbol(String(model_spec.variable)),
            time_column=time_column,
            deterministic=Symbol(String(get(model_spec, :deterministic, "constant"))),
            max_lags=Int(get(model_spec, :lags, 0)),
        )
        return MetricaBase.fit(model, data)
    elseif model_type == "cointegration"
        model = MetricaTimeSeries.CointegrationModel(
            variables=Symbol.(String.(collect(model_spec.variables))),
            time_column=time_column,
            method=Symbol(String(get(model_spec, :ts_method, "engle_granger"))),
            lags=Int(get(model_spec, :lags, 1)),
            deterministic=Symbol(String(get(model_spec, :deterministic, "constant"))),
        )
        return MetricaBase.fit(model, data)
    end
    error("未知时间序列模型类型：$model_type")
end

payload = try
    if String(request.action) != "fit_model"
        Dict(
            "status" => "error",
            "messages" => Any[Dict(
                "level" => "error",
                "code" => "UNSUPPORTED_ACTION",
                "text" => "时间序列桥接仅支持 fit_model。",
                "hint" => "请通过主桥接执行其他动作。",
            )],
        )
    else
        data = CSV.read(dataset_path, DataFrame)
        result = fit_time_series_model(model_type, request.model_spec, data)
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        runtime_fit_envelope(MetricaTimeSeries.result_to_payload(result; include_augment=include_augment))
    end
catch err
    Dict(
        "status" => "error",
        "messages" => Any[Dict(
            "level" => "error",
            "code" => "JULIA_TIME_SERIES_ERROR",
            "text" => "时间序列模型执行失败：$(sprint(showerror, err))",
            "hint" => "请检查时间列、变量列和阶数参数。",
        )],
    )
end

println(JSON3.write(sanitize_json_floats(payload)))
