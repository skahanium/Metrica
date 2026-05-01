using Test
using MetricaBase
using MetricaPanel
using Statistics

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
end
