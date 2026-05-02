using DataFrames

struct OpResult
    operation::String
    status::String          # "ok" | "error"
    df::DataFrame
    notes::String
    error::Union{Nothing, Dict{String, Any}}
end

function OpResult(operation::String, df::DataFrame; notes::String = "")
    return OpResult(operation, "ok", df, notes, nothing)
end

function OpResult(operation::String, ::Nothing; error::Dict{String, Any})
    return OpResult(operation, "error", DataFrame(), "", error)
end

"""
    generate(df, name, expr)

创建新变量。`expr` 为字符串表达式，使用列名作为变量。
"""
function generate(df::DataFrame, name::String, expr::String)
    df2 = copy(df)
    df2[!, name] = [begin
        row = NamedTuple{tuple(Symbol.(names(df2))...)}(Tuple(r))
        eval(Meta.parse(expr))
    end for r in eachrow(df2)]
    return OpResult("generate", df2, notes = "已创建变量 '$name' = $expr")
end

"""
    replace(df, col, condition, value_expr)

对满足条件的行替换列值。`condition` 和 `value_expr` 为字符串表达式。
"""
function replace(df::DataFrame, col::String, condition::String, value_expr::String)
    df2 = copy(df)
    for r in eachrow(df2)
        row = NamedTuple{tuple(Symbol.(names(df2))...)}(Tuple(r))
        if eval(Meta.parse(condition))
            df2[r, Symbol(col)] = eval(Meta.parse(value_expr))
        end
    end
    return OpResult("replace", df2, notes = "已按条件 $condition 替换 '$col'")
end

"""
    rename(df, mapping)

重命名列。`mapping` 为 Dict(old => new)。
"""
function rename(df::DataFrame, mapping::Dict{String, String})
    df2 = copy(df)
    new_names = [get(mapping, String(n), String(n)) for n in names(df2)]
    rename!(df2, Symbol.(new_names))
    return OpResult("rename", df2, notes = "已重命名 $(length(mapping)) 列")
end

"""
    drop(df, cols)

删除指定列。
"""
function drop(df::DataFrame, cols::Vector{Symbol})
    df2 = df[:, Not(cols)]
    return OpResult("drop", df2, notes = "已删除 $(length(cols)) 列")
end

"""
    keep(df, cols)

保留指定列。
"""
function keep(df::DataFrame, cols::Vector{Symbol})
    df2 = df[:, cols]
    return OpResult("keep", df2, notes = "已保留 $(length(cols)) 列")
end
