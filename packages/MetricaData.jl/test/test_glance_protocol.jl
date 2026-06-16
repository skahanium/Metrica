using Test
using CSV
using DataFrames
using MetricaData
using MetricaBase

@testset "query commands expose ModelGlance-shaped glance" begin
    df = DataFrame(region = ["A", "B"], year = [2020, 2021], y = [1.0, 2.0])
    with_temp_csv(df) do path
        for (fn, kind) in (
            (MetricaData.inspect_dataset, "dataset_inspect"),
            (MetricaData.describe_dataset, "dataset_describe"),
            (MetricaData.browse_dataset, "dataset_browse"),
        )
            result = fn(path)
            @test result["status"] == "success"
            g = result["result_payload"]["glance"]
            @test g["model"] == kind
            @test g["nobs"] == 2
            @test g["dof"] == 3
            @test haskey(g["metrics"], "row_count")
            @test g["metrics"]["row_count"] == 2.0
            @test haskey(g["metrics"], "missing_cells")
        end

        sumr = MetricaData.summarize_dataset(path; variables = ["y"])
        @test sumr["result_payload"]["glance"]["model"] == "dataset_summarize"
        @test sumr["result_payload"]["glance"]["metrics"]["variables_summarized"] == 1.0

        tab = MetricaData.tabulate_dataset(path; variable = "region", max_levels = 10)
        @test tab["result_payload"]["glance"]["model"] == "dataset_tabulate"
        @test tab["result_payload"]["glance"]["metrics"]["tabulate_levels"] == 2.0
    end
end

@testset "query_error messages align with warning envelope fields" begin
    result = MetricaData.inspect_dataset("/tmp/metrica-nonexistent-glance-test.csv")
    @test result["status"] == "error"
    m = result["messages"][1]
    @test m["severity"] == "error"
    @test m["level"] == "error"
    @test haskey(m, "detail")
    @test haskey(m, "text")
end

@testset "transform chain errors expose structured status" begin
    df = DataFrame(x = [1.0, 2.0])
    result = MetricaData.operate_chain(
        df,
        [Dict{String, Any}(
            "op" => "generate",
            "args" => Dict{String, Any}("name" => "z", "expr" => "missing_col + 1"),
        )];
    )
    @test result["status"] == "error"
    @test haskey(result, "error")
    @test haskey(result["error"], "message")
end
