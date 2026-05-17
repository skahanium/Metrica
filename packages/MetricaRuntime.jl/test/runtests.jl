using Test
using MetricaRuntime

@testset "MetricaRuntime aggregate package" begin
    @test isdefined(MetricaRuntime, :MetricaRuntime)
end
