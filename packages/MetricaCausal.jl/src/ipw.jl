# === IPW 逆概率加权 ==========================================================

function MetricaBase.fit(::Type{IPWModel}, formula::AbstractString, data;
                          treatment_column::Symbol, outcome_column::Symbol,
                          propensity_formula::String)
    df = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    # Step 1: 倾向得分模型 (Logit)
    treat_vec = Float64.(df[!, treatment_column])
    ps_result = MetricaBase.fit(LogitModel, propensity_formula, df)
    ps_result isa MetricaBase.ModelError && return ps_result
    ps = ps_result.fitted_values
    ps = clamp.(ps, 0.01, 0.99)

    # Step 2: IPW 权重
    w = treat_vec ./ ps .+ (1.0 .- treat_vec) ./ (1.0 .- ps)

    # Step 3: 结果变量
    y_out = Float64.(df[!, outcome_column])

    # Step 4: 加权估计
    n = length(y_out)
    ate = sum(w .* treat_vec .* y_out) / sum(w .* treat_vec) - sum(w .* (1 .- treat_vec) .* y_out) / sum(w .* (1 .- treat_vec))

    # ATT: treated group vs counterfactual
    treated_mask = treat_vec .== 1.0
    control_mask = .!treated_mask
    att = mean(y_out[treated_mask]) - sum(w[control_mask] .* y_out[control_mask]) / sum(w[control_mask])

    # ATU
    atu = sum(w[treated_mask] .* y_out[treated_mask]) / sum(w[treated_mask]) - mean(y_out[control_mask])

    # Robust SE (sandwich)
    mu1 = sum(w .* treat_vec .* y_out) / sum(w .* treat_vec)
    mu0 = sum(w .* (1 .- treat_vec) .* y_out) / sum(w .* (1 .- treat_vec))
    score = w .* treat_vec .* (y_out .- mu1) ./ sum(w .* treat_vec) .- w .* (1 .- treat_vec) .* (y_out .- mu0) ./ sum(w .* (1 .- treat_vec))
    ate_se = sqrt(sum(score.^2)) / n

    # ATT SE (simplified)
    n1 = sum(treated_mask)
    att_se = sqrt(var(y_out[treated_mask]) / n1 + sum((w[control_mask] .* (y_out[control_mask] .- mu0)).^2) / sum(w[control_mask])^2)

    # ATU SE
    n0 = sum(control_mask)
    mu1_atu = sum(w[treated_mask] .* y_out[treated_mask]) / sum(w[treated_mask])
    atu_se = sqrt(sum((w[treated_mask] .* (y_out[treated_mask] .- mu1_atu)).^2) / sum(w[treated_mask])^2 + var(y_out[control_mask]) / n0)

    glance_table = MetricaBase.ModelGlance(:ipw, n, n-1,
        Dict{Symbol, MetricaBase.MetricValue}(:ate => ate, :att => att, :atu => atu),
        MetricaBase.ModelWarning[])

    tidy_rows = [
        MetricaBase.CoefRow(:ATE, ate, ate_se, ate/ate_se, 2*(1-cdf(Normal(), abs(ate/ate_se)))),
        MetricaBase.CoefRow(:ATT, att, att_se, att/att_se, 2*(1-cdf(Normal(), abs(att/att_se)))),
        MetricaBase.CoefRow(:ATU, atu, atu_se, atu/atu_se, 2*(1-cdf(Normal(), abs(atu/atu_se))))
    ]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "IPW (robust sandwich)")

    return IPWFitResult(formula, glance_table, tidy_table,
        ps_result, ate, ate_se, att, att_se, atu, atu_se, w, ps_result.loglikelihood)
end

MetricaBase.glance(result::IPWFitResult) = result.glance_table
MetricaBase.tidy(result::IPWFitResult) = result.tidy_table
MetricaBase.coef(result::IPWFitResult) = MetricaBase.coef(result.propensity_model)
MetricaBase.vcov(result::IPWFitResult) = MetricaBase.vcov(result.propensity_model)
MetricaBase.nobs(result::IPWFitResult) = result.glance_table.nobs
MetricaBase.dof(result::IPWFitResult) = result.glance_table.dof
MetricaBase.r2(result::IPWFitResult) = result.glance_table.metrics[:pseudo_r2]
MetricaBase.stderror(result::IPWFitResult) = MetricaBase.stderror(result.propensity_model)
