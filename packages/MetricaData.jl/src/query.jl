using CSV
using Statistics

"""
    query_error(code, text; hint=nothing)

构造数据查看命令使用的结构化错误载荷。
"""
function query_error(code::AbstractString, text::AbstractString; hint::Union{Nothing, AbstractString}=nothing)
    message = Dict{String, Any}(
        "level" => "error",
        "code" => String(code),
        "text" => String(text),
    )
    if hint !== nothing
        message["hint"] = String(hint)
    end
    return Dict(
        "status" => "error",
        "messages" => Any[message],
    )
end

"""
    query_success(payload; messages=Any[])

构造数据查看命令使用的结构化成功载荷。
"""
function query_success(payload::Dict{String, Any}; messages::Vector{Any}=Any[])
    return Dict(
        "status" => "success",
        "messages" => messages,
        "result_payload" => payload,
    )
end

"""
    read_dataset(path)

读取 CSV 数据集；失败时返回结构化错误载荷。
"""
function read_dataset(path::AbstractString)
    if !isfile(path)
        return query_error(
            "dataset_not_found",
            "数据文件不存在：$(path)",
            hint = "请确认 CSV 路径后重试。",
        )
    end

    try
        return CSV.read(path, DataFrame; missingstring = "")
    catch err
        return query_error(
            "csv_parse_failed",
            "CSV 解析失败：$(sprint(showerror, err))",
            hint = "请检查分隔符、表头与编码是否正确。",
        )
    end
end

"""
    normalize_preview_value(value)

将预览中的 `missing` 统一序列化为 `nothing`。
"""
function normalize_preview_value(value)
    return ismissing(value) ? nothing : value
end

"""
    inferred_type_label(column)

返回列当前推断出的存储类型标签。
"""
function inferred_type_label(column)
    return string(eltype(column))
end

"""
    dataset_summary_dict(dataset)

返回统一的数据集规模摘要。
"""
function dataset_summary_dict(dataset::DataFrame)
    return Dict(
        "row_count" => nrow(dataset),
        "column_count" => ncol(dataset),
    )
end

"""
    column_summary_dict(dataset, name)

返回单个变量的结构化摘要。
"""
function column_summary_dict(dataset::DataFrame, name::AbstractString)
    column = dataset[!, Symbol(name)]
    missing_count = count(ismissing, column)
    return Dict(
        "name" => String(name),
        "inferred_type" => inferred_type_label(column),
        "missing_count" => missing_count,
        "non_missing_count" => nrow(dataset) - missing_count,
    )
end

"""
    columns_summary(dataset; variables=nothing)

返回指定变量列表的结构化摘要；若未指定则返回全部变量。
"""
function columns_summary(dataset::DataFrame; variables::Union{Nothing, Vector{String}}=nothing)
    selected = isnothing(variables) ? String.(names(dataset)) : variables
    return [column_summary_dict(dataset, name) for name in selected]
end

"""
    preview_rows(dataset; limit=5, variables=nothing)

返回预览行；可按变量子集裁剪列。
"""
function preview_rows(dataset::DataFrame; limit::Int=5, variables::Union{Nothing, Vector{String}}=nothing)
    preview = first(dataset, min(limit, nrow(dataset)))
    selected = isnothing(variables) ? String.(names(preview)) : variables

    return [
        Dict(
            name => normalize_preview_value(row[Symbol(name)])
            for name in selected
        )
        for row in eachrow(preview)
    ]
end

"""
    validate_variables(dataset, variables)

校验变量是否存在；返回 `nothing` 表示成功，否则返回错误载荷。
"""
function validate_variables(dataset::DataFrame, variables::Vector{String})
    existing = Set(String.(names(dataset)))
    missing_vars = [name for name in variables if !(name in existing)]
    if !isempty(missing_vars)
        return query_error(
            "unknown_variable",
            "变量不存在：$(join(missing_vars, ", "))",
            hint = "请检查变量拼写或先运行 describe。",
        )
    end
    return nothing
end

"""
    select_variables(dataset, variables)

返回查询应使用的变量列表，并执行存在性校验。
"""
function select_variables(dataset::DataFrame, variables::Union{Nothing, Vector{String}})
    selected = isnothing(variables) || isempty(variables) ? String.(names(dataset)) : variables
    validation = validate_variables(dataset, selected)
    if validation !== nothing
        return validation
    end
    return selected
end

"""
    inspect_dataset(path; preview_limit=5)

返回数据集基础摘要与预览行，供 `use` 与全屏浏览复用。
"""
function inspect_dataset(path::AbstractString; preview_limit::Integer=5)
    dataset = read_dataset(path)
    dataset isa DataFrame || return dataset

    return query_success(Dict(
        "dataset_summary" => dataset_summary_dict(dataset),
        "columns" => columns_summary(dataset),
        "preview_rows" => preview_rows(dataset; limit = Int(preview_limit)),
        "warnings" => Any[],
    ))
end

"""
    describe_dataset(path; variables=nothing)

返回变量清单与数据集规模。
"""
function describe_dataset(path::AbstractString; variables::Union{Nothing, Vector{String}}=nothing)
    dataset = read_dataset(path)
    dataset isa DataFrame || return dataset

    selected = select_variables(dataset, variables)
    selected isa Vector{String} || return selected

    return query_success(Dict(
        "kind" => "describe",
        "dataset_summary" => dataset_summary_dict(dataset),
        "variables" => columns_summary(dataset; variables = selected),
    ))
end

"""
    summarize_dataset(path; variables=nothing)

返回 Stata 风格默认描述性统计：Obs、Mean、Std. dev.、Min、Max。
"""
function summarize_dataset(path::AbstractString; variables::Union{Nothing, Vector{String}}=nothing)
    dataset = read_dataset(path)
    dataset isa DataFrame || return dataset

    selected = select_variables(dataset, variables)
    selected isa Vector{String} || return selected

    rows = Any[]
    for name in selected
        column = dataset[!, Symbol(name)]
        values = collect(skipmissing(column))
        obs = length(values)
        numeric_type = Base.nonmissingtype(eltype(column)) <: Number

        mean_value = nothing
        std_value = nothing
        min_value = nothing
        max_value = nothing

        if numeric_type && obs > 0
            numeric_values = Float64[v for v in values]
            mean_value = mean(numeric_values)
            std_value = obs > 1 ? std(numeric_values) : nothing
            min_value = minimum(numeric_values)
            max_value = maximum(numeric_values)
        end

        push!(rows, Dict(
            "name" => name,
            "inferred_type" => inferred_type_label(column),
            "obs" => obs,
            "mean" => mean_value,
            "std_dev" => std_value,
            "min" => min_value,
            "max" => max_value,
        ))
    end

    return query_success(Dict(
        "kind" => "summarize",
        "dataset_summary" => dataset_summary_dict(dataset),
        "variables" => rows,
    ))
end

"""
    tabulate_dataset(path; variable, max_levels=200)

返回单变量频数表；默认排除缺失值并提供累计百分比。
"""
function tabulate_dataset(path::AbstractString; variable::AbstractString, max_levels::Int=200)
    isempty(variable) && return query_error(
        "missing_variable",
        "tabulate 命令需要指定一个变量。",
        hint = "例如：tabulate group",
    )

    dataset = read_dataset(path)
    dataset isa DataFrame || return dataset

    validation = validate_variables(dataset, [String(variable)])
    validation === nothing || return validation

    column = dataset[!, Symbol(variable)]
    nonmissing_values = collect(skipmissing(column))
    total = length(nonmissing_values)
    missing_count = count(ismissing, column)

    unique_values = unique(nonmissing_values)
    sorted_values = try
        sort!(collect(unique_values))
    catch
        sort!(string.(unique_values))
    end

    warning_messages = Any[]
    truncated = false
    if length(sorted_values) > max_levels
        sorted_values = sorted_values[1:max_levels]
        truncated = true
        push!(warning_messages, Dict(
            "level" => "warning",
            "code" => "tabulate_truncated",
            "text" => "唯一值数量过多，仅显示前 $(max_levels) 个水平。",
            "hint" => "如需完整频数表，请后续扩展导出能力。",
        ))
    end

    rows = Any[]
    cumulative_pct = 0.0
    for value in sorted_values
        count_value = count(item -> isequal(item, value), nonmissing_values)
        pct_value = total == 0 ? 0.0 : count_value / total * 100
        cumulative_pct += pct_value
        push!(rows, Dict(
            "value" => string(value),
            "count" => count_value,
            "pct" => pct_value,
            "cum_pct" => cumulative_pct,
        ))
    end

    return query_success(
        Dict(
            "kind" => "tabulate",
            "dataset_summary" => dataset_summary_dict(dataset),
            "variable" => String(variable),
            "total" => total,
            "missing_count" => missing_count,
            "truncated" => truncated,
            "rows" => rows,
        );
        messages = warning_messages,
    )
end

"""
    browse_dataset(path; variables=nothing)

返回只读浏览配置，不伪造统计结果。
"""
function browse_dataset(path::AbstractString; variables::Union{Nothing, Vector{String}}=nothing)
    dataset = read_dataset(path)
    dataset isa DataFrame || return dataset

    selected = select_variables(dataset, variables)
    selected isa Vector{String} || return selected

    return query_success(Dict(
        "kind" => "browse",
        "readonly" => true,
        "dataset_summary" => dataset_summary_dict(dataset),
        "columns" => columns_summary(dataset; variables = selected),
    ))
end
