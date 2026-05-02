using DataFrames

"""
    reshape_long(df, id_cols, time_col, stub_cols)

宽 → 长转换。以 `id_cols` 为标识，`stub_cols` 为 stub 列表，
生成 `time_col`（取值来自原宽列名后缀）和 `value` 列。
"""
function reshape_long(df::DataFrame, id_cols::Vector{Symbol}, time_col::String, stub_cols::Vector{String})
    id_names = String.(id_cols)
    all_stub_cols = String[]
    for stub in stub_cols
        pattern = Regex("^$(stub)_(.+)")
        for col_name in names(df)
            m = match(pattern, String(col_name))
            if m !== nothing
                push!(all_stub_cols, String(col_name))
            end
        end
    end
    df2 = stack(df, Symbol.(all_stub_cols), Symbol.(id_names),
        variable_name = Symbol(time_col), value_name = :_value)

    result = df2
    if length(stub_cols) == 1
        rename!(result, :_value => Symbol(stub_cols[1]))
    end

    notes = "reshape long: $(nrow(df)) → $(nrow(result)) 行"
    return OpResult("reshape_long", result, notes = notes)
end

"""
    reshape_wide(df, id_cols, time_col, value_cols)

长 → 宽转换。
"""
function reshape_wide(df::DataFrame, id_cols::Vector{Symbol}, time_col::Symbol, value_cols::Vector{Symbol})
    value_col = value_cols[1]
    result = unstack(df, id_cols, time_col, value_col)
    rename_map = Pair{Symbol, Symbol}[]
    for col in names(result)
        col_sym = Symbol(col)
        col_sym in id_cols && continue
        push!(rename_map, col_sym => Symbol("$(value_col)_$(col)"))
    end
    rename!(result, rename_map...)
    notes = "reshape wide: $(nrow(df)) → $(nrow(result)) 行"
    return OpResult("reshape_wide", result, notes = notes)
end
