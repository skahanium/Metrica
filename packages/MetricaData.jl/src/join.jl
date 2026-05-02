using DataFrames

"""
    merge(left, right, on, how)

连接两个 DataFrame。`how` 支持 "inner"、"left"、"right"、"outer"。
"""
function merge(left::DataFrame, right::DataFrame, on::Vector{String}, how::String)
    on_sym = Symbol.(on)
    how_map = Dict(
        "inner" => :inner,
        "left"  => :left,
        "right" => :right,
        "outer" => :outer,
    )
    join_type = get(how_map, how, :inner)

    df2 = join(left, right, on = on_sym, kind = join_type)

    matched = nrow(df2)
    unmatched_left = sum(.\!(
        [any(r[on_sym] .== row[on_sym]) for r in eachrow(right)]
        for row in eachrow(left)
    ))
    notes = "$how join: $matched matched, $unmatched_left unmatched left"

    return OpResult("merge", df2, notes = notes)
end
