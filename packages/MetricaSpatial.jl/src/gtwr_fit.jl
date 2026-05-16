# gtwr_fit.jl — 地理时空加权回归 (Geographically and Temporally Weighted Regression)

function fit_gtwr(y::Vector{Float64}, X::Matrix{Float64}, coords::Matrix{Float64},
                  times::Vector{Float64};
                  kernel::String="gaussian",
                  bandwidth::Union{Nothing, Float64}=nothing,
                  bandwidth_selection::String="cv",
                  adaptive::Bool=false,
                  time_scale::Union{Nothing, Float64}=nothing,
                  distance_metric::Symbol=:euclidean)
    n = length(y)
    p = size(X, 2)

    t_min, t_max = minimum(times), maximum(times)
    t_range = t_max - t_min
    tau = if time_scale !== nothing
        time_scale
    else
        D_space = _distance_matrix(coords, distance_metric)
        mean_d_space = sum(D_space) / (n * (n - 1))
        mean_d_space / max(t_range, 1.0)
    end

    D_space = _distance_matrix(coords, distance_metric)
    D_time = Matrix{Float64}(undef, n, n)
    for i in 1:n
        for j in 1:n
            D_time[i, j] = abs(times[i] - times[j])
        end
    end
    D_st = sqrt.(D_space.^2 .+ tau^2 .* D_time.^2)

    kernel_fn = kernel == "bisquare" ? bisquare_kernel : gaussian_kernel
    h = if bandwidth !== nothing
        bandwidth
    else
        sum(D_st) / (n * (n - 1))
    end

    hs = adaptive ? _adaptive_bandwidths(D_st, round(Int, h)) : fill(h, n)
    coef_names = [Symbol("beta_$i") for i in 0:(p-1)]
    local_beta = Matrix{Float64}(undef, n, p)
    fitted = Vector{Float64}(undef, n)
    hat_diag = Vector{Float64}(undef, n)
    local_r2 = Vector{Float64}(undef, n)

    for i in 1:n
        w = [kernel_fn(D_st[i, j], hs[i]) for j in 1:n]
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
    sigma2 = dot(residuals, residuals) / max(n - 2 * sum(hat_diag) + sum(hat_diag.^2), 1)
    sigma2 = max(sigma2, 1e-18)
    eff_params = sum(hat_diag)
    aicc = n * log(sigma2) + n * log(2π) + n * (n + eff_params) / max(n - eff_params - 2, 1)

    st_summary = Dict{Symbol, Any}(
        :n_unique_spatial => length(Set(eachrow(coords))),
        :n_unique_temporal => length(Set(times)),
        :t_min => t_min,
        :t_max => t_max,
    )

    diag = Dict{Symbol, Any}(
        :bandwidth => h,
        :bandwidth_selection => bandwidth_selection,
        :kernel => kernel,
        :adaptive => adaptive,
        :distance_metric => String(distance_metric),
        :time_scale => tau,
        :effective_parameters => eff_params,
        :aicc => aicc,
        :spatiotemporal_distance_summary => st_summary,
    )

    return GTWRFitResult("gtwr", n, p, coef_names, local_beta, nothing, nothing,
                         local_r2, fitted, residuals, h, bandwidth_selection, NaN,
                         kernel, adaptive, String(distance_metric), tau, "time",
                         [t_min, t_max], st_summary,
                         eff_params, sigma2, aicc, hat_diag, diag,
                         MetricaBase.ModelWarning[])
end
