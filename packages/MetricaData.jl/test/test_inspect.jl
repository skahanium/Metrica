using MetricaData
using DataFrames
using Test
using CSV

if !@isdefined(with_temp_csv)
    function with_temp_csv(f::Function, df::DataFrame)
        path = tempname() * ".csv"
        CSV.write(path, df)
        try
            return f(path)
        finally
            rm(path; force = true)
        end
    end
end

@testset "inspect_dataset basic" begin
    df = DataFrame(y = [1.0, 2.0], x = [3.0, 4.0])
    with_temp_csv(df) do path
        result = MetricaData.inspect_dataset(path; preview_limit = 2)
        @test result["status"] == "success"
        payload = result["result_payload"]
        @test payload["dataset_summary"]["row_count"] == 2
        @test payload["dataset_summary"]["column_count"] == 2
        @test length(payload["columns"]) == 2
        @test length(payload["preview_rows"]) == 2
        @test payload["columns"][1]["name"] == "y"
        @test payload["columns"][1]["inferred_type"] == "Float64"
        @test payload["columns"][1]["missing_count"] == 0
        @test payload["columns"][1]["non_missing_count"] == 2
    end
end

@testset "inspect_dataset missing file" begin
    result = MetricaData.inspect_dataset("/tmp/does-not-exist-metrica-test.csv")
    @test result["status"] == "error"
    @test result["messages"][1]["code"] == "dataset_not_found"
end

@testset "inspect_dataset with missing values" begin
    df = DataFrame(
        y = Union{Missing, Float64}[1.0, missing, 3.0],
        x = [4.0, 5.0, 6.0],
    )
    with_temp_csv(df) do path
        result = MetricaData.inspect_dataset(path)
        @test result["status"] == "success"
        payload = result["result_payload"]
        y_col = only(Base.filter(c -> c["name"] == "y", payload["columns"]))
        @test y_col["missing_count"] == 1
        @test y_col["non_missing_count"] == 2
    end
end

@testset "inspect_dataset preview truncation" begin
    df = DataFrame(x = 1:10, y = 11:20)
    with_temp_csv(df) do path
        result = MetricaData.inspect_dataset(path; preview_limit = 3)
        @test length(result["result_payload"]["preview_rows"]) == 3
    end
end

@testset "inspect_dataset default preview limit" begin
    df = DataFrame(x = 1:10, y = 11:20)
    with_temp_csv(df) do path
        result = MetricaData.inspect_dataset(path)
        @test length(result["result_payload"]["preview_rows"]) == 5
    end
end
