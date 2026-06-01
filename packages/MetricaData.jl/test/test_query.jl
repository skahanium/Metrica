using CSV

@testset "describe_dataset 返回真实变量与数据集规模" begin
    df = DataFrame(region = ["A", "B"], year = [2020, 2021], y = [1.0, 2.0])
    with_temp_csv(df) do path
        result = MetricaData.describe_dataset(path; variables = ["year", "y"])

        @test result["status"] == "success"
        payload = result["result_payload"]
        @test payload["kind"] == "describe"
        @test payload["dataset_summary"]["row_count"] == 2
        @test payload["dataset_summary"]["column_count"] == 3
        @test [item["name"] for item in payload["variables"]] == ["year", "y"]
    end
end

@testset "summarize_dataset 对数值列给出 Stata 风格默认统计量" begin
    df = DataFrame(
        y = [1.0, 3.0, 5.0],
        group = ["a", "b", "a"],
    )
    with_temp_csv(df) do path
        result = MetricaData.summarize_dataset(path; variables = ["y", "group"])

        @test result["status"] == "success"
        payload = result["result_payload"]
        @test payload["kind"] == "summarize"

        y_row = only(Base.filter(item -> item["name"] == "y", payload["variables"]))
        @test y_row["obs"] == 3
        @test y_row["mean"] ≈ 3.0
        @test y_row["std_dev"] ≈ 2.0
        @test y_row["min"] ≈ 1.0
        @test y_row["max"] ≈ 5.0

        group_row = only(Base.filter(item -> item["name"] == "group", payload["variables"]))
        @test group_row["obs"] == 3
        @test isnothing(group_row["mean"])
        @test isnothing(group_row["std_dev"])
        @test isnothing(group_row["min"])
        @test isnothing(group_row["max"])
    end
end

@testset "tabulate_dataset 默认排除缺失并按变量值顺序输出累计百分比" begin
    df = DataFrame(
        id = 1:5,
        code = Union{Missing, Int}[2, missing, 1, 2, 1],
    )
    with_temp_csv(df) do path
        result = MetricaData.tabulate_dataset(path; variable = "code")

        @test result["status"] == "success"
        payload = result["result_payload"]
        @test payload["kind"] == "tabulate"
        @test payload["variable"] == "code"
        @test payload["total"] == 4
        @test payload["missing_count"] == 1
        @test [item["value"] for item in payload["rows"]] == ["1", "2"]
        @test [item["count"] for item in payload["rows"]] == [2, 2]
        @test payload["rows"][1]["cum_pct"] ≈ 50.0
        @test payload["rows"][2]["cum_pct"] ≈ 100.0
    end
end

@testset "browse_dataset 校验变量并返回只读浏览配置" begin
    df = DataFrame(y = [1.0, 2.0], x = [3.0, 4.0])
    with_temp_csv(df) do path
        ok_result = MetricaData.browse_dataset(path; variables = ["x"])
        @test ok_result["status"] == "success"
        ok_payload = ok_result["result_payload"]
        @test ok_payload["kind"] == "browse"
        @test ok_payload["readonly"] == true
        @test [item["name"] for item in ok_payload["columns"]] == ["x"]

        bad_result = MetricaData.browse_dataset(path; variables = ["missing_col"])
        @test bad_result["status"] == "error"
        @test bad_result["messages"][1]["code"] == "unknown_variable"
    end
end

@testset "describe_dataset without variables returns all columns" begin
    df = DataFrame(a = [1, 2], b = [3.0, 4.0])
    with_temp_csv(df) do path
        result = MetricaData.describe_dataset(path)
        @test result["status"] == "success"
        payload = result["result_payload"]
        @test payload["kind"] == "describe"
        @test [item["name"] for item in payload["variables"]] == ["a", "b"]
    end
end

@testset "summarize_dataset with missing numeric values" begin
    df = DataFrame(
        y = Union{Missing, Float64}[1.0, missing, 5.0, missing, 9.0],
        group = ["a", "b", "a", "b", "a"],
    )
    with_temp_csv(df) do path
        result = MetricaData.summarize_dataset(path)
        @test result["status"] == "success"
        payload = result["result_payload"]
        @test payload["kind"] == "summarize"
        y_row = only(Base.filter(item -> item["name"] == "y", payload["variables"]))
        @test y_row["obs"] == 3
        @test y_row["mean"] ≈ 5.0
    end
end

@testset "browse_dataset empty dataset" begin
    df = DataFrame(x = Float64[], y = String[])
    with_temp_csv(df) do path
        result = MetricaData.browse_dataset(path)
        @test result["status"] == "success"
        payload = result["result_payload"]
        @test payload["kind"] == "browse"
        @test payload["dataset_summary"]["row_count"] == 0
    end
end

@testset "tabulate_dataset truncation emits ModelWarning envelope" begin
    codes = string.(1:25)
    df = DataFrame(code = codes)
    with_temp_csv(df) do path
        result = MetricaData.tabulate_dataset(path; variable = "code", max_levels = 5)
        @test result["status"] == "success"
        msgs = result["messages"]
        @test length(msgs) == 1
        @test msgs[1]["severity"] == "warning"
        @test msgs[1]["code"] == "tabulate_truncated"
        @test occursin("5", msgs[1]["detail"])
        payload = result["result_payload"]
        @test payload["truncated"] == true
        @test length(payload["rows"]) == 5
    end
end

@testset "tabulate_dataset all same value" begin
    df = DataFrame(code = ["a", "a", "a"])
    with_temp_csv(df) do path
        result = MetricaData.tabulate_dataset(path; variable = "code")
        @test result["status"] == "success"
        payload = result["result_payload"]
        @test length(payload["rows"]) == 1
        @test payload["rows"][1]["count"] == 3
        @test payload["rows"][1]["cum_pct"] ≈ 100.0
    end
end
