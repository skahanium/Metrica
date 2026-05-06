# === 事件研究估计器 ==========================================================

function MetricaBase.fit(::Type{EventStudyModel}, formula::AbstractString, data;
                          panel_id::Symbol, panel_time::Symbol,
                          treated_column::Symbol, event_time_column::Symbol=:event_time,
                          pre_periods::Int=3, post_periods::Int=5,
                          vcov::Symbol=:cluster, panel_method::Symbol=:fe,
                          fe_spec::Vector{Symbol}=Symbol[], weights=nothing,
                          post_column::Union{Symbol,Nothing}=nothing)
    df = if data isa AbstractString
        loaded = MetricaLinear.load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    # 生成相对时期变量
    df.relative_time = df[!, panel_time] .- df[!, event_time_column]
    min_rel = -pre_periods
    max_rel = post_periods
    rel_values = min_rel:max_rel

    # 排除基准期 (-1)
    rel_dummies = setdiff(rel_values, [-1])

    # 为每个相对时期创建虚拟变量 × treated 交互列
    dummy_names = String[]
    for r in rel_dummies
        rs = replace(string(r), "-" => "m")  # -3 → m3
        col_name = "rel_$(rs)_x_treat"
        df[!, Symbol(col_name)] = Float64.(df.relative_time .== r) .* Float64.(df[!, treated_column])
        push!(dummy_names, col_name)
    end

    # 构造扩展公式
    extended_formula = formula * " + " * join(dummy_names, " + ")

    # StatsModels 展开
    model_formula = MetricaLinear.parse_formula_term(extended_formula)
    model_formula isa MetricaBase.ModelError && return model_formula
    model_columns = MetricaLinear.collect_term_symbols(model_formula)

    prepared = MetricaLinear.prepare_model_data(df, model_formula, model_columns, nothing, nothing)
    prepared isa MetricaBase.ModelError && return prepared
    (filtered_df, model_frame, _, X, y, _, _, _, _) = prepared

    X_noint = X[:, 2:end]
    coef_names = Symbol.(coefnames(model_frame))[2:end]

    id_vec = filtered_df[!, panel_id]
    time_vec = filtered_df[!, panel_time]
    twfe_result = fit_twfe(X_noint, y, id_vec, time_vec, has_intercept=false)

    coefficients = twfe_result.coefficients
    stderrors = twfe_result.stderror
    dof = twfe_result.dof
    nobs = twfe_result.nobs
    ncoef_es = length(coefficients)

    # 个体聚类标准误
    if vcov == :cluster
        residuals = y - X_noint * coefficients
        XtX_inv = twfe_result.vcov
        unique_ids = unique(id_vec)
        G = length(unique_ids)
        meat = zeros(ncoef_es, ncoef_es)
        for g in unique_ids
            idx = id_vec .== g
            Xg = X_noint[idx, :]
            eg = residuals[idx]
            meat += (Xg' * eg) * (eg' * Xg)
        end
        vcov_cluster = XtX_inv * meat * XtX_inv * (G / (G - 1)) * ((nobs - 1) / (nobs - ncoef_es))
        stderrors = sqrt.(max.(diag(vcov_cluster), 0.0))
    end

    # 提取各相对时期的系数
    period_coefs = Float64[]
    period_ses = Float64[]
    period_labels = String[]
    for r in rel_dummies
        rs = replace(string(r), "-" => "m")
        col = Symbol("rel_$(rs)_x_treat")
        idx = findfirst(==(col), coef_names)
        if !isnothing(idx)
            push!(period_coefs, coefficients[idx])
            push!(period_ses, stderrors[idx])
            push!(period_labels, string(r))
        end
    end

    # 平行趋势检验：预处理期系数联合 = 0 的 F 检验
    pre_indices = [i for (i, l) in enumerate(period_labels) if parse(Int, l) < -1]
    pre_trend_pvalue = 1.0
    parallel_supported = true
    if length(pre_indices) >= 2
        pre_coefs = period_coefs[pre_indices]
        q = length(pre_indices)
        pre_vcov = twfe_result.vcov[pre_indices, pre_indices]
        f_stat = (pre_coefs' * (pre_vcov \ pre_coefs)) / q
        pre_trend_pvalue = 1 - cdf(FDist(q, max(dof, 1)), f_stat)
        parallel_supported = pre_trend_pvalue > 0.05
    end

    glance_table = MetricaBase.ModelGlance(:event_study, twfe_result.nobs, dof,
        Dict{Symbol, MetricaBase.MetricValue}(
            :n_periods => length(period_labels),
            :pre_trend_pvalue => pre_trend_pvalue,
        ),
        MetricaBase.ModelWarning[
            MetricaBase.ModelWarning(:parallel_trends_check,
                "平行趋势检验",
                "事前趋势联合 F 检验 p = $(round(pre_trend_pvalue, digits=4))。" *
                (parallel_supported ? "未拒绝平行趋势假设。" : "拒绝平行趋势假设，请谨慎解读。"),
                "",
                parallel_supported ? MetricaBase.info : MetricaBase.warning,
            )
        ])

    tidy_rows = [let
        t_stat = stderrors[i] > 1e-15 ? coefficients[i]/stderrors[i] : 0.0
        p_val = t_stat != 0.0 ? 2*(1-cdf(TDist(max(dof,1)), abs(t_stat))) : 1.0
        MetricaBase.CoefRow(coef_names[i], coefficients[i], stderrors[i], t_stat, p_val)
    end for i in 1:length(coef_names)]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "TWFE")

    return EventStudyFitResult(formula, glance_table, tidy_table,
        period_coefs, period_ses, period_labels,
        pre_trend_pvalue, parallel_supported,
        coef_names, coefficients, -Inf)
end

MetricaBase.glance(result::EventStudyFitResult) = result.glance_table
MetricaBase.tidy(result::EventStudyFitResult) = result.tidy_table
MetricaBase.coef(result::EventStudyFitResult) = result.coefficient_names .=> result.coefficient_values
MetricaBase.nobs(result::EventStudyFitResult) = result.glance_table.nobs
MetricaBase.dof(result::EventStudyFitResult) = result.glance_table.dof
MetricaBase.r2(result::EventStudyFitResult) = NaN
MetricaBase.stderror(result::EventStudyFitResult) = result.tidy_table.rows .|> r -> r.stderror |> Float64
