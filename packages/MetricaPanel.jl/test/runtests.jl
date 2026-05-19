using Test
using CSV
using DataFrames
using MetricaBase
using MetricaPanel
using Statistics

const DPGMM_DEMO = joinpath(dirname(@__DIR__), "..", "..", "datasets", "demo", "dynamic_panel_gmm_demo.csv")

function read_teaching_csv(path::String)
    lines = readlines(path)
    columns = Symbol.(split(first(lines), ","))
    data = Dict{Symbol, Vector}()
    raw_rows = [split(line, ",") for line in lines[2:end]]

    for (index, name) in enumerate(columns)
        values = [row[index] for row in raw_rows]
        if name in (:country, :isocode)
            data[name] = String.(values)
        elseif name === :year
            data[name] = parse.(Int, values)
        else
            data[name] = parse.(Float64, values)
        end
    end

    return data
end

@testset "MetricaPanel 面板基础" begin
    # 构造简单的面板数据
    data = Dict(
        :firm => [1, 1, 1, 2, 2, 2, 3, 3, 3],
        :year => [1, 2, 3, 1, 2, 3, 1, 2, 3],
        :invest => [10.0, 12.0, 14.0, 15.0, 18.0, 20.0, 8.0, 10.0, 12.0],
        :mvalue => [100.0, 120.0, 140.0, 150.0, 180.0, 200.0, 80.0, 100.0, 120.0],
        :capital => [50.0, 55.0, 60.0, 70.0, 75.0, 80.0, 40.0, 45.0, 50.0],
    )
    panel_data = PanelData(data, :firm, :year)

    @testset "PanelModel 规格对象" begin
        model = PanelModel("invest ~ mvalue + capital", :firm, :year, :fe)
        @test model isa MetricaBase.AbstractPanelModel
        @test model.formula == "invest ~ mvalue + capital"
        @test model.id_col === :firm
        @test model.time_col === :year
        @test model.method === :fe
    end

    @testset "FE 固定效应拟合" begin
        result = fit_panel(panel_data, "invest ~ mvalue + capital"; method=:fe)
        @test result isa PanelFitResult
        @test result.method === :fe

        # 检查 glance
        g = glance(result)
        @test g.model === :fe
        @test g.nobs == 9
        @test g.dof == 5
        @test haskey(g.metrics, :r2)
        @test haskey(g.metrics, :adj_r2)
        @test haskey(g.metrics, :n_ids)
        @test haskey(g.metrics, :n_times)
        @test g.metrics[:n_ids] == 3
        @test g.metrics[:n_times] == 3

        # Task 9: loglikelihood/aic/bic
        @test haskey(g.metrics, :loglikelihood)
        @test haskey(g.metrics, :aic)
        @test haskey(g.metrics, :bic)
        @test isfinite(g.metrics[:loglikelihood])
        @test isfinite(g.metrics[:aic])
        @test isfinite(g.metrics[:bic])

        # Task 11: within/between/overall R²
        @test haskey(g.metrics, :r2_within)
        @test haskey(g.metrics, :r2_between)
        @test haskey(g.metrics, :r2_overall)
        @test 0.0 <= g.metrics[:r2_within] <= 1.0
        @test 0.0 <= g.metrics[:r2_between] <= 1.0
        @test 0.0 <= g.metrics[:r2_overall] <= 1.0

        # 检查 tidy（FE 无截距，截距被实体固定效应吸收）
        t = tidy(result)
        @test length(t.rows) == 2  # mvalue + capital
        @test t.vcov_label == "classical"
        @test all(row -> row.pvalue !== nothing, t.rows)

        # Task 12: 置信区间
        @test all(row -> row.ci_lower !== nothing, t.rows)
        @test all(row -> row.ci_upper !== nothing, t.rows)
        @test all(row -> row.ci_lower < row.estimate < row.ci_upper, t.rows)

        # 检查 augment — fitted + residual 必须在原始 y 空间成立
        a = augment(result)
        @test a isa MetricaBase.AugmentTable
        @test a.nobs == 9
        @test haskey(a.columns, :fitted)
        @test haskey(a.columns, :residual)
        @test haskey(a.columns, :std_residual)

        y_orig = [10.0, 12.0, 14.0, 15.0, 18.0, 20.0, 8.0, 10.0, 12.0]
        @test a.columns[:fitted] + a.columns[:residual] ≈ y_orig atol=1e-10
        @test sum(a.columns[:residual]) ≈ 0.0 atol=1e-10
    end

    @testset "FE 结果序列化" begin
        result = fit_panel(panel_data, "invest ~ mvalue + capital"; method=:fe)
        payload = result_to_payload(result)
        @test payload["status"] == "success"
        @test haskey(payload, "result_payload")
        @test haskey(payload["result_payload"], "glance")
        @test haskey(payload["result_payload"], "tidy")
        @test haskey(payload["result_payload"], "augment_preview")
        @test payload["result_payload"]["glance"]["model"] == "fe"
        @test payload["result_payload"]["glance"]["metrics"]["n_ids"] == 3
        @test payload["result_payload"]["augment_preview"] isa Vector
        @test haskey(payload["result_payload"]["augment_preview"][1], "fitted")
        @test haskey(payload["result_payload"]["augment_preview"][1], "std_residual")

        # Task 9: loglikelihood/aic/bic 在载荷中
        @test haskey(payload["result_payload"]["glance"]["metrics"], "loglikelihood")
        @test haskey(payload["result_payload"]["glance"]["metrics"], "aic")
        @test haskey(payload["result_payload"]["glance"]["metrics"], "bic")

        # Task 12: 置信区间在 tidy 载荷中
        @test haskey(payload["result_payload"]["tidy"][1], "ci_lower")
        @test haskey(payload["result_payload"]["tidy"][1], "ci_upper")
        @test payload["result_payload"]["tidy"][1]["ci_lower"] < payload["result_payload"]["tidy"][1]["estimate"]
        @test payload["result_payload"]["tidy"][1]["estimate"] < payload["result_payload"]["tidy"][1]["ci_upper"]
    end

    @testset "面板诊断结构化载荷" begin
        diagnostics = panel_diagnostics(panel_data, "invest ~ mvalue + capital")

        @test haskey(diagnostics, "hausman")
        @test haskey(diagnostics, "fixed_effect_f")
        @test haskey(diagnostics, "breusch_pagan_lm")

        for key in ("hausman", "fixed_effect_f", "breusch_pagan_lm")
            diagnostic = diagnostics[key]
            @test haskey(diagnostic, "available")
            @test haskey(diagnostic, "method")
            @test haskey(diagnostic, "note")
            if diagnostic["available"]
                @test isfinite(diagnostic["statistic"])
                @test 0.0 <= diagnostic["pvalue"] <= 1.0
            end
        end
    end

    @testset "FE 不平衡面板" begin
        unbalanced_data = Dict(
            :firm => [1, 1, 2, 2, 2],
            :year => [1, 2, 1, 2, 3],
            :invest => [10.0, 12.0, 15.0, 18.0, 20.0],
            :mvalue => [100.0, 120.0, 150.0, 180.0, 200.0],
        )
        unbalanced_panel = PanelData(unbalanced_data, :firm, :year)
        result = fit_panel(unbalanced_panel, "invest ~ mvalue"; method=:fe)
        @test result isa PanelFitResult
        @test glance(result).nobs == 5

        a = augment(result)
        y_orig = [10.0, 12.0, 15.0, 18.0, 20.0]
        @test a.columns[:fitted] + a.columns[:residual] ≈ y_orig atol=1e-10

        diagnostics = panel_diagnostics(unbalanced_panel, "invest ~ mvalue")
        # M7: BP LM 现在支持不平衡面板
        @test diagnostics["breusch_pagan_lm"]["available"] == true
        @test occursin("不平衡面板", diagnostics["breusch_pagan_lm"]["note"])

        # BP-LM 不平衡面板应使用 T_star 修正量
        # 手动计算 T_star 验证统计量
        N = 5
        n_groups = 2
        group_sizes = [2, 3]
        sum_T_sq = sum(s^2 for s in group_sizes)  # 4 + 9 = 13
        T_star_expected = (N - sum_T_sq / N) / (n_groups - 1)  # (5 - 2.6) / 1 = 2.4

        # 获取 pooled OLS 残差并计算 ratio
        design = MetricaPanel._panel_design(unbalanced_panel, "invest ~ mvalue")
        pooled_stats = MetricaPanel.ols_statistics(
            Matrix{Float64}(design.X_design), design.y, design.coef_names, :pooled,
            Dict{Symbol, MetricaBase.MetricValue}(:n_ids => n_groups),
        )
        res = pooled_stats.residuals
        grouped_res = groupby(DataFrame(id=unbalanced_data[:firm], residual=res), :id)
        group_sums_res = [sum(g.residual) for g in grouped_res]
        sum_sq_groups = sum(s^2 for s in group_sums_res)
        total_ss = sum(abs2, res)
        ratio = sum_sq_groups / total_ss

        expected_stat = n_groups * T_star_expected / (2 * (T_star_expected - 1)) * (ratio - 1)^2
        expected_stat = max(expected_stat, 0.0)
        @test diagnostics["breusch_pagan_lm"]["statistic"] ≈ expected_stat atol=1e-10
    end

    @testset "RE（Mundlak/CRE）拟合" begin
        result = fit_panel(panel_data, "invest ~ mvalue + capital"; method=:re)
        @test result isa PanelFitResult
        @test result.method === :re

        g = glance(result)
        @test g.model === :re
        @test g.nobs == 9
        @test haskey(g.metrics, :r2)
        @test haskey(g.metrics, :n_ids)
        @test g.metrics[:n_ids] == 3

        # Task 9: loglikelihood/aic/bic
        @test haskey(g.metrics, :loglikelihood)
        @test haskey(g.metrics, :aic)
        @test haskey(g.metrics, :bic)
        @test isfinite(g.metrics[:loglikelihood])
        @test isfinite(g.metrics[:aic])
        @test isfinite(g.metrics[:bic])

        # Task 10: rho/sigma_u/sigma_e
        @test haskey(g.metrics, :sigma_u)
        @test haskey(g.metrics, :sigma_e)
        @test haskey(g.metrics, :rho)
        @test g.metrics[:sigma_u] >= 0.0
        @test g.metrics[:sigma_e] >= 0.0
        @test 0.0 <= g.metrics[:rho] <= 1.0

        # Task 11: within/between/overall R²
        @test haskey(g.metrics, :r2_within)
        @test haskey(g.metrics, :r2_between)
        @test haskey(g.metrics, :r2_overall)
        @test 0.0 <= g.metrics[:r2_within] <= 1.0
        @test 0.0 <= g.metrics[:r2_between] <= 1.0
        @test 0.0 <= g.metrics[:r2_overall] <= 1.0

        t = tidy(result)
        @test length(t.rows) == 5  # intercept + 2 predictors + 2 group means
        @test all(row -> row.pvalue !== nothing, t.rows)

        # Task 12: 置信区间
        @test all(row -> row.ci_lower !== nothing, t.rows)
        @test all(row -> row.ci_upper !== nothing, t.rows)
        @test all(row -> row.ci_lower < row.estimate < row.ci_upper, t.rows)

        a = augment(result)
        @test haskey(a.columns, :std_residual)
        y_orig = [10.0, 12.0, 14.0, 15.0, 18.0, 20.0, 8.0, 10.0, 12.0]
        @test a.columns[:fitted] + a.columns[:residual] ≈ y_orig atol=1e-10
    end

    @testset "FD 一阶差分拟合" begin
        result = fit_panel(panel_data, "invest ~ mvalue + capital"; method=:fd)
        @test result isa PanelFitResult
        @test result.method === :fd

        g = glance(result)
        @test g.model === :fd
        @test g.nobs == 6  # 3 firms * (3-1) periods
        @test haskey(g.metrics, :r2)

        # Task 9: loglikelihood/aic/bic
        @test haskey(g.metrics, :loglikelihood)
        @test haskey(g.metrics, :aic)
        @test haskey(g.metrics, :bic)
        @test isfinite(g.metrics[:loglikelihood])
        @test isfinite(g.metrics[:aic])
        @test isfinite(g.metrics[:bic])

        t = tidy(result)
        @test length(t.rows) == 2  # mvalue + capital (no intercept)
        @test all(row -> row.pvalue !== nothing, t.rows)

        # Task 12: 置信区间
        @test all(row -> row.ci_lower !== nothing, t.rows)
        @test all(row -> row.ci_upper !== nothing, t.rows)
        @test all(row -> row.ci_lower < row.estimate < row.ci_upper, t.rows)

        # augment 验证：fitted + residual = Δy（差分空间）
        a = augment(result)
        @test a.nobs == 6
        @test haskey(a.columns, :std_residual)
        @test a.columns[:fitted] + a.columns[:residual] ≈
              result.fitted_values + result.residual_vector atol=1e-12
    end

    @testset "Between 组间估计拟合" begin
        result = fit_panel(panel_data, "invest ~ mvalue + capital"; method=:between)
        @test result isa PanelFitResult
        @test result.method === :between

        g = glance(result)
        @test g.model === :between
        @test g.nobs == 3  # 3 firms (group means)
        @test haskey(g.metrics, :r2)
        @test haskey(g.metrics, :nobs_original)
        @test g.metrics[:nobs_original] == 9

        # Task 9: loglikelihood/aic/bic
        @test haskey(g.metrics, :loglikelihood)
        @test haskey(g.metrics, :aic)
        @test haskey(g.metrics, :bic)

        t = tidy(result)
        @test length(t.rows) == 3  # intercept + mvalue + capital
        # 当自由度为 0 时，p 值为 NaN
        @test all(row -> row.pvalue === nothing || isnan(row.pvalue), t.rows)

        # Task 12: 置信区间（自由度为 0 时可能为 NaN）
        @test all(row -> row.ci_lower !== nothing, t.rows)
        @test all(row -> row.ci_upper !== nothing, t.rows)

        # augment 验证：fitted + residual = 组均值 y
        a = augment(result)
        @test a.nobs == 3
        @test a.columns[:fitted] + a.columns[:residual] ≈
              result.fitted_values + result.residual_vector atol=1e-12
    end

    @testset "PWT 教学数据面板拟合与诊断" begin
        root = dirname(dirname(dirname(@__DIR__)))
        pwt_path = joinpath(root, "datasets", "teaching", "pwt_productivity_panel.csv")
        if isfile(pwt_path)
            pwt_data = read_teaching_csv(pwt_path)
            pwt_panel = PanelData(pwt_data, :isocode, :year)
            formula = "log_output_per_worker ~ log_capital_per_worker + hc"

            result = fit_panel(pwt_panel, formula; method=:fe)
            @test result isa PanelFitResult
            @test glance(result).metrics[:n_ids] == 12
            @test glance(result).metrics[:n_times] == 30

            diagnostics = panel_diagnostics(pwt_panel, formula)
            @test diagnostics["fixed_effect_f"]["available"] == true
            @test diagnostics["breusch_pagan_lm"]["available"] == true
        else
            @test_skip "PWT 教学数据文件不存在: $pwt_path"
        end
    end
end

@testset "M7 HDFE 高维固定效应" begin
    df = DataFrame(
        firm = repeat(1:3, inner=4),
        year = repeat(1:4, outer=3),
        y = [10.0, 12.0, 14.0, 16.0, 20.0, 22.0, 24.0, 26.0, 30.0, 32.0, 34.0, 36.0],
        x1 = [1.0, 2.0, 3.0, 4.0, 2.0, 3.0, 4.0, 5.0, 3.0, 4.0, 5.0, 6.0],
    )
    pd = PanelData(df, :firm, :year)

    result = fit_hdfde(pd, "y ~ x1"; fe_spec=[:firm])
    @test result isa PanelFitResult
    @test result.method === :hdfde
    @test length(result.fitted_values) == 12

    g = glance(result)
    # Task 9: loglikelihood/aic/bic（完美拟合时 RSS=0 导致 loglik=Inf）
    @test haskey(g.metrics, :loglikelihood)
    @test haskey(g.metrics, :aic)
    @test haskey(g.metrics, :bic)
    # 仅在 RSS > 0 时验证有限性
    if g.metrics[:rss] > 0
        @test isfinite(g.metrics[:loglikelihood])
        @test isfinite(g.metrics[:aic])
        @test isfinite(g.metrics[:bic])
    else
        @test g.metrics[:loglikelihood] == Inf
        @test g.metrics[:aic] == -Inf
        @test g.metrics[:bic] == -Inf
    end

    t = tidy(result)
    @test t.rows[1].name === :x1

    # Task 12: 置信区间（若标准误和区间均可计算）
    @test all(row -> row.ci_lower !== nothing, t.rows)
    @test all(row -> row.ci_upper !== nothing, t.rows)
    # 仅在标准误非零且有限时验证区间包含真值
    if all(row -> isfinite(row.stderror) && row.stderror > 0 && isfinite(row.ci_lower) && isfinite(row.ci_upper), t.rows)
        @test all(row -> row.ci_lower < row.estimate < row.ci_upper, t.rows)
    end

    # 第二个 HDFE 模型（双向固定效应）
    result2 = fit_hdfde(pd, "y ~ x1"; fe_spec=[:firm, :year])
    @test result2 isa PanelFitResult
    @test result2.method === :hdfde
    # 双向固定效应可能也有共线性问题，仅检查 key 存在
    @test haskey(glance(result2).metrics, :loglikelihood)
    @test haskey(glance(result2).metrics, :aic)
    @test haskey(glance(result2).metrics, :bic)

    # fit_panel dispatch
    result3 = fit_panel(pd, "y ~ x1"; method=:hdfde, fe_spec=[:firm])
    @test result3 isa PanelFitResult
end

@testset "M7 CRE/Mundlak" begin
    df = DataFrame(
        firm = repeat(1:3, inner=4),
        year = repeat(1:4, outer=3),
        y = [10.0, 12.0, 14.0, 16.0, 20.0, 22.0, 24.0, 26.0, 30.0, 32.0, 34.0, 36.0],
        x1 = [1.0, 2.0, 3.0, 4.0, 2.0, 3.0, 4.0, 5.0, 3.0, 4.0, 5.0, 6.0],
    )
    pd = PanelData(df, :firm, :year)

    result = fit_crea(pd, "y ~ x1")
    @test result isa PanelFitResult
    @test result.method === :cre
    @test any(startswith(String(r.name), "group_mean_") for r in tidy(result).rows)

    # fit_panel dispatch
    result2 = fit_panel(pd, "y ~ x1"; method=:cre)
    @test result2 isa PanelFitResult
    @test result2.method === :cre
end

@testset "M7 面板 IV" begin
    df = DataFrame(
        firm = repeat(1:5, inner=4),
        year = repeat(1:4, outer=5),
        y = randn(20) .+ 10,
        x1 = randn(20),
        z1 = randn(20),
    )
    pd = PanelData(df, :firm, :year)

    result = fit_panel_iv(pd, "y ~ x1"; instruments=["z1"], endog=["x1"])
    @test result isa PanelIVFitResult
    @test glance(result).model === :panel_iv
    @test length(tidy(result).rows) == 1
    @test tidy(result).rows[1].name === :x1
    @test length(result.first_stage_stats) == 1
    @test haskey(result.first_stage_stats, :x1)

    # Task 9: loglikelihood/aic/bic
    g = glance(result)
    @test haskey(g.metrics, :loglikelihood)
    @test haskey(g.metrics, :aic)
    @test haskey(g.metrics, :bic)
    @test isfinite(g.metrics[:loglikelihood])
    @test isfinite(g.metrics[:aic])
    @test isfinite(g.metrics[:bic])

    # Task 12: 置信区间
    t = tidy(result)
    @test all(row -> row.ci_lower !== nothing, t.rows)
    @test all(row -> row.ci_upper !== nothing, t.rows)
    @test all(row -> row.ci_lower < row.estimate < row.ci_upper, t.rows)

    # Task 13: Panel IV result_to_payload
    payload = result_to_payload(result)
    @test payload["status"] == "success"
    @test haskey(payload["result_payload"], "first_stage_stats")
    @test haskey(payload["result_payload"], "weak_instrument_warnings")
    @test haskey(payload["result_payload"]["first_stage_stats"], "x1")
    @test payload["result_payload"]["first_stage_stats"]["x1"] isa Float64
    # 置信区间也应在 tidy 载荷中
    @test haskey(payload["result_payload"]["tidy"][1], "ci_lower")
    @test haskey(payload["result_payload"]["tidy"][1], "ci_upper")

    firm = repeat(1:8, inner=5)
    year = repeat(1:5, outer=8)
    alpha = repeat(collect(1.0:8.0), inner=5)
    trend = repeat([-2.0, -1.0, 0.0, 1.0, 2.0], outer=8)
    z = alpha .+ trend
    x = alpha .+ z
    y = alpha .+ 2.0 .* x
    correlated_df = DataFrame(firm=firm, year=year, y=y, x=x, z=z)
    correlated_panel = PanelData(correlated_df, :firm, :year)

    correlated_result = fit_panel_iv(correlated_panel, "y ~ x"; instruments=["z"], endog=["x"])
    @test correlated_result isa PanelIVFitResult
    @test only(correlated_result.coefficient_names) === :x
    @test only(correlated_result.coefficient_values) ≈ 2.0 atol=1e-8
end

@testset "M7 Driscoll-Kraay" begin
    df = DataFrame(
        firm = repeat(1:5, inner=4),
        year = repeat(1:4, outer=5),
        y = randn(20) .+ 10,
        x1 = randn(20),
    )
    pd = PanelData(df, :firm, :year)

    fe_result = fit_panel(pd, "y ~ x1"; method=:fe)
    X = hcat(ones(20), Float64.(df[!, :x1]))
    dk_result = compute_dk_vcov(fe_result.residual_vector, X, pd)
    @test dk_result isa Tuple
    vcov_mat, se = dk_result
    @test length(se) == 2
    @test all(se .> 0)
end

@testset "M7 升级诊断" begin
    gf = DataFrame(
        firm = repeat(1:3, inner=4),
        year = repeat(1:4, outer=3),
        invest = [317.99, 391.85, 410.19, 257.70, 247.68, 330.57, 461.46, 512.80, 308.20, 395.81, 420.73, 400.60],
        mvalue = [3078.5, 4691.2, 5668.6, 5022.4, 2759.4, 3812.5, 5006.8, 5869.3, 2768.9, 4303.5, 5459.1, 5324.6],
        capital = [2.8, 52.6, 156.9, 209.2, 302.4, 360.7, 478.3, 555.4, 206.4, 336.5, 462.3, 476.7],
    )
    panel_data = PanelData(gf, :firm, :year)

    diag = panel_diagnostics(panel_data, "invest ~ mvalue + capital")

    # Hausman 检验（小样本可能不可用）
    @test diag["hausman"]["method"] == "hausman_fe_re_v2"
    @test diag["hausman"]["available"] isa Bool

    # BP LM 支持平衡面板
    @test diag["breusch_pagan_lm"]["available"] == true
    @test diag["breusch_pagan_lm"]["method"] == "breusch_pagan_re_lm"

    # F 检验
    @test diag["fixed_effect_f"]["available"] == true
end

@testset "S5.2 差分动态面板 GMM" begin
    df = CSV.read(DPGMM_DEMO, DataFrame)
    pd = PanelData(df, :firm, :year)
    r = fit_dynamic_panel_gmm(pd, "y ~ x"; instrument_lags = (2, 4), gmm_weight = "two_step")
    @test r isa DynamicPanelGMMFitResult
    @test r.n_instruments == 4  # 3 个 y 滞后层 + 1 个 Δx
    @test r.n_obs_diff == 6      # 每截面 2 个有效差分时期 × 3 截面
    g = glance(r)
    @test g.model === :dynamic_panel_gmm
    @test haskey(r.diagnostics, :ar1_test)
    @test haskey(r.diagnostics, :ar2_test)
    @test haskey(r.diagnostics[:hansen_j], :j_statistic)
    pl = result_to_payload(r; include_augment = false)
    @test pl["status"] == "success"
    d = pl["result_payload"]["diagnostics"]
    @test haskey(d, "ar1_test")
    @test haskey(d, "j_statistic")
end

@testset "S5.2 System GMM" begin
    df = CSV.read(DPGMM_DEMO, DataFrame)
    pd = PanelData(df, :firm, :year)
    r = fit_dynamic_panel_gmm(pd, "y ~ x"; instrument_lags = (2, 3),
                               dpgmm_style = "system", gmm_weight = "two_step")
    @test r isa DynamicPanelGMMFitResult
    @test haskey(r.diagnostics, :diff_hansen)
    @test get(r.diagnostics, :dpgmm_style, "") == "system"
    @test r.n_instruments > 4  # System 有更多工具
end

@testset "S5.2 Collapsed instruments" begin
    df = CSV.read(DPGMM_DEMO, DataFrame)
    pd = PanelData(df, :firm, :year)
    r = fit_dynamic_panel_gmm(pd, "y ~ x"; instrument_lags = (2, 4),
                               collapse_instruments = true)
    @test r isa DynamicPanelGMMFitResult
    @test r.n_instruments == 2  # 1 列 collapsed + 1 外生
end

@testset "S5.2 Golden-value: deterministic dynamic panel fixture" begin
    golden_path = joinpath(dirname(@__DIR__), "..", "..", "datasets", "demo", "dynamic_panel_gmm_golden.csv")
    df = CSV.read(golden_path, DataFrame)
    pd = PanelData(df, :firm, :year)

    # Difference GMM (two-step) on deterministic fixture
    r = fit_dynamic_panel_gmm(pd, "y ~ x"; instrument_lags=(2, 4), gmm_weight="two_step")
    @test r isa DynamicPanelGMMFitResult

    # 样本校验：30 个体 × 10 时期 → 差分样本 = 30 × (10-4) = 180
    @test r.n_obs_diff == 180
    @test get(r.diagnostics, :n_groups, 0) == 30

    # 系数 golden：锁定当前内部 IV-GMM 堆叠口径，防止矩阵装配漂移。
    γ_idx = findfirst(n -> n == :L1Dy, r.coefficient_names)
    β_idx = findfirst(n -> n == :D_x, r.coefficient_names)
    @test γ_idx !== nothing
    @test β_idx !== nothing
    γ_hat = r.coefficient_values[γ_idx]
    β_hat = r.coefficient_values[β_idx]
    @test γ_hat ≈ 0.9717755159202648 atol=1e-10
    @test β_hat ≈ 0.010630646965193379 atol=1e-10

    # AR(1) 应显著（差分设定下常规），AR(2) 应不显著
    ar1_p = get(get(r.diagnostics, :ar1_test, Dict()), :pvalue, 1.0)
    ar2_p = get(get(r.diagnostics, :ar2_test, Dict()), :pvalue, 1.0)
    @test ar1_p < 0.05   # 一阶序列相关（预期）
    @test ar2_p > 0.01   # 二阶无序列相关（模型设定正确）

    # Hansen J 统计量保持确定性；该 fixture 当前并非外部参考 DGP。
    hj = get(r.diagnostics, :hansen_j, Dict())
    @test get(hj, :j_statistic, Inf) > 0
    j_pv = get(hj, :j_pvalue, 0.0)
    @test isnothing(j_pv) || 0.0 <= j_pv <= 1.0

    # === System GMM golden ===
    r_sys = fit_dynamic_panel_gmm(pd, "y ~ x"; instrument_lags=(2, 4), dpgmm_style="system")
    @test r_sys isa DynamicPanelGMMFitResult
    @test get(r_sys.diagnostics, :dpgmm_style, "") == "system"

    # System GMM 系数同样锁定当前确定性 fixture。
    γ_sys = r_sys.coefficient_values[findfirst(n -> n == :L1Dy, r_sys.coefficient_names)]
    β_sys = r_sys.coefficient_values[findfirst(n -> n == :D_x, r_sys.coefficient_names)]
    @test γ_sys ≈ 1.2252004620851213 atol=1e-10
    @test β_sys ≈ 0.705863546893492 atol=1e-10

    # System GMM 应有 Diff-Hansen
    @test haskey(r_sys.diagnostics, :diff_hansen)
    dh = r_sys.diagnostics[:diff_hansen]
    @test get(dh, :c_statistic, NaN) >= 0
end
