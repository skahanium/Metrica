using MetricaData
using DataFrames
using Test

@testset "merge inner" begin
    left = DataFrame(id = [1, 2, 3], v1 = [10, 20, 30])
    right = DataFrame(id = [2, 3, 4], v2 = [200, 300, 400])
    result = MetricaData.merge(left, right, ["id"], "inner")
    @test nrow(result.df) == 2
    @test "v1" in names(result.df)
    @test "v2" in names(result.df)
end

@testset "merge left" begin
    left = DataFrame(id = [1, 2, 3], v1 = [10, 20, 30])
    right = DataFrame(id = [2, 3, 4], v2 = [200, 300, 400])
    result = MetricaData.merge(left, right, ["id"], "left")
    @test nrow(result.df) == 3
end

@testset "merge with notes" begin
    left = DataFrame(id = [1, 2], v1 = [10, 20])
    right = DataFrame(id = [1, 3], v2 = [100, 300])
    result = MetricaData.merge(left, right, ["id"], "inner")
    @test contains(result.notes, "1 matched")
end
