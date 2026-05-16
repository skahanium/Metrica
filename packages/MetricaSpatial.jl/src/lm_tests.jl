# lm_tests.jl — LM-Lag / LM-Error / Robust LM-Lag / Robust LM-Error
# 参考 Anselin (1988) / R spdep::lm.LMtests 经典公式

function lm_lag_test(e::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64})
    n = length(e)
    sigma2 = dot(e, e) / n
    We = W * e
    T = tr(W * W + W' * W)
    J_num = dot(We, We) / sigma2
    J = (T + J_num) / sigma2
    LM = (dot(e, We) / sigma2)^2 / J
    pv = 1 - cdf(Chisq(1), LM)
    return Dict{Symbol, Any}(:statistic => LM, :pvalue => pv, :dof => 1)
end

function lm_error_test(e::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64})
    n = length(e)
    sigma2 = dot(e, e) / n
    We = W * e
    T = tr(W * W + W' * W)
    LM = (dot(e, We) / sigma2)^2 / T
    pv = 1 - cdf(Chisq(1), LM)
    return Dict{Symbol, Any}(:statistic => LM, :pvalue => pv, :dof => 1)
end

function robust_lm_lag_test(e::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64})
    n = length(e)
    sigma2 = dot(e, e) / n
    We = W * e
    T = tr(W * W + W' * W)
    J_num = dot(We, We) / sigma2
    J = (T + J_num) / sigma2
    LM_err = (dot(e, We) / sigma2)^2 / T
    LM_lag = (dot(e, We) / sigma2)^2 / J
    denom = J - T^2 / J
    if denom <= 1e-12
        return Dict{Symbol, Any}(:statistic => NaN, :pvalue => NaN, :dof => 1)
    end
    LM_rob = (dot(e, We) / sigma2 - LM_err)^2 / denom
    pv = 1 - cdf(Chisq(1), LM_rob)
    return Dict{Symbol, Any}(:statistic => LM_rob, :pvalue => pv, :dof => 1)
end

function robust_lm_error_test(e::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64})
    n = length(e)
    sigma2 = dot(e, e) / n
    We = W * e
    T = tr(W * W + W' * W)
    J_num = dot(We, We) / sigma2
    J = (T + J_num) / sigma2
    LM_lag = (dot(e, We) / sigma2)^2 / J
    LM_err = (dot(e, We) / sigma2)^2 / T
    denom = T - T^2 / J
    if denom <= 1e-12
        return Dict{Symbol, Any}(:statistic => NaN, :pvalue => NaN, :dof => 1)
    end
    LM_rob = (dot(e, We) / sigma2 - LM_lag)^2 / denom
    pv = 1 - cdf(Chisq(1), LM_rob)
    return Dict{Symbol, Any}(:statistic => LM_rob, :pvalue => pv, :dof => 1)
end
