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

    # 构造 SurveyDesign
    design = SurveyDesign(dataset, wc; strata_column=sc, psu_column=pc, fpc_column=fc)
    design isa MetricaBase.ModelError && return design

    # 用抽样权重做 WLS 获取点估计
    ols_result = MetricaBase.fit(OLSModel, formula, dataset; weights=wc, vcov=:classical)
    ols_result isa MetricaBase.ModelError && return ols_result

    # 提取所需数据
    X = ols_result.design_matrix
    residuals = ols_result.residual_vector
    coef_vals = ols_result.coefficient_values
    coef_names = ols_result.coefficient_names
    ncoef = length(coef_vals)
    nobs = length(residuals)
    w = dataset[1:nobs, wc]

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

    # 构建 glance
    glance = ols_result.glance_table
    survey_glance = MetricaBase.ModelGlance(
        Symbol("survey_$(glance.model)"),
        glance.nobs,
        glance.dof,
        merge(glance.metrics, Dict(:mean_deff => mean(deff))),
        glance.warnings,
    )

    # 构建 tidy（使用 survey 修正 SE）
    tidy_rows = MetricaBase.CoefRow[
        MetricaBase.CoefRow(coef_names[i], coef_vals[i], survey_se[i], z_stats[i], pvalues[i])
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
