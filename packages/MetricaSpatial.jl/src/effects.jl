# === 空间效应分解 ============================================================

using LinearAlgebra: I, inv

function empty_effects()
    return Dict{Symbol, Float64}()
end

function slx_effects(pairs::Vector{Pair{Symbol, Float64}}, x_colnames::Vector{Symbol})::Tuple{Dict{Symbol, Float64}, Dict{Symbol, Float64}, Dict{Symbol, Float64}, String}
    estimates = Dict(pairs)
    direct = Dict{Symbol, Float64}()
    indirect = Dict{Symbol, Float64}()
    total = Dict{Symbol, Float64}()
    for name in x_colnames[2:end]
        wx = Symbol("W_", String(name))
        d = get(estimates, name, 0.0)
        ind = get(estimates, wx, 0.0)
        direct[name] = d
        indirect[name] = ind
        total[name] = d + ind
    end
    return direct, indirect, total, "SLX 系数分解（直接效应=β，间接效应=θ）"
end

function sdm_effects(
    ρ::Float64,
    theta_dict::Dict{String, Float64},
    W::Matrix{Float64},
    x_colnames::Vector{Symbol},
)::Union{Tuple{Dict{Symbol, Float64}, Dict{Symbol, Float64}, Dict{Symbol, Float64}, String}, MetricaBase.ModelError}
    n = size(W, 1)
    S = try
        inv(I - ρ * W)
    catch
        return MetricaBase.ModelError(
            :sdm_effects_singular,
            "SDM 空间乘数矩阵不可逆",
            "无法计算 direct / indirect / total effects。",
            "请检查 ρ 是否接近空间权重矩阵谱边界。",
        )
    end
    mean_diag_S = sum(diag(S)) / n
    total_mult = sum(S) / n
    direct = Dict{Symbol, Float64}()
    indirect = Dict{Symbol, Float64}()
    total = Dict{Symbol, Float64}()
    for cn in x_colnames
        theta_k = get(theta_dict, String(cn), 0.0)
        d = mean_diag_S * (1.0 + theta_k)
        t = total_mult * (1.0 + theta_k)
        direct[cn] = d
        total[cn] = t
        indirect[cn] = t - d
    end
    return direct, indirect, total, "SDM 效应分解（空间乘数法，首期简化）"
end

function sar_effects(
    ρ::Float64,
    pairs::Vector{Pair{Symbol, Float64}},
    W::Matrix{Float64},
    x_colnames::Vector{Symbol},
)::Union{Tuple{Dict{Symbol, Float64}, Dict{Symbol, Float64}, Dict{Symbol, Float64}, String}, MetricaBase.ModelError}
    n = size(W, 1)
    S = try
        inv(I - ρ * W)
    catch
        return MetricaBase.ModelError(
            :spatial_sar_effects_singular,
            "SAR 空间乘数矩阵不可逆",
            "无法计算 direct / indirect / total effects。",
            "请检查 ρ 是否接近空间权重矩阵谱边界。",
        )
    end
    estimates = Dict(pairs)
    multiplier_direct = sum(diag(S)) / n
    multiplier_total = sum(S) / n
    direct = Dict{Symbol, Float64}()
    indirect = Dict{Symbol, Float64}()
    total = Dict{Symbol, Float64}()
    for name in x_colnames[2:end]
        β = get(estimates, name, 0.0)
        direct[name] = multiplier_direct * β
        total[name] = multiplier_total * β
        indirect[name] = total[name] - direct[name]
    end
    return direct, indirect, total, "SAR 精确空间乘数分解"
end
