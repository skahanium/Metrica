# gwr_fit.jl — 地理加权回归 (Geographically Weighted Regression)

function gaussian_kernel(d::Float64, h::Float64)
    return exp(-0.5 * (d / h)^2)
end

function bisquare_kernel(d::Float64, h::Float64)
    return d < h ? (1.0 - (d / h)^2)^2 : 0.0
end

function _distance_matrix(coords::Matrix{Float64}, metric::Symbol)
    n = size(coords, 1)
    D = Matrix{Float64}(undef, n, n)
    dist_fn = metric == :haversine ? haversine_distance : euclidean_distance
    for i in 1:n
        for j in 1:n
            D[i, j] = i == j ? 0.0 : dist_fn(coords[i, 1], coords[i, 2], coords[j, 1], coords[j, 2])
        end
    end
    return D
end

function _adaptive_bandwidths(D::Matrix{Float64}, k::Int)
    n = size(D, 1)
    h = Vector{Float64}(undef, n)
    for i in 1:n
        sorted = sort(D[i, :])
        h[i] = sorted[min(k + 1, n)]
    end
    return h
end

function _gwr_cv_score(y::Vector{Float64}, X::Matrix{Float64}, D::Matrix{Float64},
                        h::Union{Float64, Vector{Float64}}, kernel_fn::Function)
    n = length(y)
    cv = 0.0
    for i in 1:n
        hi = h isa Float64 ? h : h[i]
        w = [kernel_fn(D[i, j], hi) for j in 1:n]
        w[i] = 0.0  # leave-one-out
        Wsqrt = sqrt.(max.(w, 1e-18))
        Xw = Wsqrt .* X
        yw = Wsqrt .* y
        try
            beta_i = Xw \ yw
            y_hat_i = dot(X[i, :], beta_i)
            cv += (y[i] - y_hat_i)^2
        catch
            cv += (y[i] - mean(y))^2  # fallback: null model
        end
    end
    return cv
end

function fit_gwr(y::Vector{Float64}, X::Matrix{Float64}, coords::Matrix{Float64};
                 kernel::String="gaussian",
                 bandwidth::Union{Nothing, Float64}=nothing,
                 bandwidth_selection::String="cv",
                 adaptive::Bool=false,
                 adaptive_k::Int=50,
                 distance_metric::Symbol=:euclidean)
    n = length(y)
    p = size(X, 2)
    n > 2000 && return MetricaBase.ModelError(:gwr_too_large,
        "GWR 当前限 n ≤ 2000", "n=$n", "请抽样或分区。")

    coef_names = [Symbol("beta_$i") for i in 0:(p-1)]

    D = _distance_matrix(coords, distance_metric)
    kernel_fn = kernel == "bisquare" ? bisquare_kernel : gaussian_kernel

    # 带宽选择
    if bandwidth !== nothing
        h = bandwidth
        bw_method = "fixed"
        bw_score = NaN
    elseif bandwidth_selection == "cv"
        if adaptive
            best_k = min(adaptive_k, n - 1)
            best_cv = _gwr_cv_score(y, X, D, _adaptive_bandwidths(D, best_k), kernel_fn)
            h = Float64(best_k)
            bw_method = "cv-adaptive"
            bw_score = best_cv
        else
            mean_d = sum(D) / (n * (n - 1))
            candidates = range(0.1 * mean_d, 2.0 * mean_d, length=20)
            best_h = candidates[1]
            best_cv = Inf
            for cand in candidates
                cv = _gwr_cv_score(y, X, D, Float64(cand), kernel_fn)
                if cv < best_cv
                    best_cv = cv
                    best_h = cand
                end
            end
            h = Float64(best_h)
            bw_method = "cv-fixed"
            bw_score = best_cv
        end
    else
        h = adaptive ? Float64(min(n - 1, 50)) : Float64(sum(D) / (n * (n - 1)))
        bw_method = "default"
        bw_score = NaN
    end

    # 局部 WLS
    local_beta = Matrix{Float64}(undef, n, p)
    local_se = Matrix{Float64}(undef, n, p)
    local_tval = Matrix{Float64}(undef, n, p)
    hat_diag = Vector{Float64}(undef, n)
    fitted = Vector{Float64}(undef, n)
    local_r2 = Vector{Float64}(undef, n)

    hs = adaptive ? _adaptive_bandwidths(D, round(Int, h)) : fill(h, n)

    for i in 1:n
        w = [kernel_fn(D[i, j], hs[i]) for j in 1:n]
        w[i] = max(w[i], 1e-18)
        Wsqrt = sqrt.(max.(w, 1e-18))
        Xw = Wsqrt .* X
        yw = Wsqrt .* y
        try
            XtX = Xw' * Xw
            XtX_inv = inv(Symmetric(XtX))
            beta_i = XtX_inv * (Xw' * yw)
            local_beta[i, :] = beta_i
            fitted[i] = dot(X[i, :], beta_i)
            H_i = dot(X[i, :], XtX_inv * X[i, :]) * w[i]
            hat_diag[i] = max(H_i, 0.0)
            tss_i = sum(w[j] * (y[j] - mean(y))^2 for j in 1:n)
            rss_i = sum(w[j] * (y[j] - dot(X[j, :], beta_i))^2 for j in 1:n)
            local_r2[i] = tss_i > 0 ? 1.0 - rss_i / tss_i : 0.0
            for k in 1:p
                local_se[i, k] = sqrt(max(XtX_inv[k, k], 0.0))
                local_tval[i, k] = local_se[i, k] > 1e-18 ? beta_i[k] / local_se[i, k] : 0.0
            end
        catch
            local_beta[i, :] .= NaN
            local_se[i, :] .= NaN
            local_tval[i, :] .= NaN
            fitted[i] = NaN
            hat_diag[i] = NaN
            local_r2[i] = NaN
        end
    end

    valid_rows = findall(isfinite.(fitted))
    n_valid = length(valid_rows)
    if n_valid == 0
        return MetricaBase.ModelError(:gwr_all_singular, "GWR 所有局部设计矩阵均奇异", "", "")
    end

    residuals = y - fitted
    sigma2 = dot(residuals[valid_rows], residuals[valid_rows]) / max(n_valid - 2 * sum(hat_diag[valid_rows]) + sum(hat_diag[valid_rows].^2), 1)
    sigma2 = max(sigma2, 1e-18)
    eff_params = sum(hat_diag[valid_rows])
    denom = max(n_valid - eff_params - 2, 1)
    aicc = n_valid * log(sigma2) + n_valid * log(2π) + n_valid * (n_valid + eff_params) / denom

    warnings = MetricaBase.ModelWarning[]
    if !adaptive && (h < 0.05 * mean(D))
        push!(warnings, MetricaBase.ModelWarning(:bandwidth_too_small,
            "带宽过小", "固定带宽 h=$h 可能过小，局部回归不稳定。",
            "建议增大 bandwidth 或使用 bandwidth_selection=cv。", MetricaBase.warning))
    end

    diag = Dict{Symbol, Any}(
        :bandwidth => h,
        :bandwidth_selection => bw_method,
        :bandwidth_score => bw_score,
        :kernel => kernel,
        :adaptive => adaptive,
        :distance_metric => String(distance_metric),
        :effective_parameters => eff_params,
        :aicc => aicc,
    )

    return GWRFitResult("gwr", n, p, coef_names, local_beta, local_se, local_tval,
                         local_r2, fitted, residuals, h, bw_method, bw_score,
                         kernel, adaptive, String(distance_metric),
                         eff_params, sigma2, aicc, hat_diag, diag, warnings)
end

function _gwr_design_table(df::DataFrame, formula::AbstractString, coord_columns::Vector{String})
    parsed = MetricaBase.parse_metrica_formula(formula)
    parsed isa MetricaBase.ModelError && return parsed
    yname, xnames = parsed
    coord_syms = Symbol.(coord_columns)
    needcols = unique(vcat([yname], xnames, coord_columns))
    missingcols = setdiff(needcols, names(df))
    !isempty(missingcols) &&
        return MetricaBase.ModelError(
            :gwr_missing_columns,
            "数据缺少列",
            join(missingcols, ", "),
            "请检查公式与 spatial_coord_columns。",
        )
    subcc = dropmissing(select(df, needcols))
    nrow(subcc) == 0 &&
        return MetricaBase.ModelError(:gwr_empty_sample, "有效样本为空", "complete cases 为 0。", "请检查缺失值。")
    n = nrow(subcc)
    y = Vector{Float64}(undef, n)
    X = zeros(Float64, n, 1 + length(xnames))
    coords = zeros(Float64, n, length(coord_syms))
    for (i, row) in enumerate(eachrow(subcc))
        y[i] = Float64(row[Symbol(yname)])
        X[i, 1] = 1.0
        for (j, xn) in enumerate(xnames)
            X[i, j + 1] = Float64(row[Symbol(xn)])
        end
        for (j, cs) in enumerate(coord_syms)
            coords[i, j] = Float64(row[cs])
        end
    end
    return (; y, X, coords)
end

"""
从 DataFrame 与规格字典拟合 GWR（Runtime 桥接入口）。
"""
function fit_gwr_model(formula::AbstractString, df::DataFrame, spec::AbstractDict)
    raw_coords = get(spec, "spatial_coord_columns", nothing)
    (raw_coords === nothing || isempty(raw_coords)) &&
        return MetricaBase.ModelError(
            :gwr_missing_coords,
            "缺少 spatial_coord_columns",
            "",
            "GWR/GTWR 须指定坐标列。",
        )
    coord_cols = String.(collect(raw_coords))
    design = _gwr_design_table(df, formula, coord_cols)
    design isa MetricaBase.ModelError && return design
    kernel = String(get(spec, "gwr_kernel", "gaussian"))
    bandwidth = if haskey(spec, "gwr_bandwidth") && spec["gwr_bandwidth"] !== nothing
        Float64(spec["gwr_bandwidth"])
    else
        nothing
    end
    return fit_gwr(design.y, design.X, design.coords; kernel=kernel, bandwidth=bandwidth)
end
