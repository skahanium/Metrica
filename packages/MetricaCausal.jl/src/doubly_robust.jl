# === AIPW 双重稳健估计 ======================================================

function MetricaBase.fit(::Type{AIPWModel}, formula::AbstractString, data;
                          treatment_column::Symbol, outcome_column::Symbol,
                          outcome_formula::String, propensity_formula::String)
    df = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    treat_vec = Float64.(df[!, treatment_column])
    y_out = Float64.(df[!, outcome_column])
    n = length(y_out)
    treated = treat_vec .== 1.0
    control = .!treated

    # Step 1: 结果模型 (OLS) — 分别按处理组拟合
    # 拟合全样本模型以获取设计矩阵（用于后续预测）
    ols_full = MetricaBase.fit(OLSModel, outcome_formula, df)
    ols_full isa MetricaBase.ModelError && return ols_full
    X_full = ols_full.design_matrix

    # 拟合处理组结果模型 E[Y|X,T=1]
    df_treated = df[treated, :]
    ols1_result = MetricaBase.fit(OLSModel, outcome_formula, df_treated)
    ols1_result isa MetricaBase.ModelError && return ols1_result
    μ1_hat = MetricaBase.predict(ols1_result, newdata=X_full)

    # 拟合控制组结果模型 E[Y|X,T=0]
    df_control = df[control, :]
    ols0_result = MetricaBase.fit(OLSModel, outcome_formula, df_control)
    ols0_result isa MetricaBase.ModelError && return ols0_result
    μ0_hat = MetricaBase.predict(ols0_result, newdata=X_full)

    ols_result = (treated=ols1_result, control=ols0_result)

    # Step 2: 倾向得分模型 (Logit)
    ps_result = MetricaBase.fit(LogitModel, propensity_formula, df)
    ps_result isa MetricaBase.ModelError && return ps_result
    ps = ps_result.fitted_values
    ps = clamp.(ps, 0.01, 0.99)

    # Step 3: AIPW estimator
    # E[Y1] = 1/n Σ [T*Y/p + (1-T/p)*μ1_hat]
    # E[Y0] = 1/n Σ [(1-T)*Y/(1-p) + (1-(1-T)/(1-p))*μ0_hat]
    aipw_y1 = treat_vec .* y_out ./ ps .+ (1.0 .- treat_vec ./ ps) .* μ1_hat
    aipw_y0 = (1.0 .- treat_vec) .* y_out ./ (1.0 .- ps) .+ (1.0 .- (1.0 .- treat_vec) ./ (1.0 .- ps)) .* μ0_hat

    ate = mean(aipw_y1 - aipw_y0)
    att = mean(y_out[treated]) - mean(μ0_hat[treated])
    ate_se = sqrt(var(aipw_y1 - aipw_y0) / n)
    att_se = sqrt(var(y_out[treated] - μ0_hat[treated]) / sum(treated))

    glance_table = MetricaBase.ModelGlance(:aipw, n, n-1,
        Dict{Symbol, MetricaBase.MetricValue}(:ate => ate, :att => att),
        MetricaBase.ModelWarning[])

    tidy_rows = [MetricaBase.CoefRow(:ATE, ate, ate_se, ate/ate_se, 2*(1-cdf(Normal(), abs(ate/ate_se))))]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "AIPW (doubly robust)")

    return AIPWFitResult(formula, glance_table, tidy_table,
        ate, ate_se, att, att_se, ols_result, ps_result, ols_result.treated.glance_table.metrics[:r2])
end

MetricaBase.glance(result::AIPWFitResult) = result.glance_table
MetricaBase.tidy(result::AIPWFitResult) = result.tidy_table
MetricaBase.coef(result::AIPWFitResult) = MetricaBase.coef(result.outcome_model.treated)
MetricaBase.vcov(result::AIPWFitResult) = MetricaBase.vcov(result.outcome_model.treated)
MetricaBase.nobs(result::AIPWFitResult) = result.glance_table.nobs
MetricaBase.dof(result::AIPWFitResult) = result.glance_table.dof
MetricaBase.r2(result::AIPWFitResult) = result.glance_table.metrics[:pseudo_r2]
MetricaBase.stderror(result::AIPWFitResult) = MetricaBase.stderror(result.outcome_model.treated)
