# Metrica 守护进程共享模块
# 提取各入口脚本共用的工具函数，避免代码重复。
module MetricaDaemon

export sanitize_json_floats, runtime_fit_envelope

"""
    sanitize_json_floats(x)

将非有限浮点数（Inf/NaN）替换为 `nothing`，满足 JSON 规范。
JSON3 默认拒绝序列化 Inf/NaN，此函数确保数据可安全序列化。
"""
sanitize_json_floats(x::AbstractFloat) = isfinite(x) ? x : nothing
sanitize_json_floats(x::Integer) = x
sanitize_json_floats(x::Bool) = x
sanitize_json_floats(x::AbstractString) = x
sanitize_json_floats(::Nothing) = nothing
sanitize_json_floats(x::AbstractDict) = Dict(k => sanitize_json_floats(v) for (k, v) in pairs(x))
sanitize_json_floats(x::AbstractVector) = map(sanitize_json_floats, x)
sanitize_json_floats(x) = x

"""
    runtime_fit_envelope(result_payload::AbstractDict)

将拟合结果字典包装为 Runtime / 守护进程统一的顶层 JSON 形状。
"""
function runtime_fit_envelope(result_payload::AbstractDict)
    Dict{String, Any}(
        "status" => "success",
        "messages" => Any[],
        "result_payload" => result_payload,
        "artifacts" => Any[],
    )
end

end # module MetricaDaemon
