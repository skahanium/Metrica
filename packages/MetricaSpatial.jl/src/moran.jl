# === 残差 Moran I（全局指标 + 随机化假设下期望）==============================

"""对中心化残差 `z` 与稀疏权重 `W` 计算全局 Moran I；`moran_var`/`moran_z` 首期简化为 `nothing`。"""
function moran_residuals(z::AbstractVector{Float64}, W::Matrix{Float64})::Dict{Symbol, Any}
    n = length(z)
    if n == 0
        return Dict{Symbol, Any}(
            :moran_i => nothing,
            :moran_ei => nothing,
            :moran_var => nothing,
            :moran_z => nothing,
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
        )
    end
    I = (n / S0) * (cross / denom)
    EI = -1.0 / (n - 1)
    return Dict{Symbol, Any}(
        :moran_i => I,
        :moran_ei => EI,
        :moran_var => nothing,
        :moran_z => nothing,
    )
end
