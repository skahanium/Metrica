# === SLX：空间外生滞后，OLS ===================================================

using LinearAlgebra: Symmetric, inv

function fit_slx_ols(
    y::Vector{Float64},
    X::Matrix{Float64},
    W::Matrix{Float64},
    colnames::Vector{Symbol},
)::Union{Tuple{Vector{Pair{Symbol, Float64}}, Vector{Float64}, Vector{Float64}, Vector{Float64}}, MetricaBase.ModelError}
    n, p = size(X)
    if p < 2
        return MetricaBase.ModelError(
            :spatial_slx_requires_predictor,
            "SLX 至少需要一个自变量",
            "空间外生滞后模型需要对非截距自变量构造 WX。",
            "请在公式右侧加入至少一个解释变量。",
        )
    end
    WX = Matrix(W * X[:, 2:end])
    Xslx = hcat(X, WX)
    xtx_raw = Xslx' * Xslx
    xtx = Symmetric((xtx_raw + xtx_raw') / 2)
    β = try
        xtx \ (Xslx' * y)
    catch
        return MetricaBase.ModelError(
            :spatial_slx_singular,
            "SLX 设计矩阵奇异",
            "原始自变量与空间滞后自变量之间存在无法稳定分解的共线性。",
            "请减少共线变量或检查空间权重结构。",
        )
    end
    fitted = Xslx * β
    resid = y .- fitted
    σ2 = sum(abs2, resid) / max(1, n - length(β))
    V = try
        σ2 .* inv(xtx)
    catch
        return MetricaBase.ModelError(
            :spatial_slx_vcov_singular,
            "SLX 协方差矩阵不可逆",
            "估计系数可得，但无法稳定计算经典标准误。",
            "请检查自变量与空间滞后项的共线性。",
        )
    end
    se = sqrt.(max.(0.0, diag(V)))
    wx_names = [Symbol("W_", String(name)) for name in colnames[2:end]]
    coefnames = vcat(colnames, wx_names)
    pairs = Pair{Symbol, Float64}[coefnames[i] => β[i] for i in 1:length(β)]
    return (pairs, se, fitted, resid)
end
