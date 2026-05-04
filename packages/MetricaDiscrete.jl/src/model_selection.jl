# === 模型选择 =================================================================

struct LRTestResult
    statistic::Float64
    pvalue::Float64
    dof_diff::Int
    model_full::Symbol
    model_reduced::Symbol
    significant::Bool
end

"""
    lr_test(full_result, reduced_result)

似然比检验：比较嵌套模型的拟合优度。
H₀: 简化模型足够。LR = -2*(ℓ_reduced - ℓ_full) ~ χ²(dof_diff)。
"""
function lr_test(
    full_result::AbstractDiscreteFitResult,
    reduced_result::AbstractDiscreteFitResult,
)
    ll_full = full_result.loglikelihood
    ll_reduced = reduced_result.loglikelihood
    dof_full = length(full_result.coefficient_names)
    dof_reduced = length(reduced_result.coefficient_names)

    dof_diff = dof_full - dof_reduced
    if dof_diff <= 0
        throw(ArgumentError("完整模型的参数个数必须大于简化模型。"))
    end

    lr_stat = 2 * (ll_full - ll_reduced)
    pvalue = 1.0 - cdf(Chisq(dof_diff), lr_stat)

    return LRTestResult(
        lr_stat, pvalue, dof_diff,
        Symbol(full_result.glance_table.model),
        Symbol(reduced_result.glance_table.model),
        pvalue < 0.05,
    )
end

struct ModelComparison
    models::Vector{Dict{Symbol, Any}}
    best_by_aic::Symbol
    best_by_bic::Symbol
end

"""
    compare_aic_bic(models::Dict{Symbol, <:AbstractDiscreteFitResult})

对多个模型按 AIC 和 BIC 排序，返回比较结果。
"""
function compare_aic_bic(models::Dict{Symbol, <:AbstractDiscreteFitResult})
    entries = []
    for (name, result) in models
        push!(entries, Dict(
            :model => name,
            :nobs => length(result.response_vector),
            :dof => length(result.coefficient_names),
            :loglik => result.loglikelihood,
            :aic => result.glance_table.metrics[:aic],
            :bic => result.glance_table.metrics[:bic],
        ))
    end

    sort!(entries, by=e -> e[:aic])
    best_by_aic = entries[1][:model]

    sorted_bic = sort(entries, by=e -> e[:bic])
    best_by_bic = sorted_bic[1][:model]

    return ModelComparison(entries, best_by_aic, best_by_bic)
end
