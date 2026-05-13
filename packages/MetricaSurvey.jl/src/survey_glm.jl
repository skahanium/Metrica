# === Survey GLM：Logit / Probit / Poisson 加权伪似然估计 ==========================

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

    # 用调查权重做加权 IRLS 获取点估计
    weighted_result = _fit_weighted_discrete(LogitModel, formula, dataset, wc, MetricaDiscrete.LOGIT_LINK)
    weighted_result isa MetricaBase.ModelError && return weighted_result

    build_survey_glm_result(
        SurveyLogitFitResult, weighted_result, formula, dataset, design, wc,
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

    weighted_result = _fit_weighted_discrete(ProbitModel, formula, dataset, wc, MetricaDiscrete.PROBIT_LINK)
    weighted_result isa MetricaBase.ModelError && return weighted_result

    build_survey_glm_result(
        SurveyProbitFitResult, weighted_result, formula, dataset, design, wc,
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

    weighted_result = _fit_weighted_discrete(PoissonModel, formula, dataset, wc, MetricaDiscrete.LOG_LINK)
    weighted_result isa MetricaBase.ModelError && return weighted_result

    build_survey_glm_result(
        SurveyPoissonFitResult, weighted_result, formula, dataset, design, wc,
    )
end

# === 加权离散模型拟合辅助 ========================================================

"""
    _fit_weighted_discrete(ModelType, formula, dataset, weights_column, link)

用调查权重拟合离散模型：解析公式、提取 X/y/w，调用加权 IRLS。
返回命名元组 (coefficients, vcov_matrix, fitted_values, ...) 或 ModelError。
"""
function _fit_weighted_discrete(
    ModelType::Type, formula::AbstractString, dataset::DataFrame,
    weights_column::Symbol, link::MetricaDiscrete.Link,
)
    model_formula = MetricaLinear.parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    err = MetricaLinear.validate_model_columns(dataset, model_columns, nothing, nothing)
    err isa MetricaBase.ModelError && return err

    prepared = MetricaLinear.prepare_model_data(
        dataset, model_formula, model_columns, nothing, nothing,
    )
    prepared isa MetricaBase.ModelError && return prepared

    (_, model_frame, _, X, y, _, _, n_total, n_effective) = prepared
    nobs = length(y)
    ncoef = size(X, 2)

    # 响应变量校验
    if link.name == :logit || link.name == :probit
        unique_y = unique(y)
        if !all(in([0.0, 1.0]), unique_y)
            return MetricaBase.ModelError(
                :invalid_binary_response,
                "响应变量不是二值变量",
                "$(ModelType) 要求响应变量为 0/1 二值变量。当前数据包含值：$(unique_y)。",
                "请检查响应变量是否为 0/1 编码。",
            )
        end
    elseif link.name == :log
        if any(y .< 0)
            return MetricaBase.ModelError(
                :invalid_count_response,
                "响应变量不是计数数据",
                "Poisson 模型要求响应变量为非负整数。当前数据包含负值。",
                "请检查响应变量是否为计数数据。",
            )
        end
        if !all(y .== floor.(y))
            return MetricaBase.ModelError(
                :invalid_count_response,
                "响应变量不是计数数据",
                "Poisson 模型要求响应变量为非负整数。当前数据包含非整数值。",
                "请检查响应变量是否为计数数据。",
            )
        end
    end

    err = MetricaLinear.validate_design(X, ncoef, nobs)
    err isa MetricaBase.ModelError && return err

    w = dataset[1:nobs, weights_column]

    irls_result = MetricaDiscrete.weighted_irls(X, y, link, w)
    irls_result isa MetricaBase.ModelError && return irls_result

    coefficient_names = Symbol.(StatsModels.coefnames(model_frame))

    return (
        coefficients = irls_result.coefficients,
        vcov_matrix = irls_result.vcov,
        fitted_values = irls_result.fitted_values,
        linear_predictor = irls_result.linear_predictor,
        design_matrix = Matrix{Float64}(X),
        response_vector = y,
        coefficient_names = coefficient_names,
        deviance = irls_result.deviance,
        loglikelihood = irls_result.loglikelihood,
        iterations = irls_result.iterations,
        converged = irls_result.converged,
        nobs = nobs,
        ncoef = ncoef,
        n_total = n_total,
        n_effective = n_effective,
    )
end

# === 共享的 GLM Survey 结果构建逻辑 ==============================================

function build_survey_glm_result(
    ResultT::Type,
    weighted_result,
    formula::AbstractString,
    dataset::DataFrame,
    design::SurveyDesign,
    weights_column::Symbol,
)
    X = weighted_result.design_matrix
    y = weighted_result.response_vector
    fitted = weighted_result.fitted_values
    ncoef = size(X, 2)
    nobs = length(y)

    # Pearson 残差: r_j = (y_j - μ_j) / sqrt(V(μ_j))
    residuals = y - fitted

    w = dataset[1:nobs, weights_column]

    # GLM Hessian 作为 bread: H^{-1} = vcov_matrix（来自加权 IRLS）
    bread = weighted_result.vcov_matrix

    # Taylor 线性化 Sandwich 方差（使用 GLM Hessian 作为 bread）
    survey_vcov = glm_taylor_linearization_vcov(X, residuals, w, bread, design)
    survey_se = sqrt.(max.(diag(survey_vcov), 0.0))

    # 设计效应（用加权 IRLS 的 vcov 作为 SRS 参考）
    srs_vcov = weighted_result.vcov_matrix
    deff, n_eff = compute_deff(survey_vcov, srs_vcov, nobs)

    coef_vals = weighted_result.coefficients
    coef_names = weighted_result.coefficient_names

    # z 统计量
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

    # Glance（扩展原有指标，附加 mean_deff）
    link_sym = if ResultT == SurveyLogitFitResult
        :logit
    elseif ResultT == SurveyProbitFitResult
        :probit
    else
        :poisson
    end
    dof = nobs - ncoef

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = weighted_result.n_total - weighted_result.n_effective
    dropped_rows > 0 && push!(warnings, MetricaLinear.build_rows_dropped_warning(dropped_rows))
    if !weighted_result.converged
        push!(warnings, MetricaBase.ModelWarning(
            :irls_not_converged, "加权 IRLS 未收敛",
            "加权 IRLS 迭代在最大次数内未收敛，结果可能不可靠。",
            "请检查数据中是否存在完全分离或数值问题。",
            MetricaBase.warning,
        ))
    end

    # 模型拟合指标
    loglik = weighted_result.loglikelihood
    pseudo_r2 = if link_sym == :logit || link_sym == :probit
        null_ll = MetricaDiscrete.null_loglikelihood_bernoulli(y)
        1 - (-loglik) / max(-null_ll, 1e-10)
    else
        null_ll = MetricaDiscrete.null_loglikelihood_poisson(y)
        1 - (-loglik) / max(-null_ll, 1e-10)
    end
    aic = 2 * ncoef - 2 * loglik
    bic = ncoef * log(nobs) - 2 * loglik

    survey_glance = MetricaBase.ModelGlance(
        Symbol("survey_$(link_sym)"),
        nobs, dof,
        Dict{Symbol, MetricaBase.MetricValue}(
            :pseudo_r2 => pseudo_r2, :loglik => loglik,
            :aic => aic, :bic => bic,
            :deviance => weighted_result.deviance,
            :mean_deff => mean(deff),
            :wald_f => wald_f, :wald_pvalue => wald_pvalue,
        ),
        warnings,
    )

    # Tidy（使用 survey 修正 SE）
    z_crit = quantile(Normal(), 0.975)
    tidy_rows = MetricaBase.CoefRow[
        MetricaBase.CoefRow(coef_names[i], coef_vals[i], survey_se[i], z_stats[i], pvalues[i],
            coef_vals[i] - z_crit * survey_se[i], coef_vals[i] + z_crit * survey_se[i])
        for i in 1:ncoef
    ]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "z")

    return ResultT(
        String(formula), survey_glance, tidy_table,
        weighted_result, survey_vcov, survey_se, deff, n_eff,
        coef_names, coef_vals,
    )
end

# === GLM Taylor 线性化 Sandwich 方差 ============================================

"""
    glm_taylor_linearization_vcov(X, residuals, weights, bread, design)

用 GLM Hessian 逆矩阵作为 bread 的 Taylor 线性化 Sandwich 方差。
score_j = x_j * w_j * r_j, Var(β) = B * Var(S) * B
"""
function glm_taylor_linearization_vcov(
    X::Matrix{Float64},
    residuals::Vector{Float64},
    weights::Vector{Float64},
    bread::Matrix{Float64},
    design::SurveyDesign,
)
    nobs, ncoef = size(X)
    w = weights[1:nobs]

    # 计算每个观测的得分贡献: s_j = x_j * w_j * r_j
    score_matrix = X .* (w .* residuals)

    strata_col = design.strata_column
    psu_col = design.psu_column
    fpc_col = design.fpc_column

    # 根据抽样设计结构计算 Var_hat(S)
    if !isnothing(strata_col) && !isnothing(psu_col)
        Var_S = strata_psu_variance(score_matrix, design, nobs)
    elseif !isnothing(strata_col)
        Var_S = strata_only_variance(score_matrix, design, nobs)
    elseif !isnothing(psu_col)
        Var_S = psu_only_variance(score_matrix, design, nobs)
    else
        s_bar = mean(score_matrix, dims=1)
        centered = score_matrix .- s_bar
        Var_S = (nobs / (nobs - 1)) * (centered' * centered)
    end

    # 有限总体修正 (FPC)
    if !isnothing(fpc_col)
        fpc_values = design.data[1:nobs, fpc_col]
        sampling_fraction = nobs ./ fpc_values
        fpc_factor = max.(1.0 .- sampling_fraction, 0.0)
        if any(sampling_fraction .> 0.05)
            Var_S = Var_S .* median(fpc_factor[sampling_fraction .> 0.05])
        end
    end

    # Sandwich: Var(β) = B * Var_S * B （B = GLM Hessian^{-1}）
    survey_vcov = bread * Var_S * bread

    survey_vcov = Symmetric(survey_vcov)
    d = diag(survey_vcov)
    if any(<(0), d)
        d_fixed = max.(d, 0.0)
        survey_vcov = survey_vcov + Diagonal(d_fixed - d)
    end

    return Matrix(survey_vcov)
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
    r.discrete_result.fitted_values
MetricaBase.residuals(r::Union{SurveyLogitFitResult, SurveyProbitFitResult, SurveyPoissonFitResult}) =
    r.discrete_result.response_vector - r.discrete_result.fitted_values
function MetricaBase.augment(r::Union{SurveyLogitFitResult, SurveyProbitFitResult, SurveyPoissonFitResult})
    d = r.discrete_result
    n = length(d.response_vector)
    res = d.response_vector - d.fitted_values
    return MetricaBase.AugmentTable(
        Dict(:observation => collect(1.0:n), :fitted => d.fitted_values, :residual => res),
        n,
    )
end
