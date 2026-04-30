using Test
using MetricaBase
using MetricaOutput

@testset "summary_card 与 markdown_regtable" begin
    glance = ModelGlance(
        :ols,
        8,
        5,
        Dict(:r2 => 0.84, :adj_r2 => 0.79, :sigma => 0.49),
        ModelWarning[],
    )
    tidy = TidyTable(
        [
            CoefRow(:Intercept, 1.0, 0.1, 10.0, 0.001),
            CoefRow(:x1, 2.0, 0.2, 10.0, 0.001),
        ],
        "classical",
    )

    summary = summary_card(glance)
    table = markdown_regtable(tidy)

    @test occursin("R²", summary)
    @test occursin("调整 R²", summary)
    @test occursin("| 参数 |", table)
    @test occursin("Intercept", table)
end
