using MetricaData
using DataFrames
using Test

@testset "MetricaData.jl" begin
    @testset "query" begin
        include("test_query.jl")
    end
    @testset "transform" begin
        include("test_transform.jl")
    end
    @testset "reshape" begin
        include("test_reshape.jl")
    end
    @testset "combine" begin
        include("test_combine.jl")
    end
    @testset "join" begin
        include("test_join.jl")
    end
end
