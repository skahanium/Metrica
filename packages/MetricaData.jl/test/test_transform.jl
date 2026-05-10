using MetricaData
using DataFrames
using Test

@testset "generate" begin
    df = DataFrame(x = [1, 2, 3], y = [4, 5, 6])
    result = generate(df, "z", "x + y")
    @test result.df.z == [5, 7, 9]
end

@testset "replace" begin
    df = DataFrame(x = [1, 2, 3], flag = ["a", "b", "a"])
    result = MetricaData.replace(df, "flag", "x > 1", "\"c\"")
    @test result.df.flag == ["a", "c", "c"]
end

@testset "rename" begin
    df = DataFrame(x = [1, 2, 3])
    result = MetricaData.rename(df, Dict("x" => "value"))
    @test "value" in names(result.df)
    @test !("x" in names(result.df))
end

@testset "drop" begin
    df = DataFrame(x = [1, 2], y = [3, 4], z = [5, 6])
    result = drop(df, [:z])
    @test names(result.df) == ["x", "y"]
end

@testset "keep" begin
    df = DataFrame(x = [1, 2], y = [3, 4], z = [5, 6])
    result = keep(df, [:x])
    @test names(result.df) == ["x"]
end

@testset "impute_missing uses mean median and mode" begin
    df = DataFrame(
        xf = Union{Missing, Float64}[1.0, missing, 3.0],
        xi = Union{Missing, Int}[1, missing, 5],
        xs = Union{Missing, String}["a", missing, "a"],
        xb = Union{Missing, Bool}[true, missing, true],
    )
    result = impute_missing(df)

    @test result.status == "ok"
    @test result.df.xf[2] == 2.0
    @test result.df.xi[2] == 3.0
    @test result.df.xs[2] == "a"
    @test result.df.xb[2] == true
    @test occursin("xf=均值", result.notes)
    @test occursin("xi=中位数", result.notes)
    @test occursin("xs=众数", result.notes)
end

@testset "impute_missing skips all-missing columns with warning" begin
    df = DataFrame(
        x = Union{Missing, Int}[missing, missing],
        y = Union{Missing, Float64}[1.0, missing],
    )
    result = impute_missing(df)

    @test result.status == "ok"
    @test !isempty(result.warnings)
    @test occursin("x", result.warnings[1]["detail"])
    @test result.df.y[2] == 1.0
end

@testset "operate_chain impute_missing reports no-op note for complete data" begin
    df = DataFrame(x = [1, 2], y = ["a", "b"])
    result = operate_chain(
        df,
        Dict{String, Any}[
            Dict("op" => "impute_missing", "args" => Dict{String, Any}()),
        ],
    )

    @test result["status"] == "ok"
    @test result["result"]["notes"] == "未发现需要插补的列。"
end

@testset "operate_chain success writes derived csv" begin
    df = DataFrame(x = [1, 2, 3], y = [4, 5, 6])
    output_path = tempname() * ".csv"
    result = operate_chain(
        df,
        Dict{String, Any}[
            Dict("op" => "filter", "args" => Dict{String, Any}("condition" => "x >= 2")),
            Dict("op" => "generate", "args" => Dict{String, Any}("name" => "z", "expr" => "x + y")),
        ];
        output_path,
        preview_rows = 1,
    )

    @test result["status"] == "ok"
    @test result["result"]["dataset_path"] == output_path
    @test isfile(output_path)
    @test length(result["preview"]["rows"]) == 1
    @test length(result["operations"]) == 2
    rm(output_path; force = true)
end

@testset "operate_chain failure does not write output" begin
    df = DataFrame(x = [1, 2, 3], y = [4, 5, 6])
    output_path = tempname() * ".csv"
    result = operate_chain(
        df,
        Dict{String, Any}[
            Dict("op" => "generate", "args" => Dict{String, Any}("name" => "z", "expr" => "missing_col + 1")),
        ];
        output_path,
    )

    @test result["status"] == "error"
    @test result["error"]["op_index"] == 1
    @test occursin("missing_col", result["error"]["message"])
    @test !isfile(output_path)
end

@testset "operate_chain merge missing file reports structured error" begin
    df = DataFrame(id = [1, 2], x = [10, 20])
    result = operate_chain(
        df,
        Dict{String, Any}[
            Dict(
                "op" => "merge",
                "args" => Dict{String, Any}(
                    "with" => "/tmp/metrica-missing-file.csv",
                    "on" => ["id"],
                    "how" => "inner",
                ),
            ),
        ],
    )

    @test result["status"] == "error"
    @test result["error"]["op_index"] == 1
    @test occursin("metrica-missing-file.csv", result["error"]["message"])
end
