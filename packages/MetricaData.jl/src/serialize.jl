using DataFrames, CSV

"""
将 OpResult 序列化为 Dict（Runtime 可直接序列化为 JSON）。
"""
function result_to_dict(result::OpResult)
    d = Dict{String, Any}(
        "operation" => result.operation,
        "status" => result.status,
    )
    if result.status == "ok"
        d["result"] = Dict(
            "nrows" => nrow(result.df),
            "ncols" => ncol(result.df),
            "notes" => result.notes,
        )
        preview_n = min(10, nrow(result.df))
        d["preview"] = Dict(
            "columns" => String.(names(result.df)),
            "rows" => [Dict(String.(names(result.df)) .=> collect(r)) for r in eachrow(first(result.df, preview_n))],
        )
    else
        d["error"] = result.error
    end
    d["warnings"] = []
    return d
end

"""
    operate(df, op::Dict)

根据字典描述执行单个数据操作。返回 OpResult。
"""
function operate(df::DataFrame, op::Dict{String, Any})
    op_type = op["op"]::String
    args = op["args"]::Dict{String, Any}

    if op_type == "filter"
        return MetricaData.filter(df, args["condition"]::String)
    elseif op_type == "generate"
        return generate(df, args["name"]::String, args["expr"]::String)
    elseif op_type == "replace"
        return replace(df, args["col"]::String, args["condition"]::String, args["value"]::String)
    elseif op_type == "rename"
        mapping = Dict{String, String}(k => v for (k, v) in args["mapping"])
        return rename(df, mapping)
    elseif op_type == "drop"
        return drop(df, Symbol.(args["cols"]))
    elseif op_type == "keep"
        return keep(df, Symbol.(args["cols"]))
    elseif op_type == "sort"
        return MetricaData.sort(df, Symbol.(args["cols"]))
    elseif op_type == "merge"
        right_path = args["with"]::String
        right = CSV.read(right_path, DataFrame)
        on = args["on"]
        how = get(args, "how", "inner")
        return MetricaData.merge(df, right, on isa Vector ? String.(on) : [String(on)], String(how))
    elseif op_type == "reshape_long"
        return reshape_long(df, Symbol.(args["id_cols"]), args["time_col"]::String, String.(args["stub_cols"]))
    elseif op_type == "reshape_wide"
        return reshape_wide(df, Symbol.(args["id_cols"]), Symbol(args["time_col"]), Symbol.(args["value_cols"]))
    elseif op_type == "collapse"
        return collapse(df, Symbol.(args["by"]), String.(args["stats"]), Symbol.(args["value_cols"]))
    else
        return OpResult(op_type, nothing, error = Dict("message" => "Unknown operation: $op_type"))
    end
end

"""
    operate_chain(df, operations::Vector{Dict})

顺序执行多个操作。任一操作失败则停止并返回错误。
"""
function operate_chain(df::DataFrame, operations::Vector{Dict{String, Any}})
    results = Dict{String, Any}[]
    current_df = df
    for (i, op) in enumerate(operations)
        result = operate(current_df, op)
        if result.status == "error"
            result_dict = result_to_dict(result)
            result_dict["error"] = Dict("op_index" => i, "message" => get(result.error, "message", "Unknown error"))
            result_dict["status"] = "error"
            return result_dict
        end
        push!(results, result_to_dict(result))
        current_df = result.df
    end
    final = copy(last(results))
    final["operations"] = results
    return final
end
