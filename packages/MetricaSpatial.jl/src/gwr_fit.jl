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
            beta_i = Xw \ yw
            local_beta[i, :] = beta_i
            fitted[i] = dot(X[i, :], beta_i)
            H_i = dot(X[i, :], (Xw' * Xw) \ X[i, :]) * w[i]
            hat_diag[i] = max(H_i, 0.0)
            tss_i = sum(w[j] * (y[j] - mean(y))^2 for j in 1:n)
            rss_i = sum(w[j] * (y[j] - dot(X[j, :], beta_i))^2 for j in 1:n)
            local_r2[i] = tss_i > 0 ? 1.0 - rss_i / tss_i : 0.0
        catch
            local_beta[i, :] .= 0.0
            fitted[i] = 0.0
            hat_diag[i] = 0.0
            local_r2[i] = 0.0
        end
    end

    residuals = y - fitted
    sigma2 = dot(residuals, residuals) / (n - 2 * sum(hat_diag) + sum(hat_diag.^2))
    sigma2 = max(sigma2, 1e-18)
    eff_params = sum(hat_diag)
    denom = max(n - eff_params - 2, 1)
    aicc = n * log(sigma2) + n * log(2π) + n * (n + eff_params) / denom

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

    return GWRFitResult("gwr", n, p, coef_names, local_beta, nothing, nothing,
                         local_r2, fitted, residuals, h, bw_method, bw_score,
                         kernel, adaptive, String(distance_metric),
                         eff_params, sigma2, aicc, hat_diag, diag, warnings)
end
