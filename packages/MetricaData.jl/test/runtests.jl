using MetricaData
using DataFrames
using Test

include("test_support.jl")

@testset "MetricaData.jl" begin
    @testset "query" begin
        include("test_query.jl")
    end
    @testset "inspect" begin
        include("test_inspect.jl")
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
    @testset "operate" begin
        include("test_operate.jl")
    end
    @testset "serialize" begin
        include("test_serialize_md.jl")
    end
    @testset "warning protocol" begin
        include("test_warning_protocol.jl")
    end
    @testset "glance protocol" begin
        include("test_glance_protocol.jl")
    end
end
