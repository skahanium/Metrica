# === Metrica Runtime 时间序列 Julia 桥接入口 =================================
# 本脚本使用 MetricaTimeSeries.jl 自身 project 运行，避免与主 Runtime project
# 中的 Optim 版本约束冲突。
# ==============================================================================

using CSV
using DataFrames
using JSON3
using MetricaBase
using MetricaTimeSeries

# 加载共享工具模块
include(joinpath(@__DIR__, "daemon", "src", "MetricaDaemon.jl"))
using .MetricaDaemon

request = JSON3.read(ARGS[1])
dataset_path = String(request.dataset_ref.path)
model_type = String(request.model_spec.model_type)

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
        # 将 JSON3 对象转换为 Dict 供 build_time_series_model 使用
        params = Dict{String, Any}()
        for key in keys(request.model_spec)
            params[String(key)] = request.model_spec[key]
        end
        model = MetricaTimeSeries.build_time_series_model(model_type, params)
        result = MetricaBase.fit(model, data)
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
