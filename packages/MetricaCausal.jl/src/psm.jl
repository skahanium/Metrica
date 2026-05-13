# === PSM 倾向得分匹配 ========================================================

function MetricaBase.fit(::Type{PSMModel}, formula::AbstractString, data;
                          treatment_column::Symbol, outcome_column::Symbol,
                          propensity_formula::String, method::Symbol=:nearest,
                          caliper::Float64=0.2, n_neighbors::Int=1)
    df = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    # Step 1: 倾向得分
    treat_vec = Float64.(df[!, treatment_column])
    ps_result = MetricaBase.fit(LogitModel, propensity_formula, df)
    ps_result isa MetricaBase.ModelError && return ps_result
    ps = ps_result.fitted_values

    y_out = Float64.(df[!, outcome_column])

    treated_idx = findall(treat_vec .== 1.0)
    control_idx = findall(treat_vec .== 0.0)
    ps_treated = ps[treated_idx]
    ps_control = ps[control_idx]
    y_treated = y_out[treated_idx]
    y_control = y_out[control_idx]

    # Step 2: 最近邻匹配
    caliper_sd = caliper * std(ps)
    matched_diffs = Float64[]

    for (i, pt) in enumerate(ps_treated)
        dists = abs.(ps_control .- pt)
        sorted_idx = sortperm(dists)
        n_match = 0
        diff_sum = 0.0
        for j in sorted_idx
            if dists[j] <= caliper_sd
                diff_sum += y_treated[i] - y_control[j]
                n_match += 1
                n_match >= n_neighbors && break
            else
                break
            end
        end
        if n_match > 0
            push!(matched_diffs, diff_sum / n_match)
        end
    end

    n_matched = length(matched_diffs)
    if n_matched == 0
        return MetricaBase.ModelError(:psm_no_matches, "PSM 无匹配样本",
            "卡尺 $(caliper) 标准差内无匹配。请增大 caliper 或检查数据。", "")
    end

    att = mean(matched_diffs)
    att_se = sqrt(var(matched_diffs) / n_matched)

    # 平衡性检验
    balance_data = Dict{Symbol, Any}[]
    for col_name in Symbol.(names(df))
        col_name == treatment_column && continue
        col_name == outcome_column && continue
        col = df[!, col_name]
        if eltype(col) <: Number
            mean_t = mean(col[treated_idx])
            mean_c = mean(col[control_idx])
            sd_pooled = sqrt(max((var(col[treated_idx]) + var(col[control_idx])) / 2, 1e-10))
            std_bias = sd_pooled > 1e-10 ? 100 * (mean_t - mean_c) / sd_pooled : 0.0
            push!(balance_data, Dict(:variable => String(col_name), :mean_treated => mean_t,
                :mean_control => mean_c, :std_bias => std_bias))
        else
            # 分类变量：比较比例
            vals_t = proportionmap(col[treated_idx])
            vals_c = proportionmap(col[control_idx])
            all_vals = union(keys(vals_t), keys(vals_c))
            max_diff = 0.0
            for v in all_vals
                diff = abs(get(vals_t, v, 0.0) - get(vals_c, v, 0.0))
                max_diff = max(max_diff, diff)
            end
            push!(balance_data, Dict(:variable => String(col_name), :mean_treated => NaN,
                :mean_control => NaN, :std_bias => 100 * max_diff))
        end
    end
    balance_df = DataFrame(balance_data)

    glance_table = MetricaBase.ModelGlance(:psm, length(y_out), length(y_out)-1,
        Dict{Symbol, MetricaBase.MetricValue}(:att => att, :n_matched => n_matched),
        MetricaBase.ModelWarning[])

    z_crit = quantile(Normal(), 0.975)
    tidy_rows = [MetricaBase.CoefRow(:ATT, att, att_se, att/att_se, 2*(1-cdf(Normal(), abs(att/att_se))),
        att - z_crit * att_se, att + z_crit * att_se)]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "PSM (nearest neighbor)")

    return PSMFitResult(formula, glance_table, tidy_table,
        ps_result, att, att_se, n_matched, balance_df, ps_result.loglikelihood)
end

MetricaBase.glance(result::PSMFitResult) = result.glance_table
MetricaBase.tidy(result::PSMFitResult) = result.tidy_table
MetricaBase.coef(result::PSMFitResult) = MetricaBase.coef(result.propensity_model)
MetricaBase.vcov(result::PSMFitResult) = MetricaBase.vcov(result.propensity_model)
MetricaBase.nobs(result::PSMFitResult) = result.glance_table.nobs
MetricaBase.dof(result::PSMFitResult) = result.glance_table.dof
MetricaBase.r2(result::PSMFitResult) = result.glance_table.metrics[:att]
MetricaBase.stderror(result::PSMFitResult) = MetricaBase.stderror(result.propensity_model)
