# === 稀疏空间权重：边表读入与行标准化（稠密矩阵，n ≤ 5000）===================

"""解析 `spatial_weights_path`：相对路径相对 `working_dir`。"""
function resolve_weights_path(weights_path::AbstractString, working_dir::AbstractString)::String
    p = strip(weights_path)
    isempty(p) && return p
    if isabspath(p)
        return p
    end
    base = strip(working_dir)
    isempty(base) && return abspath(p)
    return abspath(joinpath(base, p))
end

"""读取边表 CSV，校验列名 `id_i`、`id_j`、`w`。"""
function read_edges_csv(path::AbstractString)::Union{DataFrame, MetricaBase.ModelError}
    try
        df = CSV.read(path, DataFrame)
        cols = names(df)
        has_i = "id_i" in cols
        has_j = "id_j" in cols
        has_w = "w" in cols
        if !(has_i && has_j && has_w)
            return MetricaBase.ModelError(
                :spatial_weights_schema,
                "空间权重文件列名无效",
                "边表 CSV 必须包含列：id_i、id_j、w。",
                "请按 runtime-protocol 中 S5.7 边表格式导出。",
            )
        end
        return df
    catch err
        return MetricaBase.ModelError(
            :spatial_weights_read_failed,
            "无法读取空间权重文件",
            string(err),
            "请检查 spatial_weights_path 与文件编码。",
        )
    end
end

"""将边表聚合为稠密 `W`（行/列顺序为 `ids`）。"""
function edges_to_weight_matrix(
    edges::DataFrame,
    ids::Vector{String};
    row_standardize::Bool,
)::Union{Tuple{Matrix{Float64}, Dict{Symbol, Any}}, MetricaBase.ModelError}
    id_to_idx = Dict{String, Int}(id => i for (i, id) in enumerate(ids))
    n = length(ids)
    W = zeros(Float64, n, n)
    for r in eachrow(edges)
        si = string(r.id_i)::String
        sj = string(r.id_j)::String
        wi = try
            Float64(r.w)
        catch
            return MetricaBase.ModelError(
                :spatial_weights_nonnumeric,
                "空间权重非数值",
                "列 w 须为有限非负实数。",
                nothing,
            )
        end
        !isfinite(wi) &&
            return MetricaBase.ModelError(:spatial_weights_nonfinite, "空间权重无效", "w 须为有限数。", nothing)
        wi < 0 &&
            return MetricaBase.ModelError(:spatial_weights_negative, "空间权重为负", "w 不得为负数。", nothing)
        !haskey(id_to_idx, si) && continue
        !haskey(id_to_idx, sj) && continue
        i = id_to_idx[si]
        j = id_to_idx[sj]
        W[i, j] += wi
    end
    rep = Dict{Symbol, Any}(
        :nnz_stored => count(!iszero, W),
        :row_standardize_requested => row_standardize,
        :row_standardize_applied => false,
        :row_sums_min => nothing,
        :row_sums_max => nothing,
    )
    rowsum = vec(sum(W, dims=2))
    if row_standardize
        rep[:row_sums_min] = isempty(rowsum) ? nothing : minimum(rowsum)
        rep[:row_sums_max] = isempty(rowsum) ? nothing : maximum(rowsum)
        if any(<=(0.0), rowsum)
            return MetricaBase.ModelError(
                :spatial_isolated_unit,
                "存在孤立空间单元",
                "行标准化要求每个观测在权重图中行和为正；当前存在行和为 0 的单元。",
                "请检查边表是否覆盖全部观测 id，或暂时关闭 spatial_row_standardize。",
            )
        end
        for i in 1:n
            W[i, :] ./= rowsum[i]
        end
        rep[:row_standardize_applied] = true
        rep[:row_sums_min] = 1.0
        rep[:row_sums_max] = 1.0
    else
        if any(<=(0.0), rowsum)
            return MetricaBase.ModelError(
                :spatial_isolated_unit,
                "存在孤立空间单元",
                "权重矩阵中存在行和为 0 的观测（无边或权重全为 0）。",
                "请补全邻接或启用行标准化（若适用）。",
            )
        end
        rep[:row_sums_min] = minimum(rowsum)
        rep[:row_sums_max] = maximum(rowsum)
    end
    sym_hint = isapprox(W, W', atol=1e-6 * max(1.0, maximum(abs, W)))
    rep[:symmetry_hint] = sym_hint
    return (W, rep)
end
