# === 残差 Moran I（全局指标 + 随机化假设下期望）==============================

"""对中心化残差 `z` 与权重 `W` 计算全局 Moran I 及正态近似方差、z 值、p 值。"""
function moran_residuals(z::AbstractVector{Float64}, W::Matrix{Float64})::Dict{Symbol, Any}
    n = length(z)
    if n == 0
        return Dict{Symbol, Any}(
            :moran_i => nothing,
            :moran_ei => nothing,
            :moran_var => nothing,
            :moran_z => nothing,
            :moran_pvalue => nothing,
        )
    end
    zc = z .- (sum(z) / n)
    denom = sum(abs2, zc)
    if denom <= 0
        return Dict{Symbol, Any}(
            :moran_i => nothing,
            :moran_ei => nothing,
            :moran_var => nothing,
            :moran_z => nothing,
            :moran_pvalue => nothing,
        )
    end
    Wz = W * zc
    cross = dot(zc, Wz)
    S0 = sum(W)
    if S0 <= 0
        return Dict{Symbol, Any}(
            :moran_i => nothing,
            :moran_ei => nothing,
            :moran_var => nothing,
            :moran_z => nothing,
            :moran_pvalue => nothing,
        )
    end
    I = (n / S0) * (cross / denom)
    EI = -1.0 / (n - 1)
    if n <= 2
        return Dict{Symbol, Any}(
            :moran_i => I,
            :moran_ei => EI,
            :moran_var => nothing,
            :moran_z => nothing,
            :moran_pvalue => nothing,
        )
    end
    S1 = 0.5 * sum((W .+ W') .^ 2)
    row_col_sums = vec(sum(W, dims=2)) .+ vec(sum(W, dims=1))
    S2 = sum(row_col_sums .^ 2)
    var_i = (n^2 * S1 - n * S2 + 3 * S0^2) / ((n - 1) * (n + 1) * S0^2) - EI^2
    if !isfinite(var_i) || var_i <= 0
        return Dict{Symbol, Any}(
            :moran_i => I,
            :moran_ei => EI,
            :moran_var => nothing,
            :moran_z => nothing,
            :moran_pvalue => nothing,
        )
    end
    zscore = (I - EI) / sqrt(var_i)
    pvalue = _normal_two_sided_pvalue(zscore)
    return Dict{Symbol, Any}(
        :moran_i => I,
        :moran_ei => EI,
        :moran_var => var_i,
        :moran_z => zscore,
        :moran_pvalue => pvalue,
    )
end

function _normal_two_sided_pvalue(z::Float64)::Float64
    x = abs(z)
    t = 1.0 / (1.0 + 0.2316419 * x)
    poly = (((((1.330274429 * t - 1.821255978) * t) + 1.781477937) * t - 0.356563782) * t + 0.319381530) * t
    tail = exp(-0.5 * x^2) / sqrt(2π) * poly
    return clamp(2.0 * tail, 0.0, 1.0)
end
