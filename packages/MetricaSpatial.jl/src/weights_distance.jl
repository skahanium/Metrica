# weights_distance.jl — distance-band 空间权重构造

function build_distance_band_weights(coords::Matrix{Float64}, threshold::Float64;
                                     distance_metric::Symbol=:euclidean,
                                     row_standardize::Bool=true)
    n = size(coords, 1)
    threshold <= 0 && return MetricaBase.ModelError(:invalid_threshold, "threshold 必须 > 0", "$threshold", "")

    dist_fn = distance_metric == :haversine ? haversine_distance : euclidean_distance

    id_i = Int[]
    id_j = Int[]
    ws = Float64[]
    for i in 1:n
        has_neighbor = false
        for j in 1:n
            i == j && continue
            d = dist_fn(coords[i, 1], coords[i, 2], coords[j, 1], coords[j, 2])
            if d <= threshold
                push!(id_i, i)
                push!(id_j, j)
                push!(ws, 1.0)
                has_neighbor = true
            end
        end
        has_neighbor || return MetricaBase.ModelError(
            :isolated_unit,
            "距离阈值下存在孤立单元",
            "单元 $i 无邻居",
            "增大 threshold 或检查坐标",
        )
    end

    edges = DataFrame(id_i=id_i, id_j=id_j, w=ws)
    meta = Dict{Symbol, Any}(
        :method => "distance_band",
        :threshold => threshold,
        :distance_metric => String(distance_metric),
        :row_standardized => row_standardize,
    )
    return (edges, meta)
end
