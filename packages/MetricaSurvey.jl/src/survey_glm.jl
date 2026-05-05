# === Survey GLM：Logit / Probit / Poisson 设计效应修正方差 ========================

# ---- Survey Logit -------------------------------------------------------------

function MetricaBase.fit(
    ::Type{SurveyLogitModel}, formula::AbstractString, data;
    weights_column::Union{Symbol,String,Nothing}=nothing,
    strata_column::Union{Nothing,Symbol,String}=nothing,
    psu_column::Union{Nothing,Symbol,String}=nothing,
    fpc_column::Union{Nothing,Symbol,String}=nothing,
    kwargs...,
)
    wc = isnothing(weights_column) ? nothing : Symbol(weights_column)
    sc = isnothing(strata_column) ? nothing : Symbol(strata_column)
    pc = isnothing(psu_column) ? nothing : Symbol(psu_column)
    fc = isnothing(fpc_column) ? nothing : Symbol(fpc_column)

    isnothing(wc) && return MetricaBase.ModelError(
        :missing_weights_column,
        "缺少抽样权重列",
        "Survey Logit 需要指定 weights_column。",
        "请提供抽样权重列名。",
    )

    dataset = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    design = SurveyDesign(dataset, wc; strata_column=sc, psu_column=pc, fpc_column=fc)
    design isa MetricaBase.ModelError && return design

    # 用 MetricaDiscrete 拟合 Logit 获取点估计
    discrete_result = MetricaBase.fit(LogitModel, formula, dataset)
    discrete_result isa MetricaBase.ModelError && return discrete_result

    build_survey_glm_result(
        SurveyLogitFitResult, discrete_result, formula, dataset, design, wc,
    )
end

# ---- Survey Probit ------------------------------------------------------------

function MetricaBase.fit(
    ::Type{SurveyProbitModel}, formula::AbstractString, data;
    weights_column::Union{Symbol,String,Nothing}=nothing,
    strata_column::Union{Nothing,Symbol,String}=nothing,
    psu_column::Union{Nothing,Symbol,String}=nothing,
    fpc_column::Union{Nothing,Symbol,String}=nothing,
    kwargs...,
)
    wc = isnothing(weights_column) ? nothing : Symbol(weights_column)
    sc = isnothing(strata_column) ? nothing : Symbol(strata_column)
    pc = isnothing(psu_column) ? nothing : Symbol(psu_column)
    fc = isnothing(fpc_column) ? nothing : Symbol(fpc_column)

    isnothing(wc) && return MetricaBase.ModelError(
        :missing_weights_column,
        "缺少抽样权重列",
        "Survey Probit 需要指定 weights_column。",
        "请提供抽样权重列名。",
    )

    dataset = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    design = SurveyDesign(dataset, wc; strata_column=sc, psu_column=pc, fpc_column=fc)
    design isa MetricaBase.ModelError && return design

    discrete_result = MetricaBase.fit(ProbitModel, formula, dataset)
    discrete_result isa MetricaBase.ModelError && return discrete_result

    build_survey_glm_result(
        SurveyProbitFitResult, discrete_result, formula, dataset, design, wc,
    )
end

# ---- Survey Poisson -----------------------------------------------------------

function MetricaBase.fit(
    ::Type{SurveyPoissonModel}, formula::AbstractString, data;
    weights_column::Union{Symbol,String,Nothing}=nothing,
    strata_column::Union{Nothing,Symbol,String}=nothing,
    psu_column::Union{Nothing,Symbol,String}=nothing,
    fpc_column::Union{Nothing,Symbol,String}=nothing,
    kwargs...,
)
    wc = isnothing(weights_column) ? nothing : Symbol(weights_column)
    sc = isnothing(strata_column) ? nothing : Symbol(strata_column)
    pc = isnothing(psu_column) ? nothing : Symbol(psu_column)
    fc = isnothing(fpc_column) ? nothing : Symbol(fpc_column)

    isnothing(wc) && return MetricaBase.ModelError(
        :missing_weights_column,
        "缺少抽样权重列",
        "Survey Poisson 需要指定 weights_column。",
        "请提供抽样权重列名。",
    )

    dataset = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    design = SurveyDesign(dataset, wc; strata_column=sc, psu_column=pc, fpc_column=fc)
    design isa MetricaBase.ModelError && return design

    discrete_result = MetricaBase.fit(PoissonModel, formula, dataset)
    discrete_result isa MetricaBase.ModelError && return discrete_result

    build_survey_glm_result(
        SurveyPoissonFitResult, discrete_result, formula, dataset, design, wc,
    )
end

# === 共享的 GLM Survey 结果构建逻辑 ==============================================

function build_survey_glm_result(
    ResultT::Type,
    discrete_result,
    formula::AbstractString,
    dataset::DataFrame,
    design::SurveyDesign,
    weights_column::Symbol,
)
    X = discrete_result.design_matrix
    y = discrete_result.response_vector
    fitted = discrete_result.fitted_values
    ncoef = size(X, 2)
    nobs = length(y)

    # 响应残差: r_j = y_j - μ_j
    residuals = y - fitted

    w = dataset[1:nobs, weights_column]

    # Taylor 线性化 Sandwich 方差
    survey_vcov = taylor_linearization_vcov(X, residuals, w, design)
    survey_se = sqrt.(max.(diag(survey_vcov), 0.0))

    # 设计效应
    srs_vcov = discrete_result.vcov_matrix
    deff, n_eff = compute_deff(survey_vcov, srs_vcov, nobs)

    coef_vals = discrete_result.coefficient_values
    coef_names = discrete_result.coefficient_names

    # z 统计量
    z_stats = coef_vals ./ survey_se
    z_stats[survey_se .< 1e-16] .= 0.0
    pvalues = 2 .* (1 .- cdf.(Normal(), abs.(z_stats)))

    # Glance（扩展原有指标，附加 mean_deff）
    g = discrete_result.glance_table
    survey_glance = MetricaBase.ModelGlance(
        Symbol("survey_$(g.model)"),
        g.nobs, g.dof,
        merge(g.metrics, Dict(:mean_deff => mean(deff))),
        g.warnings,
    )

    # Tidy（使用 survey 修正 SE）
    tidy_rows = MetricaBase.CoefRow[
        MetricaBase.CoefRow(coef_names[i], coef_vals[i], survey_se[i], z_stats[i], pvalues[i])
        for i in 1:ncoef
    ]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "z")

    return ResultT(
        String(formula), survey_glance, tidy_table,
        discrete_result, survey_vcov, survey_se, deff, n_eff,
        coef_names, coef_vals,
    )
end

# === Protocol 方法委托（Survey GLM）==============================================

for RT in (:SurveyLogitFitResult, :SurveyProbitFitResult, :SurveyPoissonFitResult)
    @eval begin
        MetricaBase.glance(r::$RT) = r.glance_table
        MetricaBase.tidy(r::$RT) = r.tidy_table
        MetricaBase.coef(r::$RT) = r.coefficient_values
        MetricaBase.vcov(r::$RT) = r.survey_vcov
        MetricaBase.stderror(r::$RT) = r.survey_se
        MetricaBase.nobs(r::$RT) = r.glance_table.nobs
        MetricaBase.dof(r::$RT) = r.glance_table.dof
    end
end

MetricaBase.fitted(r::Union{SurveyLogitFitResult, SurveyProbitFitResult, SurveyPoissonFitResult}) =
    MetricaBase.fitted(r.discrete_result)
MetricaBase.residuals(r::Union{SurveyLogitFitResult, SurveyProbitFitResult, SurveyPoissonFitResult}) =
    MetricaBase.residuals(r.discrete_result)
MetricaBase.augment(r::Union{SurveyLogitFitResult, SurveyProbitFitResult, SurveyPoissonFitResult}) =
    MetricaBase.augment(r.discrete_result)
