using Test
using DataFrames
using MetricaBase
using MetricaPanel
using Statistics

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
        @test haskey(g.metrics, :r2)
        @test haskey(g.metrics, :adj_r2)
        @test haskey(g.metrics, :n_ids)
        @test haskey(g.metrics, :n_times)
        @test g.metrics[:n_ids] == 3
        @test g.metrics[:n_times] == 3

        # 检查 tidy
        t = tidy(result)
        @test length(t.rows) == 3  # intercept + mvalue + capital
        @test t.vcov_label == "classical"
        @test all(row -> row.pvalue !== nothing, t.rows)

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
        @test haskey(payload["result_payload"]["augment_preview"], "fitted")
        @test haskey(payload["result_payload"]["augment_preview"], "std_residual")
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
    end

    @testset "RE 随机效应拟合" begin
        result = fit_panel(panel_data, "invest ~ mvalue + capital"; method=:re)
        @test result isa PanelFitResult
        @test result.method === :re

        g = glance(result)
        @test g.model === :re
        @test g.nobs == 9
        @test haskey(g.metrics, :r2)
        @test haskey(g.metrics, :n_ids)
        @test g.metrics[:n_ids] == 3

        t = tidy(result)
        @test length(t.rows) == 5  # intercept + 2 predictors + 2 group means
        @test all(row -> row.pvalue !== nothing, t.rows)

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

        t = tidy(result)
        @test length(t.rows) == 2  # mvalue + capital (no intercept)
        @test all(row -> row.pvalue !== nothing, t.rows)

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

        t = tidy(result)
        @test length(t.rows) == 3  # intercept + mvalue + capital
        # 当自由度为 0 时，p 值为 NaN
        @test all(row -> row.pvalue === nothing || isnan(row.pvalue), t.rows)

        # augment 验证：fitted + residual = 组均值 y
        a = augment(result)
        @test a.nobs == 3
        @test a.columns[:fitted] + a.columns[:residual] ≈
              result.fitted_values + result.residual_vector atol=1e-12
    end

    @testset "PWT 教学数据面板拟合与诊断" begin
        root = dirname(dirname(dirname(@__DIR__)))
        pwt_path = joinpath(root, "datasets", "teaching", "pwt_productivity_panel.csv")
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
    @test tidy(result).rows[1].name === :x1

    result2 = fit_hdfde(pd, "y ~ x1"; fe_spec=[:firm, :year])
    @test result2 isa PanelFitResult
    @test result2.method === :hdfde

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
    @test length(tidy(result).rows) == 2
    @test length(result.first_stage_stats) == 1
    @test haskey(result.first_stage_stats, :x1)
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
