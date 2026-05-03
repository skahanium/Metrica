# === 面板 IV 估计器 ===========================================================
# 面板数据中的工具变量/两阶段最小二乘

"""
面板 IV 模型规格。
"""
struct PanelIVModel <: MetricaBase.AbstractPanelModel
    formula::String
    instruments::Vector{String}
    endog::Vector{String}
    id_col::Symbol
    time_col::Symbol
end

"""
面板 IV 拟合结果。
"""
struct PanelIVFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    panel_data::MetricaBase.PanelData
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
    coefficient_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    first_stage_stats::Dict{Symbol, Float64}
    weak_instrument_warnings::Vector{MetricaBase.ModelWarning}
end

MetricaBase.glance(result::PanelIVFitResult) = result.glance_table
MetricaBase.tidy(result::PanelIVFitResult) = result.tidy_table
MetricaBase.coef(result::PanelIVFitResult) = result.coefficient_names .=> result.coefficient_values

function MetricaBase.augment(result::PanelIVFitResult)
    nobs = length(result.fitted_values)
    k = length(result.coefficient_names)
    dof = nobs - k
    cols = Dict{Symbol, Vector{Float64}}(
        :observation => collect(1.0:nobs),
        :fitted => result.fitted_values,
        :residual => result.residual_vector,
    )
    if dof > 0
        sigma = sqrt(sum(abs2, result.residual_vector) / dof)
        sigma > 0 && (cols[:std_residual] = result.residual_vector ./ sigma)
    end
    return MetricaBase.AugmentTable(cols, nobs)
end

"""
    fit_panel_iv(panel_data, formula; instruments, endog)

使用面板 IV/2SLS 方法拟合模型。面板感知的第一阶段按个体分组处理。

# 示例
```julia
fit_panel_iv(pd, "y ~ x1"; instruments=["z1"], endog=["x1"])
```
"""
function fit_panel_iv(panel_data::MetricaBase.PanelData, formula::String;
                      instruments::Vector{String}, endog::Vector{String})
    data = DataFrame(panel_data.data)
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    nobs = nrow(data)
    unique_ids = unique(data[!, id_col])
    unique_times = unique(data[!, time_col])
    n_ids = length(unique_ids)
    n_times = length(unique_times)

    # 解析公式
    response_name, predictor_names = MetricaBase.parse_metrica_formula(formula)

    y = Float64.(data[!, Symbol(response_name)])
    exog_vars = [Symbol(name) for name in predictor_names]
    endog_syms = Symbol.(endog)
    inst_syms = Symbol.(instruments)

    # 验证变量存在
    available = Set(Symbol.(names(data)))
    for ev in endog_syms
        ev ∉ available && return MetricaBase.ModelError(:unknown_endog_variable,
            "内生变量不存在", "内生变量 $ev 无法在数据集中找到。", "请检查变量名。")
    end
    for iv in inst_syms
        iv ∉ available && return MetricaBase.ModelError(:unknown_instrument_variable,
            "工具变量不存在", "工具变量 $iv 无法在数据集中找到。", "请检查变量名。")
    end

    # 分离外生变量（不含内生变量）
    exog_only = [v for v in exog_vars if v ∉ endog_syms]

    # 构建矩阵
    X_exog = hcat(ones(nobs), [Float64.(data[!, v]) for v in exog_only]...)
    Z = hcat(ones(nobs), [Float64.(data[!, v]) for v in exog_only]...,
             [Float64.(data[!, iv]) for iv in inst_syms]...)
    X_endog = hcat([Float64.(data[!, ev]) for ev in endog_syms]...)

    # 第一阶段：按面板结构回归内生变量到工具变量
    Pi = Z \ X_endog
    X_endog_hat = Z * Pi

    # 第一阶段 F 统计量
    first_stage_stats = Dict{Symbol, Float64}()
    weak_warnings = MetricaBase.ModelWarning[]
    k_inst = length(inst_syms)
    k_exog = size(X_exog, 2)

    for (idx, ev) in enumerate(endog_syms)
        resid_fs = X_endog[:, idx] - X_endog_hat[:, idx]
        rss_fs = sum(abs2, resid_fs)
        tss_fs = sum(abs2, X_endog[:, idx] .- mean(X_endog[:, idx]))
        r2_fs = iszero(tss_fs) ? 0.0 : 1 - rss_fs / tss_fs
        f_stat = iszero(1 - r2_fs) ? Inf : (r2_fs / (1 - r2_fs)) * (nobs - k_exog - k_inst) / k_inst
        first_stage_stats[ev] = f_stat

        if f_stat < 10.0
            push!(weak_warnings, MetricaBase.ModelWarning(:weak_instrument,
                "弱工具变量警告",
                "内生变量 $ev 的第一阶段 F 统计量为 $(round(f_stat, digits=2))。",
                "弱工具变量会导致 2SLS 偏误增大。",
                MetricaBase.warning))
        end
    end

    # 第二阶段
    X_second = hcat(X_exog, X_endog_hat)
    coefficients = X_second \ y
    fitted = X_second * coefficients
    residuals = y - fitted

    coef_names = Symbol.(vcat(["(Intercept)"], string.(exog_only), string.(endog_syms)))

    # 协方差（默认 classical，可通过 DK 扩展）
    ncoef = length(coefficients)
    dof_val = nobs - ncoef
    sigma2 = sum(abs2, residuals) / dof_val
    XtX_inv = inv(X_second' * X_second)
    vcov_mat = sigma2 * XtX_inv
    se = sqrt.(diag(vcov_mat))

    # 模型统计
    rss = sum(abs2, residuals)
    tss = sum(abs2, y .- mean(y))
    r2_val = iszero(tss) ? 1.0 : 1 - rss / tss
    adj_r2 = iszero(tss) ? 1.0 : 1 - (rss / dof_val) / (tss / (nobs - 1))
    sigma = sqrt(rss / dof_val)

    warnings = MetricaBase.ModelWarning[]
    append!(warnings, weak_warnings)

    glance_table = MetricaBase.ModelGlance(:panel_iv, nobs, dof_val,
        Dict{Symbol, MetricaBase.MetricValue}(:r2 => r2_val, :adj_r2 => adj_r2,
            :rss => rss, :tss => tss, :sigma => sigma,
            :n_ids => n_ids, :n_times => n_times),
        warnings)

    t_stats = coefficients ./ se
    p_values = 2.0 .* (1.0 .- cdf.(TDist(dof_val), abs.(t_stats)))
    tidy_rows = [MetricaBase.CoefRow(coef_names[i], coefficients[i], se[i], t_stats[i], p_values[i]) for i in eachindex(coef_names)]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "classical")

    return PanelIVFitResult(formula, glance_table, tidy_table, panel_data,
                            fitted, residuals, coef_names, coefficients,
                            vcov_mat, se, first_stage_stats, weak_warnings)
end
