using Test
using MetricaBase
using MetricaLinear

const DEMO_CSV = joinpath(
    dirname(dirname(dirname(@__DIR__))),
    "apps",
    "metrica-desktop",
    "data",
    "demo.csv",
)

@testset "真实 OLS 链路" begin
    ok = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    @test ok isa OLSFitResult
    @test glance(ok).model === :ols
    @test glance(ok).nobs == 7
    @test haskey(glance(ok).metrics, :r2)
    @test length(tidy(ok).rows) == 3
    @test any(w -> w.code === :rows_dropped, glance(ok).warnings)

    missing_col = fit_ols_file(DEMO_CSV, "y ~ x9")
    @test missing_col isa ModelError
    @test missing_col.code === :unknown_variable
end

@testset "奇异矩阵与空样本" begin
    singular_csv, singular_io = mktemp()
    close(singular_io)
    write(singular_csv, "y,x1,x2\n1,1,2\n2,2,4\n3,3,6\n")

    singular = fit_ols_file(singular_csv, "y ~ x1 + x2")
    @test singular isa ModelError
    @test singular.code === :singular_design

    empty_csv, empty_io = mktemp()
    close(empty_io)
    write(empty_csv, "y,x1\n,\n,\n")

    empty_result = fit_ols_file(empty_csv, "y ~ x1")
    @test empty_result isa ModelError
    @test empty_result.code === :empty_effective_sample
end
