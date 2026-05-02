using DataFrames
using Statistics

"""
    filter(df, condition)

按条件筛选行。`condition` 为字符串表达式。
"""
function filter(df::DataFrame, condition::String)
    mask = [begin
        row = NamedTuple{tuple(Symbol.(names(df))...)}(Tuple(r))
        eval(Meta.parse(condition))
    end for r in eachrow(df)]
    df2 = df[mask, :]
    n_kept = nrow(df2)
    n_total = nrow(df)
    return OpResult("filter", df2, notes = "筛选条件: $condition，保留 $n_kept / $n_total 行")
end

"""
    sort(df, cols; rev = false)

按指定列排序。
"""
function sort(df::DataFrame, cols::Vector{Symbol}; rev::Bool = false)
    df2 = DataFrames.sort(df, cols; rev)
    return OpResult("sort", df2, notes = "已按 $(join(String.(cols), ", ")) 排序")
end

"""
    collapse(df, by, stats, value_cols)

分组聚合。`stats` 可包含 "mean", "sum", "sd", "min", "max", "count"。
"""
function collapse(df::DataFrame, by::Vector{Symbol}, stats::Vector{String}, value_cols::Vector{Symbol})
    gd = groupby(df, by)
    results = Dict{String, Any}()
    for col in value_cols
        for stat in stats
            name = "$col" * "_" * stat
            results[name] = if stat == "mean"
                combine(gd, col => mean => Symbol(name))
            elseif stat == "sum"
                combine(gd, col => sum => Symbol(name))
            elseif stat == "sd"
                combine(gd, col => std => Symbol(name))
            elseif stat == "min"
                combine(gd, col => minimum => Symbol(name))
            elseif stat == "max"
                combine(gd, col => maximum => Symbol(name))
            elseif stat == "count"
                combine(gd, col => length => Symbol(name))
            end
        end
    end
    df2 = results[first(keys(results))]
    for key in keys(results)
        if key != first(keys(results))
            df2 = innerjoin(df2, results[key], on = String.(by))
        end
    end
    return OpResult("collapse", df2, notes = "分组: $(join(String.(by), ", "))，统计: $(join(stats, ", "))")
end

"""
    operate(df, expr)

通用列运算。`expr` 为字符串表达式。
"""
function operate(df::DataFrame, expr::String) end

"""
    operate_chain(df, ops)

链式操作。`ops` 为操作字典列表。
"""
function operate_chain(df::DataFrame, ops::Vector{Dict{String, Any}}) end
