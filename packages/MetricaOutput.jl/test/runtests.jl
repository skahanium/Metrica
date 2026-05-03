using Test
using MetricaBase
using MetricaOutput

@testset "summary_card 与 markdown_regtable" begin
    glance = ModelGlance(
        :ols,
        8,
        5,
        Dict(:r2 => 0.84, :adj_r2 => 0.79, :sigma => 0.49),
        ModelWarning[],
    )
    tidy = TidyTable(
        [
            CoefRow(:Intercept, 1.0, 0.1, 10.0, 0.001),
            CoefRow(:x1, 2.0, 0.2, 10.0, 0.001),
        ],
        "classical",
    )

    summary = summary_card(glance)
    table = markdown_regtable(tidy)

    @test occursin("R²", summary)
    @test occursin("调整 R²", summary)
    @test occursin("| 参数 |", table)
    @test occursin("Intercept", table)
end

@testset "markdown_run_report" begin
    run_record = Dict(
        "dataset_ref" => Dict("path" => "/tmp/demo.csv"),
        "model_spec" => Dict("model_type" => "ols", "formula" => "y ~ x1 + x2"),
        "finished_at" => "2026-05-03T12:00:00Z",
        "messages" => [Dict("code" => "INFO", "text" => "ok")],
    )
    result = Dict(
        "glance" => Dict("model" => "ols", "nobs" => 8, "dof" => 5, "metrics" => Dict("r2" => 0.84)),
        "tidy" => [
            Dict("term" => "Intercept", "estimate" => 1.0, "std_error" => 0.1, "statistic" => 10.0, "p_value" => 0.001),
        ],
        "warnings" => [Dict("title" => "样本变化", "detail" => "删除了 2 行缺失值")],
        "vcov_label" => "classical",
    )

    report = markdown_run_report(run_record, result)
    @test occursin("# Metrica 单次运行报告", report)
    @test occursin("/tmp/demo.csv", report)
    @test occursin("y ~ x1 + x2", report)
    @test occursin("| 参数 |", report)
    @test occursin("样本变化", report)
end

@testset "csv_tidy" begin
    result = Dict(
        "tidy" => [
            Dict("term" => "Intercept", "estimate" => 1.0, "std_error" => 0.1, "statistic" => 10.0, "p_value" => 0.001),
            Dict("term" => "x1", "estimate" => 2.0, "std_error" => 0.2, "statistic" => 10.0, "p_value" => 0.001),
        ],
    )
    csv = csv_tidy(result)
    @test occursin("term,estimate,std_error,statistic,p_value", csv)
    @test occursin("Intercept,1.0,0.1,10.0,0.001", csv)
    @test occursin("x1,2.0,0.2,10.0,0.001", csv)
end

@testset "csv_glance" begin
    result = Dict(
        "glance" => Dict(
            "model" => "ols",
            "nobs" => 100,
            "dof" => 3,
            "metrics" => Dict("r2" => 0.84, "adj_r2" => 0.83),
        ),
    )
    csv = csv_glance(result)
    @test occursin("metric,value", csv)
    @test occursin("model,ols", csv)
    @test occursin("nobs,100", csv)
    @test occursin("r2,0.84", csv)
end

@testset "csv_diagnostics" begin
    result = Dict(
        "diagnostics" => Dict(
            "breusch_pagan" => Dict("statistic" => 3.2, "pvalue" => 0.0736, "dof" => 2, "available" => true),
            "jarque_bera" => Dict("statistic" => 0.82, "pvalue" => 0.6637, "available" => true),
        ),
    )
    csv = csv_diagnostics(result)
    @test occursin("diagnostic,statistic,pvalue,dof,available", csv)
    @test occursin("breusch_pagan,3.2,0.0736,2,true", csv)
    @test occursin("jarque_bera,0.82,0.6637,,true", csv)
end
