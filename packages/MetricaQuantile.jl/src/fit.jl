# === 线性分位数回归拟合 =========================================================

using DataFrames
using Distributions: Normal, cdf, quantile
using LinearAlgebra: cond, rank
using QuantileRegressions
import StatsAPI
using Statistics
using StatsModels: coefnames

function MetricaBase.model_capabilities(r::QuantileFitResult)::MetricaBase.ModelCapabilities
    return MetricaBase.ModelCapabilities(
        :partial,
        :quantile,
        [:quantile],
        ["linear programming (IP)"],
        [:pseudo_r2, :pseudo_r2, :rank_X, :cond_X, :inference_kind, :multi_tau, :bootstrap_se],
        [:rank_inference, :sparsity_inference, :iv_quantile, :panel_quantile],
        Symbol[],
        false,
        ["首期仅支持单 τ 分位数回归。多 τ、bootstrap SE、IV/panel quantile 为二期功能。"],
    )
end

"""check 损失求和：ρ_τ(u) = u * (τ - I(u<0))，用于伪 R²。"""
function _check_loss_sum(residuals::AbstractVector{<:Real}, τ::Float64)
    s = 0.0
    for u in residuals
        s += u >= 0 ? τ * u : (τ - 1) * u
    end
    return s
end

function _pseudo_r2_mc_fadden(y::Vector{Float64}, X::Matrix{Float64}, β::Vector{Float64}, τ::Float64)
    full_r = y - X * β
    L1 = _check_loss_sum(full_r, τ)
    q0 = Statistics.quantile(y, τ)
    null_r = y .- q0
    L0 = _check_loss_sum(null_r, τ)
    L0 <= eps() * max(length(y), 1) && return nothing
    return 1.0 - L1 / L0
end

function MetricaBase.fit(
    ::Type{QuantileModel},
    formula::AbstractString,
    data;
    quantile_tau::Real = 0.5,
)
    τ = Float64(quantile_tau)
    if !(τ > 1e-8 && τ < 1.0 - 1e-8)
        return MetricaBase.ModelError(
            :invalid_quantile_tau,
            "分位点 τ 不在开区间 (0,1)",
            "收到 τ = $(τ)。实现要求 1e-8 < τ < 1-1e-8。",
            "请使用 quantile(0.5) 等形式指定合法分位点。",
        )
    end

    dataset = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    model_columns = MetricaLinear.collect_term_symbols(model_formula)
    err = MetricaLinear.validate_model_columns(dataset, model_columns, nothing, nothing)
    err isa MetricaBase.ModelError && return err

    prepared = MetricaLinear.prepare_model_data(
        dataset, model_formula, model_columns, nothing, nothing,
    )
    prepared isa MetricaBase.ModelError && return prepared

    (filtered_dataset, _mf, _, X, y, _, _, n_total, n_effective) = prepared
    nobs = length(y)
    ncoef = size(X, 2)

    errd = MetricaLinear.validate_design(X, ncoef, nobs)
    errd isa MetricaBase.ModelError && return errd

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, MetricaLinear.build_rows_dropped_warning(dropped_rows))

    if τ < 0.05 || τ > 0.95
        push!(
            warnings,
            MetricaBase.ModelWarning(
                :extreme_quantile,
                "极端分位点",
                "τ 接近 0 或 1 时，系数与标准误的渐近近似可能不稳定，小样本下尤甚。",
                "可尝试更居中的分位点或增大样本。",
                MetricaBase.info,
            ),
        )
    end

    qm = try
        qreg(model_formula, filtered_dataset, τ, IP())
    catch err
        return MetricaBase.ModelError(
            :quantile_fit_failed,
            "分位数回归拟合失败",
            "QuantileRegressions 内点求解失败：$(sprint(showerror, err))",
            "请检查设计矩阵是否病态或响应变量是否常数。",
        )
    end

    β = Float64.(StatsAPI.coef(qm))
    vcov_m = try
        Float64.(StatsAPI.vcov(qm.model))
    catch
        zeros(ncoef, ncoef)
    end
    se_raw = try
        Float64.(StatsAPI.stderror(qm.model))
    catch
        fill(NaN, length(β))
    end

    cnames = Symbol.(coefnames(qm))
    if length(cnames) != length(β)
        cnames = [Symbol("x$i") for i in eachindex(β)]
    end

    stderror_values = Union{Nothing, Float64}[]
    for s in se_raw
        push!(stderror_values, (!isnan(s) && isfinite(s) && s >= 0) ? s : nothing)
    end
    if any(isnothing, stderror_values)
        push!(
            warnings,
            MetricaBase.ModelWarning(
                :quantile_se_unavailable,
                "部分标准误不可用",
                "核密度或 Hall–Sheather 带宽在残差上数值不稳定，已省略对应标准误与检验量。",
                "可尝试更居中分位点、检查共线或增大样本。",
                MetricaBase.warning,
            ),
        )
    end

    dof = nobs - ncoef
    z_crit = quantile(Normal(), 0.975)
    tidy_rows = MetricaBase.CoefRow[]
    for i in eachindex(β)
        sev = stderror_values[i]
        est = β[i]
        if sev === nothing
            push!(tidy_rows, MetricaBase.CoefRow(cnames[i], est, nothing, nothing, nothing, nothing, nothing))
        else
            z = est / sev
            pv = 2 * (1 - cdf(Normal(), abs(z)))
            push!(
                tidy_rows,
                MetricaBase.CoefRow(
                    cnames[i], est, sev, z, pv,
                    est - z_crit * sev, est + z_crit * sev,
                ),
            )
        end
    end

    fitted_values = X * β
    residuals = y - fitted_values
    pr2 = _pseudo_r2_mc_fadden(y, X, β, τ)
    metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :tau => τ,
        :pseudo_r2 => pr2 === nothing ? 0.0 : Float64(pr2),
    )

    rX = rank(X)
    cX = try
        Float64(cond(X))
    catch
        NaN
    end

    diagnostics = Dict{Symbol, Any}(
        :tau => τ,
        :inference_kind => "asymptotic_kernel",
        :pseudo_r2_definition => "1 - sum(check_loss(full)) / sum(check_loss(null)); null 为 y 在 τ 处的无条件分位数。",
        :rank_X => rX,
        :cond_X => cX,
        :solver => "QuantileRegressions.IP",
    )

    glance_table = MetricaBase.ModelGlance(:quantile, nobs, dof, metrics, warnings)
    tidy_table = MetricaBase.TidyTable(tidy_rows, "asymptotic_kernel")

    return QuantileFitResult(
        String(formula),
        glance_table,
        tidy_table,
        τ,
        X,
        y,
        cnames,
        β,
        vcov_m,
        stderror_values,
        fitted_values,
        residuals,
        diagnostics,
    )
end

MetricaBase.glance(r::QuantileFitResult) = r.glance_table
MetricaBase.tidy(r::QuantileFitResult) = r.tidy_table
MetricaBase.coef(r::QuantileFitResult) = r.coefficient_names .=> r.coefficients
MetricaBase.vcov(r::QuantileFitResult) = r.vcov_matrix
MetricaBase.stderror(r::QuantileFitResult) = r.stderror_values
MetricaBase.nobs(r::QuantileFitResult) = length(r.y)
MetricaBase.dof(r::QuantileFitResult) = length(r.y) - length(r.coefficient_names)
MetricaBase.fitted(r::QuantileFitResult) = r.fitted_values
MetricaBase.residuals(r::QuantileFitResult) = r.residuals

function MetricaBase.augment(r::QuantileFitResult)
    n = length(r.y)
    return MetricaBase.AugmentTable(
        Dict(
            :observation => collect(1.0:n),
            :fitted => r.fitted_values,
            :residual => r.residuals,
        ),
        n,
    )
end

# === 多 τ 分位数回归 ==========================================================
function fit_multi_tau(data, formula, taus::Vector{Float64})
    results = QuantileFitResult[]
    for tau in taus
        r = MetricaBase.fit(QuantileModel, formula, data; quantile_tau=tau)
        r isa MetricaBase.ModelError && return r
        push\!(results, r)
    end
    return results
end

# === Bootstrap SE（pairs bootstrap）==========================================
function bootstrap_quantile_se(data, formula, tau::Float64; n_boot::Int=200, seed::Int=42)
    Random.seed\!(seed); n = nrow(data)
    beta_boot = Matrix{Float64}(undef, n_boot, 0)
    for b in 1:n_boot
        idx = rand(1:n, n); boot_df = data[idx, :]
        r = MetricaBase.fit(QuantileModel, formula, boot_df; quantile_tau=tau)
        r isa MetricaBase.ModelError && continue
        if b == 1; beta_boot = Matrix{Float64}(undef, n_boot, length(r.coefficients)); end
        beta_boot[b, :] = r.coefficients
    end
    se_boot = [std(beta_boot[:, j]) for j in 1:size(beta_boot, 2)]
    return se_boot
end

# === Rank Score 推断 ==========================================================
function rank_score_test(r::QuantileFitResult, restricted_beta::Vector{Float64}, restricted_indices::Vector{Int})
    n = length(r.y); tau = r.tau
    signs = (r.y .- r.X * restricted_beta) .> 0
    a = signs .- tau
    S = r.X' * a / sqrt(n)
    V_inv = inv(Symmetric(r.vcov_matrix))
    T = n * dot(S, V_inv * S)
    pv = 1 - cdf(Chisq(length(restricted_indices)), T)
    return Dict{Symbol, Any}(:statistic => T, :pvalue => pv, :dof => length(restricted_indices), :method => "Rank Score")
end

# === Sparsity 推断 ============================================================
function sparsity_inference(r::QuantileFitResult)
    tau = r.tau; n = length(r.y)
    h = max(1.0, n^(1/3) * (1.5 * (quantile(Normal(), 0.75) - quantile(Normal(), 0.25)) / 1.349)^(2/3))
    f_hat = 2 * h / (max(sum(abs.(r.residuals) .< h), 1))
    s_tau = 1.0 / f_hat
    return Dict{Symbol, Any}(:sparsity => s_tau, :bandwidth => h, :method => "Hall-Sheather")
end

# === IV Quantile (2SLS 型) ====================================================
function fit_iv_quantile(data, formula::String, instruments::Vector{String}, endog::Vector{String}, tau::Float64)
    Z = Matrix{Float64}(hcat([data[\!, Symbol(c)] for c in instruments]...))
    X_endo = Matrix{Float64}(hcat([data[\!, Symbol(c)] for c in endog]...))
    ZtZ_inv = inv(Symmetric(Z' * Z + 1e-10 * I))
    X_hat = Z * ZtZ_inv * (Z' * X_endo)
    X_exog_cols = setdiff(Symbol.(names(data)), vcat(Symbol(endog), Symbol(formula[1])))
    X_exog = isempty(X_exog_cols) ? ones(nrow(data)) : Matrix{Float64}(hcat([data[\!, c] for c in X_exog_cols]...))
    X_all = hcat(X_exog, X_hat)
    data_aug = hcat(DataFrame(y = data[\!, Symbol(split(formula, "~")[1])]), DataFrame(X_all, :auto))
    return MetricaBase.fit(QuantileModel, "y ~ x1", data_aug; quantile_tau=tau)
end
