# === Survey OLS：Taylor 线性化方差估计 ==========================================

function MetricaBase.fit(
    ::Type{SurveyOLSModel}, formula::AbstractString, data;
    weights_column::Union{Symbol,String,Nothing}=nothing,
    strata_column::Union{Nothing,Symbol,String}=nothing,
    psu_column::Union{Nothing,Symbol,String}=nothing,
    fpc_column::Union{Nothing,Symbol,String}=nothing,
    kwargs...,
)
    # 归一化 Symbol
    wc = isnothing(weights_column) ? nothing : Symbol(weights_column)
    sc = isnothing(strata_column) ? nothing : Symbol(strata_column)
    pc = isnothing(psu_column) ? nothing : Symbol(psu_column)
    fc = isnothing(fpc_column) ? nothing : Symbol(fpc_column)

    isnothing(wc) && return MetricaBase.ModelError(
        :missing_weights_column,
        "缺少抽样权重列",
        "Survey OLS 需要指定 weights_column。",
        "请提供抽样权重列名。",
    )

    # 加载数据
    dataset = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    # 解析公式获取模型列
    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula
    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    # 确定需要检查缺失值的列
    required_columns = Symbol[wc]  # 权重列
    if !isnothing(sc)
        push!(required_columns, sc)
    end
    if !isnothing(pc)
        push!(required_columns, pc)
    end
    if !isnothing(fc)
        push!(required_columns, fc)
    end
    # 添加公式中的列
    for col in model_columns
        push!(required_columns, col)
    end
    required_columns = unique(required_columns)

    # 过滤数据集，只保留相关列中没有缺失值的行
    filtered_dataset = dataset[completecases(dataset[:, required_columns]), :]
    nrow(filtered_dataset) > 0 || return MetricaBase.ModelError(
        :empty_effective_sample,
        "有效样本为空",
        "在模型相关列完成缺失值删除后，没有剩余观测可用于拟合。",
        "请检查响应变量与解释变量中的缺失情况。",
    )

    # 构造 SurveyDesign（使用过滤后的数据集）
    design = SurveyDesign(filtered_dataset, wc; strata_column=sc, psu_column=pc, fpc_column=fc)
    design isa MetricaBase.ModelError && return design

    # 用抽样权重做 WLS 获取点估计（使用过滤后的数据集）
    ols_result = MetricaBase.fit(OLSModel, formula, filtered_dataset; weights=wc, vcov=:classical)
    ols_result isa MetricaBase.ModelError && return ols_result

    # 提取所需数据
    X = ols_result.design_matrix
    residuals = ols_result.residual_vector
    coef_vals = ols_result.coefficient_values
    coef_names = ols_result.coefficient_names
    ncoef = length(coef_vals)
    nobs = length(residuals)
    w = filtered_dataset[1:nobs, wc]

    # 计算 Taylor 线性化 Sandwich 方差
    survey_vcov = taylor_linearization_vcov(X, residuals, w, design)
    survey_se = sqrt.(max.(diag(survey_vcov), 0.0))

    # 计算 DEFF
    srs_vcov = ols_result.vcov_matrix
    deff, n_eff = compute_deff(survey_vcov, srs_vcov, nobs)

    # 计算 z 统计量与 p 值
    z_stats = coef_vals ./ survey_se
    z_stats[survey_se .< 1e-16] .= 0.0
    pvalues = 2 .* (1 .- cdf.(Normal(), abs.(z_stats)))

    # Survey-adjusted Wald F 检验（排除截距）
    coef_no_intercept = coef_vals[2:end]
    vcov_no_intercept = survey_vcov[2:end, 2:end]
    k = length(coef_no_intercept)
    dof_residual = nobs - ncoef
    wald_f = k > 0 ? (coef_no_intercept' * inv(vcov_no_intercept) * coef_no_intercept) / k : 0.0
    wald_pvalue = k > 0 && dof_residual > 0 ? 1 - cdf(FDist(k, dof_residual), wald_f) : 1.0

    # 构建 glance
    glance = ols_result.glance_table
    survey_glance = MetricaBase.ModelGlance(
        Symbol("survey_$(glance.model)"),
        glance.nobs,
        glance.dof,
        merge(glance.metrics, Dict(:mean_deff => mean(deff), :wald_f => wald_f, :wald_pvalue => wald_pvalue)),
        glance.warnings,
    )

    # 构建 tidy（使用 survey 修正 SE）
    z_crit = quantile(Normal(), 0.975)
    tidy_rows = MetricaBase.CoefRow[
        MetricaBase.CoefRow(coef_names[i], coef_vals[i], survey_se[i], z_stats[i], pvalues[i],
            coef_vals[i] - z_crit * survey_se[i], coef_vals[i] + z_crit * survey_se[i])
        for i in 1:ncoef
    ]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "z")

    return SurveyOLSFitResult(
        String(formula), survey_glance, tidy_table,
        ols_result, survey_vcov, survey_se, deff, n_eff,
        coef_names, coef_vals,
    )
end

# === Protocol 方法委托 ===========================================================

MetricaBase.glance(r::SurveyOLSFitResult) = r.glance_table
MetricaBase.tidy(r::SurveyOLSFitResult) = r.tidy_table
MetricaBase.coef(r::SurveyOLSFitResult) = r.coefficient_values
MetricaBase.vcov(r::SurveyOLSFitResult) = r.survey_vcov
MetricaBase.stderror(r::SurveyOLSFitResult) = r.survey_se
MetricaBase.nobs(r::SurveyOLSFitResult) = r.glance_table.nobs
MetricaBase.dof(r::SurveyOLSFitResult) = r.glance_table.dof
MetricaBase.fitted(r::SurveyOLSFitResult) = MetricaBase.fitted(r.ols_result)
MetricaBase.residuals(r::SurveyOLSFitResult) = MetricaBase.residuals(r.ols_result)
MetricaBase.augment(r::SurveyOLSFitResult) = MetricaBase.augment(r.ols_result)
