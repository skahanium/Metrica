# === 面板 IV 估计器 ===========================================================
# 统一使用 StatsModels 公式

struct PanelIVModel <: MetricaBase.AbstractPanelModel
    formula::String
    instruments::Vector{String}
    endog::Vector{String}
    id_col::Symbol
    time_col::Symbol
end

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

function fit_panel_iv(panel_data::MetricaBase.PanelData, formula::String;
                      instruments::Vector{String}, endog::Vector{String})
    data = DataFrame(panel_data.data)
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    unique_ids = unique(data[!, id_col])
    unique_times = unique(data[!, time_col])
    n_ids = length(unique_ids)
    n_times = length(unique_times)

    # StatsModels 公式解析
    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula
    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    prepared = MetricaLinear.prepare_model_data(data, model_formula, model_columns, nothing, nothing)
    prepared isa MetricaBase.ModelError && return prepared
    (_, model_frame, _, X, y, _, _, _, _) = prepared

    nobs = length(y)
    base_names = Symbol.(coefnames(model_frame))
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

    # 分离外生 / 内生列位置
    exog_names = [name for name in base_names if name ∉ endog_syms]
    endog_in_base = [name for name in base_names if name in endog_syms]
    exog_idx = [findfirst(==(name), base_names) for name in exog_names]
    endog_idx = [findfirst(==(name), base_names) for name in endog_in_base]

    X_exog = X[:, exog_idx]
    X_endog = X[:, endog_idx]
    Z_inst = hcat([Float64.(data[!, iv]) for iv in inst_syms]...)
    Z = hcat(X_exog, Z_inst)

    # 第一阶段
    Pi = Z \ X_endog
    X_endog_hat = Z * Pi

    # 第一阶段 F 统计
    first_stage_stats = Dict{Symbol, Float64}()
    weak_warnings = MetricaBase.ModelWarning[]
    k_inst = length(inst_syms)
    k_exog = length(exog_idx)

    for (idx, ev) in enumerate(endog_in_base)
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

    coef_names = Symbol.(vcat(string.(exog_names), string.(endog_in_base)))
    ncoef = length(coefficients)
    dof_val = nobs - ncoef
    sigma2 = sum(abs2, residuals) / dof_val
    XtX_inv = inv(X_second' * X_second)
    vcov_mat = sigma2 * XtX_inv
    se = sqrt.(diag(vcov_mat))

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
