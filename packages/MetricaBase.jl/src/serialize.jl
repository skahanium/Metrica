# === 共享序列化辅助 ============================================================
#
# 所有 S5 包的 `result_to_payload` 均可复用此文件中的函数，
# 避免每个包重复编写相同的字典转换逻辑。

"""
    将 `Severity` 枚举转为小写字符串，供 JSON 序列化。
"""
function severity_to_string(severity::Severity)
    return String(Symbol(severity))
end

"""
    将 `ModelWarning` 转为 Dict，供 JSON 序列化。
"""
function warning_to_dict(warning::ModelWarning)
    return Dict{String, Any}(
        "code" => String(warning.code),
        "title" => warning.title,
        "detail" => warning.detail,
        "hint" => warning.hint,
        "severity" => severity_to_string(warning.severity),
    )
end

"""
    将 `ModelError` 转为 JSON 错误响应信封。
"""
function error_to_payload(err::ModelError)
    return Dict{String, Any}(
        "status" => "error",
        "messages" => [
            Dict{String, Any}(
                "level" => "error",
                "code" => String(err.code),
                "text" => err.detail,
                "hint" => err.hint,
            ),
        ],
    )
end

"""
    将 `ModelCapabilities` 转为 JSON-ready Dict。
"""
function capabilities_to_dict(caps::ModelCapabilities)
    return Dict{String, Any}(
        "status" => String(caps.status),
        "model_family" => String(caps.model_family),
        "supported_models" => [String(x) for x in caps.supported_models],
        "estimators" => caps.estimators,
        "diagnostics_available" => [String(x) for x in caps.diagnostics_available],
        "diagnostics_unavailable" => [String(x) for x in caps.diagnostics_unavailable],
        "effects_available" => [String(x) for x in caps.effects_available],
        "prediction_available" => caps.prediction_available,
        "limitations" => caps.limitations,
    )
end

"""
    递归将 `Dict{Symbol, Any}` 转为 `Dict{String, Any}`，供 JSON 序列化。
    支持嵌套 Dict 和 `nothing` 值。
"""
function dict_symbol_to_string(d::Dict{Symbol, Any})
    out = Dict{String, Any}()
    for (k, v) in d
        if v isa Symbol
            out[String(k)] = String(v)
        elseif v === nothing
            out[String(k)] = nothing
        elseif v isa Dict{Symbol, Any}
            out[String(k)] = dict_symbol_to_string(v)
        elseif v isa Dict
            out[String(k)] = v  # already string-keyed or mixed
        else
            out[String(k)] = v
        end
    end
    return out
end

"""
    标准化 glance 信封，供 `result_to_payload` 使用。
    返回 `(glance_dict, warnings_array)`。
"""
function build_glance_envelope(glance_table::ModelGlance)
    warnings = [warning_to_dict(w) for w in glance_table.warnings]
    glance_dict = Dict{String, Any}(
        "model" => String(glance_table.model),
        "nobs" => glance_table.nobs,
        "dof" => glance_table.dof,
        "metrics" => Dict{String, Any}(String(k) => v for (k, v) in glance_table.metrics),
        "warnings" => warnings,
    )
    return glance_dict, warnings
end

"""
    标准化 tidy 行序列化。
"""
function build_tidy_rows(tidy_table::TidyTable)
    return [
        let se = r.stderror
            se2 = (se === nothing || (se isa Float64 && isnan(se))) ? nothing : se
            Dict{String, Any}(
                "name" => String(r.name),
                "estimate" => r.estimate,
                "stderror" => se2,
                "statistic" => r.statistic,
                "pvalue" => r.pvalue,
                "ci_lower" => r.ci_lower,
                "ci_upper" => r.ci_upper,
            )
        end
        for r in tidy_table.rows
    ]
end

"""
    标准化 messages 序列化：从 glance warnings 生成 messages 数组。
"""
function build_messages(glance_table::ModelGlance)
    return [
        Dict{String, Any}(
            "level" => severity_to_string(w.severity),
            "code" => String(w.code),
            "text" => w.detail,
            "hint" => w.hint,
        )
        for w in glance_table.warnings
    ]
end

"""
    标准化 augment_status，描述增广数据的可用性。
"""
function build_augment_status(result; available::Bool=true, columns_available::Vector{String}=String[], columns_unavailable::Vector{String}=String[], preview_included::Bool=false, preview_rows::Int=0)
    return Dict{String, Any}(
        "available" => available,
        "columns_available" => columns_available,
        "columns_unavailable" => columns_unavailable,
        "preview_included" => preview_included,
        "preview_rows" => preview_rows,
    )
end

"""
    构建标准 augment_preview 行（列式转行式，限制行数）。
"""
function build_augment_preview(augment_table::AugmentTable; max_rows::Int=100)
    n = min(max_rows, augment_table.nobs)
    return [
        Dict{String, Any}(String(k) => v[i] for (k, v) in augment_table.columns)
        for i in 1:n
    ]
end

"""
    为已实现 `glance`/`tidy` 但尚未实现 `model_capabilities` 的结果
    返回 `nothing`，供 `result_to_payload` 判断是否需要输出能力声明。
"""
function try_capabilities(result)
    caps = model_capabilities(result)
    if caps !== nothing
        return capabilities_to_dict(caps)
    end
    return nothing
end
