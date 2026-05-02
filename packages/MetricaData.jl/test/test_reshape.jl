using MetricaData
using DataFrames
using Test

@testset "reshape_long" begin
    wide = DataFrame(
        country = ["USA", "CAN"],
        gdp_2019 = [21.4, 1.7],
        gdp_2020 = [20.9, 1.6],
    )
    result = reshape_long(wide, [:country], "year", ["gdp"])
    @test nrow(result.df) == 4
    @test "year" in names(result.df)
    @test "gdp" in names(result.df)
end

@testset "reshape_wide" begin
    long = DataFrame(
        country = ["USA", "USA", "CAN", "CAN"],
        year = [2019, 2020, 2019, 2020],
        gdp = [21.4, 20.9, 1.7, 1.6],
    )
    result = reshape_wide(long, [:country], :year, [:gdp])
    @test nrow(result.df) == 2
    @test "gdp_2019" in names(result.df) || "gdp_2020" in names(result.df)
end
