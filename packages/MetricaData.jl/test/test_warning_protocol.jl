using Test
using DataFrames
using MetricaData

@testset "ModelWarning messages envelope fields" begin
    codes = string.(1:25)
    df = DataFrame(code = codes)
    with_temp_csv(df) do path
        result = MetricaData.tabulate_dataset(path; variable = "code", max_levels = 5)
        msgs = result["messages"]
        @test !isempty(msgs)
        for m in msgs
            @test haskey(m, "severity")
            @test haskey(m, "code")
            @test haskey(m, "detail")
            @test m["severity"] isa String
            @test m["code"] isa String
            @test m["detail"] isa String
        end
    end
end
