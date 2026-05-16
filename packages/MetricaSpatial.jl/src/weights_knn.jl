# weights_knn.jl — k 近邻空间权重构造

function euclidean_distance(x1::Float64, y1::Float64, x2::Float64, y2::Float64)
    return sqrt((x1 - x2)^2 + (y1 - y2)^2)
end

function haversine_distance(lon1::Float64, lat1::Float64, lon2::Float64, lat2::Float64)
    R = 6371.0  # km
    dlat = deg2rad(lat2 - lat1)
    dlon = deg2rad(lon2 - lon1)
    a = sin(dlat / 2)^2 + cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * sin(dlon / 2)^2
    c = 2 * atan(sqrt(a), sqrt(max(0.0, 1 - a)))
    return R * c
end

function build_knn_weights(coords::Matrix{Float64}, k::Int;
                           distance_metric::Symbol=:euclidean,
                           row_standardize::Bool=true)
    n = size(coords, 1)
    k = min(k, n - 1)
    k <= 0 && return MetricaBase.ModelError(:knn_invalid_k, "k 必须 >= 1", "k = $k", "")

    dist_fn = distance_metric == :haversine ? haversine_distance : euclidean_distance

    # 全对距离矩阵
    D = Matrix{Float64}(undef, n, n)
    for i in 1:n
        for j in 1:n
            D[i, j] = i == j ? Inf : dist_fn(coords[i, 1], coords[i, 2], coords[j, 1], coords[j, 2])
        end
    end

    # 每行找 k 个最近邻
    id_i = Int[]
    id_j = Int[]
    ws = Float64[]
    for i in 1:n
        order = sortperm(D[i, :])
        for jj in 1:k
            j = order[jj]
            push!(id_i, i)
            push!(id_j, j)
            push!(ws, 1.0)
        end
    end

    edges = DataFrame(id_i=id_i, id_j=id_j, w=ws)
    meta = Dict{Symbol, Any}(
        :method => "knn",
        :k => k,
        :distance_metric => String(distance_metric),
        :row_standardized => row_standardize,
    )
    return (edges, meta)
end
