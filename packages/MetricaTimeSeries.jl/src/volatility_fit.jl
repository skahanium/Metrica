# volatility_fit.jl — ARCH / GARCH 条件方差递推与数值优化（内部使用）
# 首期采用 Gaussian QMLE（条件正态对数似然）+ Optim.Nelder-Mead；参数化保证 ω>0、
# ARCH/GARCH 系数非负且平稳域内（系数和 < 0.99）。

"""
    _arch_unconditional_variance(ω::Float64, α::Vector{Float64}) -> Float64

ARCH(q) 无条件方差 σ² = ω / (1 - Σαᵢ)（要求 Σαᵢ < 1）。
"""
function _arch_unconditional_variance(ω::Float64, α::Vector{Float64})
    s = sum(α)
    s >= 1.0 - 1e-10 && return NaN
    return ω / (1.0 - s)
end

"""
    _garch_unconditional_variance(ω::Float64, α::Vector{Float64}, β::Vector{Float64}) -> Float64

GARCH(p,q) 无条件方差 σ² = ω / (1 - Σαᵢ - Σβⱼ)。
"""
function _garch_unconditional_variance(ω::Float64, α::Vector{Float64}, β::Vector{Float64})
    s = sum(α) + sum(β)
    s >= 1.0 - 1e-10 && return NaN
    return ω / (1.0 - s)
end

function _softmax_scaled(u::Vector{Float64}, scale::Float64)
    isempty(u) && return Float64[]
    m = maximum(u)
    ex = exp.(u .- m)
    s = sum(ex)
    s <= 0 && return fill(scale / length(u), length(u))
    return (ex ./ s) .* scale
end

"""
    arch_conditional_variances(e::Vector{Float64}, ω::Float64, α::Vector{Float64}) -> (ok, h)

计算 ARCH(q) 条件方差路径；若存在非正 `h[t]` 则 `ok=false`。
"""
function arch_conditional_variances(e::Vector{Float64}, ω::Float64, α::Vector{Float64})
    T = length(e)
    q = length(α)
    h = Vector{Float64}(undef, T)
    sα = sum(α)
    if ω <= 0 || any(x -> x < 0, α) || sα >= 1.0 - 1e-10
        return (false, h)
    end
    uncond = _arch_unconditional_variance(ω, α)
    !isfinite(uncond) || uncond <= 0 && return (false, h)
    @inbounds for t in 1:T
        ht = ω
        for i in 1:q
            ti = t - i
            ei2 = ti >= 1 ? e[ti]^2 : uncond
            ht += α[i] * ei2
        end
        if ht <= 1e-18
            return (false, h)
        end
        h[t] = ht
    end
    return (true, h)
end

function arch_loglik(e::Vector{Float64}, ω::Float64, α::Vector{Float64})
    ok, h = arch_conditional_variances(e, ω, α)
    !ok && return NaN
    ll = 0.0
    @inbounds for t in 1:length(e)
        ll += -0.5 * (log(2 * pi * h[t]) + e[t]^2 / h[t])
    end
    return ll
end

"""
    garch_conditional_variances(e::Vector{Float64}, ω::Float64, α::Vector{Float64}, β::Vector{Float64}) -> (ok, h)
"""
function garch_conditional_variances(e::Vector{Float64}, ω::Float64, α::Vector{Float64}, β::Vector{Float64})
    T = length(e)
    p, q = length(α), length(β)
    h = Vector{Float64}(undef, T)
    persistence = sum(α) + sum(β)
    if ω <= 0 || any(x -> x < 0, α) || any(x -> x < 0, β) || persistence >= 1.0 - 1e-10
        return (false, h)
    end
    uncond = _garch_unconditional_variance(ω, α, β)
    (!isfinite(uncond) || uncond <= 0) && return (false, h)
    @inbounds for t in 1:T
        ht = ω
        for i in 1:p
            ti = t - i
            ei2 = ti >= 1 ? e[ti]^2 : uncond
            ht += α[i] * ei2
        end
        for j in 1:q
            tj = t - j
            hj = tj >= 1 ? h[tj] : uncond
            ht += β[j] * hj
        end
        if ht <= 1e-18
            return (false, h)
        end
        h[t] = ht
    end
    return (true, h)
end

function garch_loglik(e::Vector{Float64}, ω::Float64, α::Vector{Float64}, β::Vector{Float64})
    ok, h = garch_conditional_variances(e, ω, α, β)
    !ok && return NaN
    ll = 0.0
    @inbounds for t in 1:length(e)
        ll += -0.5 * (log(2 * pi * h[t]) + e[t]^2 / h[t])
    end
    return ll
end

function _pack_arch_params(logω::Float64, uα::Vector{Float64})
    ω = exp(logω)
    α = _softmax_scaled(uα, 0.99)
    return ω, α
end

function _pack_garch_params(logω::Float64, uab::Vector{Float64}, p::Int, q::Int)
    ω = exp(logω)
    w = _softmax_scaled(uab, 0.99)
    length(w) == p + q || error("内部参数长度须等于 p+q")
    α = w[1:p]
    β = w[p+1:end]
    return ω, α, β
end

function fit_arch_qmle(
    e::Vector{Float64},
    q::Int;
    max_iter::Int = 5000,
    tol::Float64 = 1e-5,
)
    v0 = var(e)
    if !(v0 > 0)
        return (NaN, NaN, Float64[], false, 0, "var_zero", Float64[])
    end
    x0 = vcat(log(0.05 * max(v0, 1e-8)), zeros(q))
    function obj(x::Vector{Float64})
        ω, α = _pack_arch_params(x[1], x[2:end])
        -arch_loglik(e, ω, α)
    end
    r = Optim.optimize(obj, x0, Optim.NelderMead(), Optim.Options(iterations=max_iter, f_reltol=tol))
    xm = Optim.minimizer(r)
    ωm, αm = _pack_arch_params(xm[1], xm[2:end])
    ll = arch_loglik(e, ωm, αm)
    converged = Optim.converged(r) && isfinite(ll)
    iters = r.iterations
    okh, h = arch_conditional_variances(e, ωm, αm)
    !okh && (return (NaN, ωm, αm, false, iters, "invalid_variance", fill(NaN, length(e))))
    return (ll, ωm, αm, converged, iters, "NelderMead", h)
end

function fit_garch_qmle(
    e::Vector{Float64},
    p::Int,
    q::Int;
    max_iter::Int = 8000,
    tol::Float64 = 1e-5,
)
    v0 = var(e)
    if !(v0 > 0)
        return (NaN, NaN, Float64[], Float64[], false, 0, "var_zero", Float64[])
    end
    x0 = vcat(log(0.05 * max(v0, 1e-8)), zeros(p + q))
    function obj(x::Vector{Float64})
        ω, α, β = _pack_garch_params(x[1], x[2:end], p, q)
        -garch_loglik(e, ω, α, β)
    end
    r = Optim.optimize(obj, x0, Optim.NelderMead(), Optim.Options(iterations=max_iter, f_reltol=tol))
    xm = Optim.minimizer(r)
    ωm, αm, βm = _pack_garch_params(xm[1], xm[2:end], p, q)
    ll = garch_loglik(e, ωm, αm, βm)
    converged = Optim.converged(r) && isfinite(ll)
    iters = r.iterations
    okh, h = garch_conditional_variances(e, ωm, αm, βm)
    !okh && (return (NaN, ωm, αm, βm, false, iters, "invalid_variance", fill(NaN, length(e))))
    return (ll, ωm, αm, βm, converged, iters, "NelderMead", h)
end
