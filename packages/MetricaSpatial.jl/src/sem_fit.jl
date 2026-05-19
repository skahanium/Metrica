# === SEM：空间误差，Gaussian 剖面 ML（稠密 logdet，n ≤ 800）=================

using LinearAlgebra: I, Symmetric, logabsdet

function fit_sem_ml(
    y::Vector{Float64},
    X::Matrix{Float64},
    W::Matrix{Float64},
    colnames::Vector{Symbol},
)::Union{Tuple{Vector{Pair{Symbol, Float64}}, Vector{Float64}, Vector{Float64}, Vector{Float64}, Float64, Float64}, MetricaBase.ModelError}
    n = length(y)
    n > 800 && return MetricaBase.ModelError(
        :spatial_sem_size_limit,
        "SEM 首期实现限制样本量",
        "Gaussian 剖面 ML 使用稠密 `logdet(I-λW)`，当前要求 n ≤ 800。",
        "请抽样或等待二期稀疏 logdet 实现。",
    )
    Wd = Matrix(W)
    function nll(λv::Vector{Float64})
        λ = λv[1]
        A = I - λ * Wd
        ly = A * y
        lX = A * X
        β = lX \ ly
        e = ly - lX * β
        σ2 = sum(abs2, e) / n
        σ2 <= 1e-18 && return Inf
        la = try
            logabsdet(A)[1]
        catch
            return Inf
        end
        !isfinite(la) && return Inf
        return n / 2 * log(2π) + n / 2 * log(σ2) - la
    end
    opt = Optim.optimize(nll, [0.0], Optim.NelderMead(), Optim.Options(iterations=400, f_reltol=1e-7))
    λhat = Optim.minimizer(opt)[1]
    A = I - λhat * Wd
    ly = A * y
    lX = A * X
    β = lX \ ly
    σ2 = sum(abs2, ly - lX * β) / n
    fitted = X * β
    resid = y .- fitted
    loglik = -n / 2 * log(2π) - n / 2 * log(σ2) + logabsdet(A)[1]
    invXpX = try
        inv(Symmetric(lX' * lX))
    catch
        return MetricaBase.ModelError(:spatial_sem_singular, "SEM 变换后设计矩阵奇异", "无法估计 β。", nothing)
    end
    se_β = sqrt.(max.(0.0, σ2 .* diag(invXpX)))
    p = length(β)
    length(se_β) != p && return MetricaBase.ModelError(:spatial_sem_se, "标准误长度异常", "", nothing)
    se_full = Vector{Float64}(undef, 1 + p)
    se_full[1] = NaN
    se_full[2:end] .= se_β
    pairs = Pair{Symbol, Float64}[Pair(:lambda, λhat)]
    for i in 1:p
        push!(pairs, Pair(colnames[i], β[i]))
    end
    return (pairs, se_full, fitted, resid, λhat, loglik)
end
