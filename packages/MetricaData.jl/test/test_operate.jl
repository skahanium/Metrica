using MetricaData
using DataFrames
using Test

@testset "operate filter" begin
    df = DataFrame(x = [1, 2, 3], y = [4, 5, 6])
    result = MetricaData.operate(df, Dict{String, Any}("op" => "filter", "args" => Dict{String, Any}("condition" => "x > 1")))
    @test result.status == "ok"
    @test nrow(result.df) == 2
    @test result.df.x == [2, 3]
end

@testset "operate generate" begin
    df = DataFrame(x = [1, 2, 3], y = [4, 5, 6])
    result = MetricaData.operate(df, Dict{String, Any}("op" => "generate", "args" => Dict{String, Any}("name" => "z", "expr" => "x + y")))
    @test result.status == "ok"
    @test result.df.z == [5, 7, 9]
end

@testset "operate rename" begin
    df = DataFrame(x = [1, 2], y = [3, 4])
    result = MetricaData.operate(df, Dict{String, Any}("op" => "rename", "args" => Dict{String, Any}("mapping" => Dict("x" => "value"))))
    @test result.status == "ok"
    @test "value" in names(result.df)
    @test !("x" in names(result.df))
end

@testset "operate drop" begin
    df = DataFrame(x = [1, 2], y = [3, 4], z = [5, 6])
    result = MetricaData.operate(df, Dict{String, Any}("op" => "drop", "args" => Dict{String, Any}("cols" => ["z"])))
    @test result.status == "ok"
    @test names(result.df) == ["x", "y"]
end

@testset "operate keep" begin
    df = DataFrame(x = [1, 2], y = [3, 4], z = [5, 6])
    result = MetricaData.operate(df, Dict{String, Any}("op" => "keep", "args" => Dict{String, Any}("cols" => ["x"])))
    @test result.status == "ok"
    @test names(result.df) == ["x"]
end

@testset "operate sort" begin
    df = DataFrame(x = [3, 1, 2], y = [6, 4, 5])
    result = MetricaData.operate(df, Dict{String, Any}("op" => "sort", "args" => Dict{String, Any}("cols" => ["x"])))
    @test result.status == "ok"
    @test result.df.x == [1, 2, 3]
end

@testset "operate unknown op" begin
    df = DataFrame(x = [1])
    result = MetricaData.operate(df, Dict{String, Any}("op" => "bogus", "args" => Dict{String, Any}("x" => 1)))
    @test result.status == "error"
    @test occursin("Unknown operation", result.error["message"])
end

@testset "operate replace" begin
    df = DataFrame(x = [1, 2, 3], flag = ["a", "b", "a"])
    result = MetricaData.operate(df, Dict{String, Any}("op" => "replace", "args" => Dict{String, Any}(
        "col" => "flag", "condition" => "x >= 2", "value" => "\"c\"",
    )))
    @test result.status == "ok"
    @test result.df.flag == ["a", "c", "c"]
end
