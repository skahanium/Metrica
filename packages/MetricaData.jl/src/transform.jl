using DataFrames
using Statistics

const _ALLOWED_FUNCTIONS = Dict{Symbol, Function}(
    :log => log,
    :exp => exp,
    :sqrt => sqrt,
    :abs => abs,
)

function _eval_row_expr(expr, row)
    if expr isa Number || expr isa AbstractString || expr isa Bool
        return expr
    elseif expr isa QuoteNode
        return expr.value
    elseif expr isa Symbol
        if haskey(row, expr)
            return row[expr]
        end
        haskey(_ALLOWED_FUNCTIONS, expr) && return _ALLOWED_FUNCTIONS[expr]
        error("表达式引用了未知变量或函数：$(expr)")
    elseif expr isa Expr && expr.head == :call
        op = expr.args[1]
        args = [_eval_row_expr(arg, row) for arg in expr.args[2:end]]
        if op == :+
            return +(args...)
        elseif op == :-
            return length(args) == 1 ? -args[1] : -(args...)
        elseif op == :*
            return *(args...)
        elseif op == :/
            return /(args...)
        elseif op == :^
            return ^(args...)
        elseif op == :>
            return >(args...)
        elseif op == :>=
            return >=(args...)
        elseif op == :<
            return <(args...)
        elseif op == :<=
            return <=(args...)
        elseif op == :(==)
            return ==(args...)
        elseif op == :(!=)
            return !=(args...)
        elseif op == :&
            return all(args)
        elseif op == :|
            return any(args)
        elseif haskey(_ALLOWED_FUNCTIONS, op)
            return _ALLOWED_FUNCTIONS[op](args...)
        end
    end
    error("暂不支持的数据表达式：$(expr)")
end

struct OpResult
    operation::String
    status::String          # "ok" | "error"
    df::DataFrame
    notes::String
    warnings::Vector{Dict{String, Any}}
    error::Union{Nothing, Dict{String, Any}}
end

function OpResult(operation::String, df::DataFrame; notes::String = "", warnings::Vector{Dict{String, Any}} = Dict{String, Any}[])
    return OpResult(operation, "ok", df, notes, warnings, nothing)
end

function OpResult(operation::String, ::Nothing; error::Dict{String, Any})
    return OpResult(operation, "error", DataFrame(), "", Dict{String, Any}[], error)
end

"""
    generate(df, name, expr)

创建新变量。`expr` 为字符串表达式，使用列名作为变量。
"""
function generate(df::DataFrame, name::String, expr::String)
    df2 = copy(df)
    parsed = Meta.parse(expr)
    df2[!, name] = [begin
        row = NamedTuple{tuple(Symbol.(names(df2))...)}(Tuple(r))
        _eval_row_expr(parsed, row)
    end for r in eachrow(df2)]
    return OpResult("generate", df2, notes = "已创建变量 '$name' = $expr")
end

"""
    replace(df, col, condition, value_expr)

对满足条件的行替换列值。`condition` 和 `value_expr` 为字符串表达式。
"""
function replace(df::DataFrame, col::String, condition::String, value_expr::String)
    df2 = copy(df)
    parsed_condition = Meta.parse(condition)
    parsed_value = Meta.parse(value_expr)
    for (row_index, r) in enumerate(eachrow(df2))
        row = NamedTuple{tuple(Symbol.(names(df2))...)}(Tuple(r))
        if _eval_row_expr(parsed_condition, row)
            df2[row_index, Symbol(col)] = _eval_row_expr(parsed_value, row)
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

function _mode_value(values)
    counts = Dict{Any, Int}()
    for value in values
        counts[value] = get(counts, value, 0) + 1
    end
    ordered = Base.sort(collect(counts); by = item -> (-item[2], string(item[1])))
    return first(first(ordered))
end

function _impute_strategy(values)
    if all(value -> value isa Bool, values)
        return "众数", _mode_value(values)
    elseif all(value -> value isa AbstractFloat, values)
        return "均值", mean(Float64.(values))
    elseif all(value -> value isa Integer, values)
        return "中位数", median(Float64.(values))
    elseif all(value -> value isa Number, values)
        return "中位数", median(Float64.(values))
    else
        return "众数", _mode_value(values)
    end
end

function _typed_imputed_column(col, fill_value)
    T = Union{Missing, typeof(fill_value)}
    result = Vector{T}(undef, length(col))
    for (i, value) in pairs(col)
        result[i] = ismissing(value) ? fill_value : convert(typeof(fill_value), value)
    end
    return result
end

"""
    impute_missing(df)

对含缺失值的列执行自动插补：

- 浮点连续列：均值
- 整数 / 离散数值列：中位数
- 字符串 / 布尔 / 分类列：众数
"""
function impute_missing(df::DataFrame)
    df2 = copy(df)
    applied = String[]
    warnings = Dict{String, Any}[]

    for name in names(df2)
        col = df2[!, name]
        missing_count = count(ismissing, col)
        missing_count == 0 && continue

        observed = collect(skipmissing(col))
        if isempty(observed)
            push!(warnings, Dict(
                "title" => "列已跳过",
                "detail" => "列 `$(name)` 全部为缺失值，无法自动插补。",
            ))
            continue
        end

        strategy, fill_value = _impute_strategy(observed)
        df2[!, name] = _typed_imputed_column(col, fill_value)
        push!(applied, "$(name)=$(strategy)")
    end

    notes = if isempty(applied)
        "未发现需要插补的列。"
    else
        "已自动插补缺失值：" * join(applied, "；")
    end

    return OpResult("impute_missing", df2; notes, warnings)
end
