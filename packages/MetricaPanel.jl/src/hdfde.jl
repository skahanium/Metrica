# === 高维固定效应估计器 =======================================================
# 通过 FixedEffectModels.jl 支持多维固定效应（如个体+时间双向）

using FixedEffectModels

"""
    fit_hdfde(panel_data::PanelData, formula::String; fe_spec::Vector{Symbol})

使用高维固定效应拟合面板模型。`fe_spec` 指定固定效应维度列名。

# 示例
```julia
fit_hdfde(panel_data, "y ~ x1 + x2"; fe_spec=[:firm, :year])
```
"""
function fit_hdfde(panel_data::MetricaBase.PanelData, formula::String;
                   fe_spec::Vector{Symbol})
    data = DataFrame(panel_data.data)
    id_col = panel_data.id_col
    time_col = panel_data.time_col

    # 构建 FixedEffectModels 公式：原公式 + fe() 固定效应项
    parts = split(formula, "~")
    response_name = strip(parts[1])
    rhs = strip(parts[2])

    fe_terms = join(["fe($col)" for col in fe_spec], " + ")
    fem_formula = "$(response_name) ~ $(rhs) + $(fe_terms)"

    # 调用 FixedEffectModels.reg
    result = try
        reg(data, FormulaTerm(Term(Symbol(response_name)),
             tuple([Term(Symbol(x)) for x in split(rhs, "+")]...,
                   [fe(Term(col)) for col in fe_spec]...));
             save=:fe)
    catch e
        return MetricaBase.ModelError(
            :hdfde_fit_failed, "HDFE 拟合失败",
            "FixedEffectModels.reg 执行出错：$(sprint(showerror, e))",
            "请检查公式语法和固定效应列名。")
    end

    # 提取结果
    coef_names = Symbol.(FixedEffectModels.coefnames(result))
    coefficients = FixedEffectModels.coef(result)
    vcov_mat = FixedEffectModels.vcov(result)
    std_errors = FixedEffectModels.stderror(result)

    nobs_val = FixedEffectModels.nobs(result)
    dof_val = FixedEffectModels.dof_residual(result)
    r2_val = FixedEffectModels.r2(result)
    adj_r2_val = FixedEffectModels.adjr2(result)

    fitted_values = try
        FixedEffectModels.predict(result, data)
    catch
        # 若 predict 失败，使用系数直接计算
        rhs_names = [strip(x) for x in split(rhs, "+")]
        X = hcat([Float64.(data[!, Symbol(name)]) for name in rhs_names]...)
        X * coefficients[2:end]  # 排除截距
    end
    residual_vector = Float64.(data[!, Symbol(response_name)]) .- fitted_values

    rss = sum(abs2, residual_vector)
    tss = sum(abs2, Float64.(data[!, Symbol(response_name)]) .- mean(Float64.(data[!, Symbol(response_name)])))
    sigma = dof_val > 0 ? sqrt(rss / dof_val) : NaN

    # 对数似然、AIC、BIC
    loglik = -nobs_val / 2.0 * (1.0 + log(2π) + log(rss / nobs_val))
    k_params = length(coefficients) + 1
    aic_val = -2.0 * loglik + 2.0 * k_params
    bic_val = -2.0 * loglik + k_params * log(nobs_val)

    metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :r2 => r2_val, :adj_r2 => adj_r2_val, :sigma => sigma, :rss => rss, :tss => tss,
        :loglikelihood => loglik, :aic => aic_val, :bic => bic_val,
        :n_ids => length(unique(data[!, id_col])),
        :n_times => length(unique(data[!, time_col])),
    )

    glance_table = MetricaBase.ModelGlance(:hdfde, nobs_val, dof_val, metrics, MetricaBase.ModelWarning[])

    t_stats = coefficients ./ std_errors
    p_values = 2.0 .* (1.0 .- cdf.(TDist(dof_val), abs.(t_stats)))
    t_crit = quantile(TDist(dof_val), 0.975)
    ci_lowers = coefficients .- t_crit .* std_errors
    ci_uppers = coefficients .+ t_crit .* std_errors
    tidy_rows = [MetricaBase.CoefRow(coef_names[i], coefficients[i], std_errors[i], t_stats[i], p_values[i], ci_lowers[i], ci_uppers[i]) for i in eachindex(coef_names)]
    tidy_table = MetricaBase.TidyTable(tidy_rows, "hdfde")

    return PanelFitResult(formula, glance_table, tidy_table, panel_data,
                          fitted_values, residual_vector, coef_names, :hdfde)
end
