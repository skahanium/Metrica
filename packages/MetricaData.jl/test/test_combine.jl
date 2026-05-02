using MetricaData
using DataFrames
using Test

@testset "filter" begin
    df = DataFrame(x = [1, 2, 3], y = [4, 5, 6])
    result = MetricaData.filter(df, "x > 1")
    @test nrow(result.df) == 2
    @test result.df.x == [2, 3]
end

@testset "sort" begin
    df = DataFrame(x = [3, 1, 2], y = [6, 4, 5])
    result = MetricaData.sort(df, [:x])
    @test result.df.x == [1, 2, 3]
end

@testset "collapse" begin
    df = DataFrame(
        group = ["A", "A", "B", "B"],
        value = [10, 20, 30, 40],
    )
    result = collapse(df, [:group], ["mean", "sum"], [:value])
    @test nrow(result.df) == 2
    @test "value_mean" in names(result.df)
    @test "value_sum" in names(result.df)
end
