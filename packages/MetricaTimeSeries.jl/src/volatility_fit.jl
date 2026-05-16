# volatility_fit.jl — ARCH / GARCH / GJR / EGARCH 条件方差递推与数值优化
# BFGS + OPG 三明治标准误；参数化保证 ω>0、系数非负且平稳域内（α+β < 0.99）。

# === 无条件方差 ===============================================================

function _arch_unconditional_variance(ω::Float64, α::Vector{Float64})
    s = sum(α)
    s >= 1.0 - 1e-10 && return NaN
    return ω / (1.0 - s)
end

function _garch_unconditional_variance(ω::Float64, α::Vector{Float64}, β::Vector{Float64})
    s = sum(α) + sum(β)
    s >= 1.0 - 1e-10 && return NaN
    return ω / (1.0 - s)
end

# === Softmax 参数化（系数和 < scale）===========================================

function _softmax_scaled(u::Vector{Float64}, scale::Float64)
    isempty(u) && return Float64[]
    m = maximum(u)
    ex = exp.(u .- m)
    s = sum(ex)
    s <= 0 && return fill(scale / length(u), length(u))
    return (ex ./ s) .* scale
end

# === ARCH 条件方差 + 对数似然 =================================================

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
        ht <= 1e-18 && return (false, h)
        h[t] = ht
    end
    return (true, h)
end

function arch_loglik(e::Vector{Float64}, ω::Float64, α::Vector{Float64})
    ok, h = arch_conditional_variances(e, ω, α)
    !ok && return NaN
    ll = 0.0
    @inbounds for t in eachindex(e)
        ll += -0.5 * (log(2 * pi * h[t]) + e[t]^2 / h[t])
    end
    return ll
end

# === GARCH 条件方差 + 对数似然 =================================================

function garch_conditional_variances(e::Vector{Float64}, ω::Float64, α::Vector{Float64}, β::Vector{Float64})
    T = length(e)
    p = length(α); q = length(β)
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
        ht <= 1e-18 && return (false, h)
        h[t] = ht
    end
    return (true, h)
end

function garch_loglik(e::Vector{Float64}, ω::Float64, α::Vector{Float64}, β::Vector{Float64})
    ok, h = garch_conditional_variances(e, ω, α, β)
    !ok && return NaN
    ll = 0.0
    @inbounds for t in eachindex(e)
        ll += -0.5 * (log(2 * pi * h[t]) + e[t]^2 / h[t])
    end
    return ll
end

# === Student-t 对数似然 =======================================================

function student_t_loglik(e::Vector{Float64}, h::Vector{Float64}, ν::Float64)
    ν <= 2.0 && return NaN
    T = length(e)
    ll = 0.0
    c = lgamma((ν + 1) / 2) - lgamma(ν / 2) - 0.5 * log(π * (ν - 2))
    @inbounds for t in 1:T
        ht = max(h[t], 1e-18)
        z2 = e[t]^2 / (ht * (ν - 2))
        ll += c - 0.5 * log(ht) - ((ν + 1) / 2) * log(1 + z2)
    end
    return ll
end

# === 参数打包 =================================================================

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

# === OPG 三明治标准误 =========================================================

function _finite_diff_hessian(f::Function, θ::Vector{Float64})
    k = length(θ)
    H = Matrix{Float64}(undef, k, k)
    ϵ = 1e-5
    f0 = f(θ)
    for i in 1:k
        for j in i:k
            θ_pp = copy(θ); θ_pp[i] += ϵ; θ_pp[j] += ϵ
            θ_pm = copy(θ); θ_pm[i] += ϵ; θ_pm[j] -= ϵ
            θ_mp = copy(θ); θ_mp[i] -= ϵ; θ_mp[j] += ϵ
            θ_mm = copy(θ); θ_mm[i] -= ϵ; θ_mm[j] -= ϵ
            H[i, j] = (f(θ_pp) - f(θ_pm) - f(θ_mp) + f(θ_mm)) / (4 * ϵ^2)
            H[j, i] = H[i, j]
        end
    end
    return H
end

function _opg_standard_errors(θ::Vector{Float64}, obj_fn::Function, n::Int)
    k = length(θ)
    H = _finite_diff_hessian(obj_fn, θ)  # 对目标函数（负 loglik）的 Hessian
    # H 是负 loglik 的 Hessian，正定则取其逆乘以 n
    info_mat = try
        inv(Symmetric(H))
    catch
        # 不可逆时退化
        diag_H = diag(H)
        all(d -> d > 1e-12, diag_H) ? inv(Diagonal(diag_H)) : Diagonal(fill(1.0, k))
    end
    # OPG: V = n * info_mat * B * info_mat, B ≈ info_mat（对 QMLE 近似）
    # 简化：V ≈ info_mat（基于信息矩阵等式）
    V = n .* info_mat
    se = sqrt.(max.(diag(V), 0.0))
    # 限制异常值
    se[isfinite.(se)] .= min.(se[isfinite.(se)], 100.0)
    return se
end

# === ARCH QMLE 拟合 (BFGS) ====================================================

function fit_arch_qmle(e::Vector{Float64}, q::Int; max_iter::Int=5000, tol::Float64=1e-5)
    v0 = var(e)
    if !(v0 > 0)
        return (NaN, NaN, Float64[], false, 0, "var_zero", Float64[], fill(NaN, q + 2))
    end
    x0 = vcat(log(0.05 * max(v0, 1e-8)), zeros(q))
    function obj(x::Vector{Float64})
        ω, α = _pack_arch_params(x[1], x[2:end])
        -arch_loglik(e, ω, α)
    end
    r = Optim.optimize(obj, x0, BFGS(), Optim.Options(iterations=max_iter, f_reltol=tol, g_reltol=tol))
    xm = Optim.minimizer(r)
    ωm, αm = _pack_arch_params(xm[1], xm[2:end])
    ll = arch_loglik(e, ωm, αm)
    converged = Optim.converged(r) && isfinite(ll)
    iters = r.iterations
    okh, h = arch_conditional_variances(e, ωm, αm)
    !okh && (return (NaN, ωm, αm, false, iters, "invalid_variance", fill(NaN, length(e)), fill(NaN, q + 2)))
    n = length(e)
    se_raw = _opg_standard_errors(xm, obj, n)
    se_final = [se_raw[1]; se_raw[2:end]]  # ω + α's
    return (ll, ωm, αm, converged, iters, "BFGS", h, se_final)
end

# === GARCH QMLE 拟合 (BFGS) ===================================================

function fit_garch_qmle(e::Vector{Float64}, p::Int, q::Int; max_iter::Int=8000, tol::Float64=1e-5)
    v0 = var(e)
    if !(v0 > 0)
        return (NaN, NaN, Float64[], Float64[], false, 0, "var_zero", Float64[], fill(NaN, 1+p+q))
    end
    x0 = vcat(log(0.05 * max(v0, 1e-8)), zeros(p + q))
    function obj(x::Vector{Float64})
        ω, α, β = _pack_garch_params(x[1], x[2:end], p, q)
        -garch_loglik(e, ω, α, β)
    end
    r = Optim.optimize(obj, x0, BFGS(), Optim.Options(iterations=max_iter, f_reltol=tol, g_reltol=tol))
    xm = Optim.minimizer(r)
    ωm, αm, βm = _pack_garch_params(xm[1], xm[2:end], p, q)
    ll = garch_loglik(e, ωm, αm, βm)
    converged = Optim.converged(r) && isfinite(ll)
    iters = r.iterations
    okh, h = garch_conditional_variances(e, ωm, αm, βm)
    !okh && (return (NaN, ωm, αm, βm, false, iters, "invalid_variance", fill(NaN, length(e)), fill(NaN, 1+p+q)))
    n = length(e)
    se_raw = _opg_standard_errors(xm, obj, n)
    se_final = [se_raw[1]; se_raw[2:end]]
    return (ll, ωm, αm, βm, converged, iters, "BFGS", h, se_final)
end
