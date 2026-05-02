using DataFrames

"""
    merge(left, right, on, how)

连接两个 DataFrame。`how` 支持 "inner"、"left"、"right"、"outer"。
"""
function merge(left::DataFrame, right::DataFrame, on::Vector{String}, how::String)
    on_sym = Symbol.(on)
    join_f = if how == "left"
        leftjoin
    elseif how == "right"
        rightjoin
    elseif how == "outer"
        outerjoin
    else
        innerjoin
    end
    df2 = join_f(left, right, on = on_sym)

    right_keys = Set(Tuple(row[col] for col in on_sym) for row in eachrow(right))
    matched = nrow(df2)
    unmatched_left = count(row -> !(Tuple(row[col] for col in on_sym) in right_keys), eachrow(left))
    notes = "$(how) join: $(matched) matched, $(unmatched_left) unmatched left"

    return OpResult("merge", df2, notes = notes)
end
