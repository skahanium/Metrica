using Test
using MetricaBase
using MetricaPanel

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

        # 检查 augment
        a = augment(result)
        @test a isa MetricaBase.AugmentTable
        @test a.nobs == 9
        @test haskey(a.columns, :fitted)
        @test haskey(a.columns, :residual)
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
    end
end
