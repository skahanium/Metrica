# === 面板诊断 ===============================================================

function _parse_panel_formula(formula::String)
    response_name, predictor_names = MetricaBase.parse_metrica_formula(formula)
    return Symbol(response_name), Symbol.(predictor_names)
end

function _panel_design(panel_data::MetricaBase.PanelData, formula::String)
    df = DataFrame(panel_data.data)
    response_name, predictor_names = _parse_panel_formula(formula)
    y = Float64.(df[!, response_name])
    X = hcat([Float64.(df[!, name]) for name in predictor_names]...)
    X_design = hcat(ones(length(y)), X)
    coef_names = vcat([:intercept], predictor_names)
    return (; df, y, X, X_design, coef_names, response_name, predictor_names)
end

function _coef_lookup(result::PanelFitResult)
    table = MetricaBase.tidy(result)
    return Dict(row.name => row for row in table.rows)
end

function _diagnostic_unavailable(reason::String; method::String)
    return Dict(
        "available" => false,
        "statistic" => nothing,
        "pvalue" => nothing,
        "dof" => nothing,
        "method" => method,
        "note" => reason,
    )
end

"""
    hausman(fe_result, re_result)

比较 FE 与 Mundlak/CRE 的共同斜率系数，返回 Hausman 检验载荷。

**计算方式：** 使用对角近似（`Var(β_FE) - Var(β_RE)` 的对角元素），
而非完整协方差矩阵差值。当完整 vcov 矩阵不可用时，此近似是必要的。

**语义说明：** `re_result` 实际为 Mundlak/CRE（非传统 GLS-RE），
因此此检验比较的是 FE 与 CRE 的系数一致性，而非传统 FE vs RE。
"""
function hausman(fe_result::PanelFitResult, re_result::PanelFitResult)
    fe_rows = _coef_lookup(fe_result)
    re_rows = _coef_lookup(re_result)
    common_names = Symbol[]

    for name in fe_result.coefficient_names
        name === :intercept && continue
        startswith(String(name), "group_mean_") && continue
        haskey(re_rows, name) && push!(common_names, name)
    end

    if isempty(common_names)
        return _diagnostic_unavailable(
            "FE 与 RE 没有可比较的共同斜率系数。";
            method="hausman_fe_re_v2",
        )
    end

    # 提取共同系数和值
    k = length(common_names)
    beta_diff = zeros(k)
    fe_se = zeros(k)
    re_se = zeros(k)

    for (i, name) in enumerate(common_names)
        fe_row = fe_rows[name]
        re_row = re_rows[name]
        beta_diff[i] = fe_row.estimate - re_row.estimate
        fe_se[i] = something(fe_row.stderror, 0.0)
        re_se[i] = something(re_row.stderror, 0.0)
    end

    # 对角近似：Var(β_FE) - Var(β_RE) 的对角元素
    # 注：完整协方差矩阵差值需要完整 vcov，此处使用对角近似
    var_diff = fe_se .^ 2 .- re_se .^ 2

    # 检查正定性
    if any(v -> !isfinite(v) || v <= sqrt(eps(Float64)), var_diff)
        # 回退到对角近似，跳过非正定项
        valid = [i for i in 1:k if isfinite(var_diff[i]) && var_diff[i] > sqrt(eps(Float64))]
        if isempty(valid)
            return _diagnostic_unavailable(
                "FE/RE 方差差非正定，无法计算 Hausman 检验。";
                method="hausman_fe_re_v2",
            )
        end
        beta_diff = beta_diff[valid]
        var_diff = var_diff[valid]
        k = length(valid)
    end

    # H = (β_FE - β_RE)' * [Var(β_FE) - Var(β_RE)]^{-1} * (β_FE - β_RE)
    # 对角近似下简化为 Σ (Δβ_i)^2 / ΔVar_i
    statistic = sum(beta_diff .^ 2 ./ var_diff)
    pvalue = 1 - cdf(Chisq(k), statistic)

    return Dict(
        "available" => true,
        "statistic" => statistic,
        "pvalue" => pvalue,
        "dof" => k,
        "method" => "hausman_fe_re_v2",
        "note" => "H0: CRE 估计量一致；p 值较小说明更倾向 FE。使用对角近似（非完整协方差矩阵）。比较对象为 Mundlak/CRE，非传统 GLS-RE。",
    )
end

"""
    fixed_effect_f(panel_data, formula)

检验个体固定效应整体显著性：比较 pooled OLS 与 FE 的残差平方和。
"""
function fixed_effect_f(panel_data::MetricaBase.PanelData, formula::String)
    design = _panel_design(panel_data, formula)
    df = design.df
    id_col = panel_data.id_col
    unique_ids = unique(df[!, id_col])
    n_ids = length(unique_ids)
    nobs = length(design.y)
    k_slopes = length(design.predictor_names)

    pooled_stats = ols_statistics(
        Matrix{Float64}(design.X_design),
        design.y,
        design.coef_names,
        :pooled,
        Dict{Symbol, MetricaBase.MetricValue}(:n_ids => n_ids),
    )
    fe_result = fit_fe(panel_data, formula)
    rss_pooled = sum(abs2, pooled_stats.residuals)
    rss_fe = sum(abs2, fe_result.residual_vector)
    df_num = n_ids - 1
    df_den = nobs - n_ids - k_slopes

    if df_num <= 0 || df_den <= 0 || rss_fe <= 0
        return _diagnostic_unavailable(
            "样本量或自由度不足，无法计算固定效应 F 检验。";
            method="pooled_vs_fe_f",
        )
    end

    statistic = ((rss_pooled - rss_fe) / df_num) / (rss_fe / df_den)
    statistic = max(statistic, 0.0)
    pvalue = 1 - cdf(FDist(df_num, df_den), statistic)

    return Dict(
        "available" => true,
        "statistic" => statistic,
        "pvalue" => pvalue,
        "df_num" => df_num,
        "df_den" => df_den,
        "method" => "pooled_vs_fe_f",
        "note" => "H0: 个体固定效应整体不显著。",
    )
end

function _balanced_panel_shape(df::DataFrame, id_col::Symbol, time_col::Symbol)
    counts = combine(groupby(df, id_col), nrow => :nobs)
    unique_counts = unique(counts.nobs)
    n_times = length(unique(df[!, time_col]))
    is_balanced = length(unique_counts) == 1 && first(unique_counts) == n_times
    return (; is_balanced, n_ids=nrow(counts), n_times)
end

"""
    breusch_pagan_lm(panel_data, formula)

Breusch-Pagan 随机效应 LM 检验。支持平衡和不平衡面板。
"""
function breusch_pagan_lm(panel_data::MetricaBase.PanelData, formula::String)
    design = _panel_design(panel_data, formula)
    df = design.df
    shape = _balanced_panel_shape(df, panel_data.id_col, panel_data.time_col)

    pooled_stats = ols_statistics(
        Matrix{Float64}(design.X_design),
        design.y,
        design.coef_names,
        :pooled,
        Dict{Symbol, MetricaBase.MetricValue}(:n_ids => shape.n_ids),
    )
    residuals = pooled_stats.residuals
    total_ss = sum(abs2, residuals)
    total_ss <= 0 && return _diagnostic_unavailable(
        "pooled OLS 残差平方和为零，无法计算随机效应 LM 检验。";
        method="breusch_pagan_re_lm",
    )

    grouped = groupby(DataFrame(id=df[!, panel_data.id_col], residual=residuals), :id)
    group_sums = [sum(group.residual) for group in grouped]
    group_sizes = [nrow(group) for group in grouped]
    N = length(residuals)
    n_groups = length(group_sums)

    # 通用 BP LM 公式（支持不平衡面板）
    # LM = (N^2 / (2 * Σ T_i^2)) * (Σ e_i)^2 / Σ e_{it}^2 - 1)^2
    # 简化：使用组内和的平方
    sum_sq_groups = sum(s^2 for s in group_sums)
    T_bar = N / n_groups  # 平均组大小

    # BP 统计量
    ratio = sum_sq_groups / total_ss
    if shape.is_balanced
        T_i = shape.n_times
        statistic = n_groups * T_i / (2 * (T_i - 1)) * (ratio - 1)^2
    else
        # 不平衡面板：使用 Searle 公式
        sum_T_sq = sum(s^2 for s in group_sizes)
        T_star = (N - sum_T_sq / N) / (n_groups - 1)
        statistic = n_groups * T_star / (2 * (T_star - 1)) * (ratio - 1)^2
    end
    statistic = max(statistic, 0.0)
    pvalue = 1 - cdf(Chisq(1), statistic)

    return Dict(
        "available" => true,
        "statistic" => statistic,
        "pvalue" => pvalue,
        "dof" => 1,
        "method" => "breusch_pagan_re_lm",
        "note" => shape.is_balanced ?
            "H0: 随机效应方差为 0，pooled OLS 足够。" :
            "H0: 随机效应方差为 0。不平衡面板 BP 为近似检验。",
    )
end

"""
    panel_diagnostics(panel_data, formula)

返回面板模型的结构化诊断载荷，用于 Runtime 与 App 消费。

Hausman 检验比较 FE 与 Mundlak/CRE（非传统 GLS-RE）的系数一致性。
"""
function panel_diagnostics(panel_data::MetricaBase.PanelData, formula::String)
    fe_result = fit_fe(panel_data, formula)
    re_result = fit_re(panel_data, formula)

    return Dict(
        "hausman" => hausman(fe_result, re_result),
        "fixed_effect_f" => fixed_effect_f(panel_data, formula),
        "breusch_pagan_lm" => breusch_pagan_lm(panel_data, formula),
    )
end
