using DataFrames, CSV

"""
将 OpResult 序列化为 Dict（Runtime 可直接序列化为 JSON）。
"""
function result_to_dict(result::OpResult; preview_rows::Int = 10)
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
        preview_n = min(preview_rows, nrow(result.df))
        d["preview"] = Dict(
            "columns" => String.(names(result.df)),
            "rows" => [Dict(String.(names(result.df)) .=> collect(r)) for r in eachrow(first(result.df, preview_n))],
        )
    else
        d["error"] = result.error
    end
    d["warnings"] = result.warnings
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
    elseif op_type == "impute_missing"
        return impute_missing(df)
    else
        return OpResult(op_type, nothing, error = Dict{String, Any}("message" => "Unknown operation: $op_type"))
    end
end

"""
    operate_chain(df, operations::Vector{Dict}; output_path = nothing, preview_rows = 10)

顺序执行多个操作。任一操作失败则停止并返回错误。
"""
function operate_chain(
    df::DataFrame,
    operations::Vector{Dict{String, Any}};
    output_path::Union{Nothing, AbstractString} = nothing,
    preview_rows::Int = 10,
)
    results = Dict{String, Any}[]
    current_df = df

    if isempty(operations)
        result = result_to_dict(OpResult("noop", current_df; notes = "未执行数据操作。"); preview_rows)
        if output_path !== nothing
            CSV.write(output_path, current_df)
            result["result"]["dataset_path"] = String(output_path)
        end
        result["operations"] = results
        return result
    end

    for (i, op) in enumerate(operations)
        result = try
            operate(current_df, op)
        catch err
            OpResult(
                get(op, "op", "unknown"),
                nothing;
                error = Dict(
                    "op_index" => i,
                    "message" => sprint(showerror, err),
                ),
            )
        end
        if result.status == "error"
            result_dict = result_to_dict(result; preview_rows)
            result_dict["error"] = Dict(
                "op_index" => i,
                "message" => get(result.error, "message", "Unknown error"),
            )
            result_dict["status"] = "error"
            result_dict["operations"] = results
            return result_dict
        end
        push!(results, result_to_dict(result; preview_rows))
        current_df = result.df
    end
    final = copy(last(results))
    if output_path !== nothing
        CSV.write(output_path, current_df)
        final["result"]["dataset_path"] = String(output_path)
    end
    final["operations"] = results
    return final
end
