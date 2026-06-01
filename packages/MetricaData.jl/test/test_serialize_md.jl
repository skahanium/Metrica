using MetricaData
using DataFrames
using Test

@testset "result_to_dict success path" begin
    df = DataFrame(x = [1, 2, 3], y = [4, 5, 6])
    result = MetricaData.generate(df, "z", "x + y")
    d = MetricaData.result_to_dict(result; preview_rows = 2)
    @test d["operation"] == "generate"
    @test d["status"] == "ok"
    @test d["result"]["nrows"] == 3
    @test d["result"]["ncols"] == 3
    @test length(d["preview"]["rows"]) == 2
    @test d["preview"]["columns"] == ["x", "y", "z"]
end

@testset "result_to_dict error path" begin
    df = DataFrame(x = [1])
    result = MetricaData.operate(df, Dict{String, Any}("op" => "bogus", "args" => Dict{String, Any}("x" => 1)))
    d = MetricaData.result_to_dict(result)
    @test d["status"] == "error"
    @test haskey(d, "error")
end

@testset "result_to_dict preview truncation" begin
    df = DataFrame(x = 1:100)
    result = MetricaData.generate(df, "z", "x * 2")
    d = MetricaData.result_to_dict(result; preview_rows = 5)
    @test length(d["preview"]["rows"]) == 5
end

@testset "result_to_dict warnings passthrough" begin
    df = DataFrame(x = Union{Missing, Float64}[1.0, missing, 3.0])
    result = MetricaData.impute_missing(df)
    d = MetricaData.result_to_dict(result)
    @test d["status"] == "ok"
    @test haskey(d, "warnings")
end

@testset "result_to_dict default preview" begin
    df = DataFrame(x = 1:20)
    result = MetricaData.generate(df, "z", "x * 2")
    d = MetricaData.result_to_dict(result)
    @test length(d["preview"]["rows"]) == 10
end
