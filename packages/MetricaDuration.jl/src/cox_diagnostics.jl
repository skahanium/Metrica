# cox_diagnostics.jl — Schoenfeld 残差 + PH 检验 + baseline survival

function schoenfeld_residuals(beta::Vector{Float64}, X::Matrix{Float64},
                               t_ord::Vector{Float64}, e_ord::Vector{Int})
    n = length(t_ord); p = size(X, 2)
    events = findall(e_ord .== 1)
    n_events = length(events)
    r = Matrix{Float64}(undef, n_events, p)
    event_idx = 0
    for i in events
        tau = t_ord[i]
        ri = _first_risk_index(t_ord, tau)
        ri === nothing && continue
        risk_idx = ri:n
        Xr = X[risk_idx, :]; eta = Xr * beta; mx = maximum(eta)
        er = exp.(eta .- mx); denom = sum(er)
        denom <= 0 && continue
        x_bar = vec(sum(Xr .* er, dims=1)) ./ denom
        event_idx += 1
        r[event_idx, :] = X[i, :] .- x_bar
    end
    return r[1:event_idx, :], t_ord[events][1:event_idx]
end

function ph_global_test(schoenfeld_r::Matrix{Float64}, event_times::Vector{Float64})
    n_ev, p = size(schoenfeld_r)
    p == 0 && return Dict{Symbol, Any}(:statistic => NaN, :pvalue => NaN, :dof => 0)

    g = log.(max.(event_times, 1e-12))
    g_mean = mean(g); g_c = g .- g_mean
    U = schoenfeld_r' * g_c
    V = sum(g_c .^ 2) .* (schoonfeld_r' * schoenfeld_r) ./ n_ev
    V_inv = try inv(Symmetric(V)) catch; pinv(V) end
    stat = dot(U, V_inv * U)
    pv = 1 - cdf(Chisq(p), stat)
    return Dict{Symbol, Any}(:statistic => stat, :pvalue => pv, :dof => p, :method => "Schoenfeld 全局 PH 检验（g(t)=log(t)）")
end

function ph_variable_tests(schoenfeld_r::Matrix{Float64}, event_times::Vector{Float64})
    n_ev, p = size(schoenfeld_r)
    results = Dict{Symbol, Any}[]
    g = log.(max.(event_times, 1e-12)); g_mean = mean(g); g_c = g .- g_mean
    for k in 1:p
        r_k = schoenfeld_r[:, k]
        rho = cor(g_c, r_k)
        ssg = sum(g_c .^ 2)
        denom = ssg * (sum(r_k .^ 2) / n_ev)
        stat = denom > 1e-18 ? dot(r_k, g_c)^2 / denom : 0.0
        pv = 1 - cdf(Chisq(1), stat)
        push!(results, Dict{Symbol, Any}(:coef_index => k, :statistic => stat, :pvalue => pv, :rho => rho, :dof => 1))
    end
    return results
end

function baseline_survival(baseline_hazard_preview::Vector{Pair{Float64, Float64}})
    return [(t => exp(-H)) for (t, H) in baseline_hazard_preview]
end
