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
