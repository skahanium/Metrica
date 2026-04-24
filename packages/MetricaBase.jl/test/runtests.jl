# 在不在 Project.toml 里声明 Test 的情况下，让 `Pkg.test()` 里能 `using Test`
# （独立测试进程的 LOAD_PATH 上有时找不到标准库 Test）。
pushfirst!(
    LOAD_PATH,
    joinpath(Sys.BINDIR, "..", "share", "julia", "stdlib", "v$(VERSION.major).$(VERSION.minor)"),
)

using Test
using MetricaBase

@testset "MetricaBase：结构化契约（alpha 垂直切片）" begin
    warning = ModelWarning(
        :rows_dropped,
        "Rows dropped",
        "2 rows were removed due to missing values.",
        "Inspect missing columns before fitting.",
        :info,
    )

    gl = ModelGlance(
        :ols,
        10,
        7,
        Dict(:r2 => 0.8),
        [warning],
    )

    td = TidyTable(
        [
            CoefRow(:intercept, 1.0, 0.1, 10.0, 0.001),
            CoefRow(:x1, 2.0, 0.2, 10.0, 0.001),
        ],
        "classical",
    )

    @test gl.model == :ols
    @test gl.metrics[:r2] == 0.8
    @test td.rows[2].name == :x1
    @test td.vcov_label == "classical"
end
