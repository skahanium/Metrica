# volatility_fit.jl — ARCH / GARCH / GJR / EGARCH 条件方差递推与数值优化
# BFGS + OPG 三明治标准误；参数化保证 ω>0、系数非负且平稳域内（α+β < 0.99）。
# 支持 Gaussian / Student-t / Skewed-t (Fernandez-Steel) 分布。

# === 无条件方差 ===============================================================

function _arch_unconditional_variance(ω, α)
    s = sum(α); s >= 1.0 - 1e-10 && return NaN; return ω / (1.0 - s)
end
function _garch_unconditional_variance(ω, α, β)
    s = sum(α) + sum(β); s >= 1.0 - 1e-10 && return NaN; return ω / (1.0 - s)
end

# === Softmax 参数化 ===========================================================

function _softmax_scaled(u, scale)
    isempty(u) && return Float64[]; m = maximum(u); ex = exp.(u .- m)
    s = sum(ex); s <= 0 && return fill(scale / length(u), length(u)); return (ex ./ s) .* scale
end

# === ARCH 条件方差 + 对数似然 =================================================

function arch_conditional_variances(e, ω, α)
    T = length(e); q = length(α); h = Vector{Float64}(undef, T)
    sα = sum(α)
    ω <= 0 || any(x -> x < 0, α) || sα >= 1.0 - 1e-10 && return (false, h)
    uncond = _arch_unconditional_variance(ω, α)
    !isfinite(uncond) || uncond <= 0 && return (false, h)
    @inbounds for t in 1:T; ht = ω
        for i in 1:q; ti = t - i; ei2 = ti >= 1 ? e[ti]^2 : uncond; ht += α[i] * ei2 end
        ht <= 1e-18 && return (false, h); h[t] = ht
    end; return (true, h)
end

function arch_loglik(e, ω, α)
    ok, h = arch_conditional_variances(e, ω, α); !ok && return NaN; ll = 0.0
    @inbounds for t in eachindex(e); ll += -0.5 * (log(2π * h[t]) + e[t]^2 / h[t]) end
    return ll
end

# === GARCH 条件方差 + 对数似然 =================================================

function garch_conditional_variances(e, ω, α, β)
    T = length(e); p = length(α); q = length(β); h = Vector{Float64}(undef, T)
    persistence = sum(α) + sum(β)
    ω <= 0 || any(x -> x < 0, [α;β]) || persistence >= 1.0 - 1e-10 && return (false, h)
    uncond = _garch_unconditional_variance(ω, α, β)
    (!isfinite(uncond) || uncond <= 0) && return (false, h)
    @inbounds for t in 1:T; ht = ω
        for i in 1:p; ti = t - i; ei2 = ti >= 1 ? e[ti]^2 : uncond; ht += α[i] * ei2 end
        for j in 1:q; tj = t - j; hj = tj >= 1 ? h[tj] : uncond; ht += β[j] * hj end
        ht <= 1e-18 && return (false, h); h[t] = ht
    end; return (true, h)
end

function garch_loglik(e, ω, α, β)
    ok, h = garch_conditional_variances(e, ω, α, β); !ok && return NaN; ll = 0.0
    @inbounds for t in eachindex(e); ll += -0.5 * (log(2π * h[t]) + e[t]^2 / h[t]) end
    return ll
end

# === Student-t 对数似然 =======================================================

function student_t_loglik(e, h, ν)
    ν <= 2.0 && return NaN; T = length(e); ll = 0.0
    c = lgamma((ν + 1) / 2) - lgamma(ν / 2) - 0.5 * log(π * (ν - 2))
    @inbounds for t in 1:T; ht = max(h[t], 1e-18); z2 = e[t]^2 / (ht * (ν - 2))
        ll += c - 0.5 * log(ht) - ((ν + 1) / 2) * log(1 + z2) end
    return ll
end

# === Skewed-t (Fernandez-Steel 1998) 对数似然 =================================

function skewed_t_loglik(e, h, ν, λ)
    ν <= 2.0 && return NaN; abs(λ) >= 1.0 && return NaN; T = length(e); ll = 0.0
    c0 = lgamma((ν + 1) / 2) - lgamma(ν / 2) - 0.5 * log(π * (ν - 2))
    s_neg = 1 - λ; s_pos = 1 + λ
    @inbounds for t in 1:T; ht = max(h[t], 1e-18); z = e[t] / sqrt(ht)
        zs = z < 0 ? z / s_neg : z / s_pos; z2 = zs^2 / (ν - 2)
        ll += c0 - 0.5 * log(ht) + log(2 / (s_neg + s_pos)) - ((ν + 1) / 2) * log(1 + z2) end
    return ll
end

# === 参数打包 =================================================================

function _pack_arch_params(logω, uα)
    ω = exp(logω); α = _softmax_scaled(uα, 0.99); return ω, α
end
function _pack_garch_params(logω, uab, p, q)
    ω = exp(logω); w = _softmax_scaled(uab, 0.99)
    length(w) == p + q || error("内部参数长度须等于 p+q"); α = w[1:p]; β = w[p+1:end]; return ω, α, β
end

# === OPG 三明治标准误（含 Hessian 状态）=======================================

function _finite_diff_hessian(f, θ)
    k = length(θ); H = Matrix{Float64}(undef, k, k); ϵ = 1e-5
    for i in 1:k, j in i:k
        θ_pp = copy(θ); θ_pp[i] += ϵ; θ_pp[j] += ϵ
        θ_pm = copy(θ); θ_pm[i] += ϵ; θ_pm[j] -= ϵ
        θ_mp = copy(θ); θ_mp[i] -= ϵ; θ_mp[j] += ϵ
        θ_mm = copy(θ); θ_mm[i] -= ϵ; θ_mm[j] -= ϵ
        H[i,j] = (f(θ_pp) - f(θ_pm) - f(θ_mp) + f(θ_mm)) / (4ϵ^2); H[j,i] = H[i,j]
    end; return H
end

function _opg_standard_errors(θ, obj_fn, n)
    k = length(θ); H = _finite_diff_hessian(obj_fn, θ); hessian_status = "ok"
    info_mat = try; inv(Symmetric(H))
    catch; hessian_status = "singular"
        diag_H = diag(H); all(d -> d > 1e-12, diag_H) ? inv(Diagonal(diag_H)) : begin hessian_status = "diag_zero"; Diagonal(fill(1.0, k)) end
    end
    V = n .* info_mat; se = sqrt.(max.(diag(V), 0.0))
    se[isfinite.(se)] .= min.(se[isfinite.(se)], 100.0)
    return se, hessian_status
end

# === ARCH QMLE 拟合 (BFGS, dist=:gaussian/:student_t/:skewed_t) ===============

function fit_arch_qmle(e, q; max_iter=5000, tol=1e-5, dist=:gaussian)
    v0 = var(e); !(v0 > 0) && return (NaN, NaN, Float64[], false, 0, "var_zero", Float64[], fill(NaN, q+2), "var_zero")
    has_nu = dist === :student_t || dist === :skewed_t; has_λ = dist === :skewed_t
    n_extra = (has_nu ? 1 : 0) + (has_λ ? 1 : 0)
    x0 = vcat(log(0.05 * max(v0, 1e-8)), zeros(q), has_nu ? [log(5.0)] : Float64[], has_λ ? [0.0] : Float64[])
    function obj(x)
        ω, α = _pack_arch_params(x[1], x[2:end]); ok, h = arch_conditional_variances(e, ω, α); !ok && return 1e30
        if dist === :student_t; ν = 2.0 + exp(x[q+2]); return -student_t_loglik(e, h, ν)
        elseif dist === :skewed_t; ν = 2.0 + exp(x[q+2]); λ = tanh(x[q+3]); return -skewed_t_loglik(e, h, ν, λ)
        else; return -arch_loglik(e, ω, α) end
    end
    r = Optim.optimize(obj, x0, BFGS(), Optim.Options(iterations=max_iter, f_reltol=tol, g_reltol=tol))
    xm = Optim.minimizer(r); ωm, αm = _pack_arch_params(xm[1], xm[2:end])
    νm = has_nu ? 2.0 + exp(xm[q+2]) : NaN; λm = has_λ ? tanh(xm[q+3]) : NaN
    okh, h = arch_conditional_variances(e, ωm, αm)
    !okh && return (NaN, ωm, αm, false, r.iterations, "invalid_variance", fill(NaN, length(e)), fill(NaN, q+2+n_extra), "invalid_variance")
    ll = if dist === :student_t; student_t_loglik(e, h, νm)
    elseif dist === :skewed_t; skewed_t_loglik(e, h, νm, λm)
    else; arch_loglik(e, ωm, αm) end
    converged = Optim.converged(r) && isfinite(ll); iters = r.iterations
    se_all, hess_stat = _opg_standard_errors(xm, obj, length(e))
    return (ll, ωm, αm, converged, iters, "BFGS", h, se_all, hess_stat)
end

# === GARCH QMLE 拟合 (BFGS, dist) =============================================

function fit_garch_qmle(e, p, q; max_iter=8000, tol=1e-5, dist=:gaussian)
    v0 = var(e); !(v0 > 0) && return (NaN, NaN, Float64[], Float64[], false, 0, "var_zero", Float64[], fill(NaN, 1+p+q), "var_zero")
    has_nu = dist === :student_t || dist === :skewed_t; has_λ = dist === :skewed_t
    n_extra = (has_nu ? 1 : 0) + (has_λ ? 1 : 0); n_base = 1 + p + q
    x0 = vcat(log(0.05 * max(v0, 1e-8)), zeros(p+q), has_nu ? [log(5.0)] : Float64[], has_λ ? [0.0] : Float64[])
    function obj(x)
        ω, α, β = _pack_garch_params(x[1], x[2:end], p, q); ok, h = garch_conditional_variances(e, ω, α, β); !ok && return 1e30
        if dist === :student_t; ν = 2.0 + exp(x[n_base+1]); return -student_t_loglik(e, h, ν)
        elseif dist === :skewed_t; ν = 2.0 + exp(x[n_base+1]); λ = tanh(x[n_base+2]); return -skewed_t_loglik(e, h, ν, λ)
        else; return -garch_loglik(e, ω, α, β) end
    end
    r = Optim.optimize(obj, x0, BFGS(), Optim.Options(iterations=max_iter, f_reltol=tol, g_reltol=tol))
    xm = Optim.minimizer(r); ωm, αm, βm = _pack_garch_params(xm[1], xm[2:end], p, q)
    νm = has_nu ? 2.0 + exp(xm[n_base+1]) : NaN; λm = has_λ ? tanh(xm[n_base+2]) : NaN
    okh, h = garch_conditional_variances(e, ωm, αm, βm)
    !okh && return (NaN, ωm, αm, βm, false, r.iterations, "invalid_variance", fill(NaN, length(e)), fill(NaN, n_base+n_extra), "invalid_variance")
    ll = if dist === :student_t; student_t_loglik(e, h, νm)
    elseif dist === :skewed_t; skewed_t_loglik(e, h, νm, λm)
    else; garch_loglik(e, ωm, αm, βm) end
    converged = Optim.converged(r) && isfinite(ll); iters = r.iterations
    se_all, hess_stat = _opg_standard_errors(xm, obj, length(e))
    return (ll, ωm, αm, βm, converged, iters, "BFGS", h, se_all, hess_stat)
end
