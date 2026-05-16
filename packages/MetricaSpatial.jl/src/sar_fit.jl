# === SAR：空间滞后，2SLS ======================================================

using LinearAlgebra: Symmetric, Diagonal, pinv, det

function fit_sar_2sls(
    y::Vector{Float64},
    X::Matrix{Float64},
    W::Matrix{Float64},
    colnames::Vector{Symbol};
    vcov_kind::Symbol,
)::Union{Tuple{Vector{Pair{Symbol, Float64}}, Vector{Float64}, Vector{Float64}, Vector{Float64}, Float64}, MetricaBase.ModelError}
    n, p = size(X)
    Wy = W * y
    WX = Matrix(W * X)
    Z = hcat(X, WX)
    Pz = Z * pinv(Symmetric(Z' * Z)) * Z'
    Xmat = hcat(Wy, X)
    XPX = Xmat' * Pz * Xmat
    XPXs = Symmetric((XPX + XPX') / 2)
    detv = det(XPXs)
    (!isfinite(detv) || abs(detv) < 1e-18) &&
        return MetricaBase.ModelError(
            :spatial_sar_singular,
            "SAR 2SLS 正规方程接近奇异",
            "设计矩阵或工具矩阵秩亏，无法稳定估计 ρ 与 β。",
            "请减少共线变量或检查权重结构。",
        )
    XPy = Xmat' * Pz * y
    β = XPXs \ XPy
    ρ = β[1]
    βx = β[2:end]
    fitted = ρ .* Wy + X * βx
    resid = y .- fitted
    σ2 = sum(abs2, resid) / max(1, n - length(β))
    invxpx = inv(XPXs)
    if vcov_kind == :HC1
        Xe = Xmat
        meat = Xe' * Diagonal(resid .^ 2) * Xe
        V = invxpx * meat * invxpx
        se = sqrt.(max.(0.0, diag(V)))
    else
        V = σ2 .* invxpx
        se = sqrt.(max.(0.0, diag(V)))
    end
    coefnames = vcat([:rho], colnames)
    pairs = Pair{Symbol, Float64}[coefnames[i] => β[i] for i in 1:length(β)]
    return (pairs, se, fitted, resid, ρ)
end
