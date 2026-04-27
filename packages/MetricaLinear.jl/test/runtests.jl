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
    @test haskey(glance(ok).metrics, :adj_r2)
    @test haskey(glance(ok).metrics, :rss)
    @test haskey(glance(ok).metrics, :tss)
    @test haskey(glance(ok).metrics, :sigma)
    @test length(tidy(ok).rows) == 3
    @test all(row -> row.pvalue !== nothing, tidy(ok).rows)
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
    write(empty_csv, "y,x1\n,1\n,2\n")

    empty_result = fit_ols_file(empty_csv, "y ~ x1")
    @test empty_result isa ModelError
    @test empty_result.code === :empty_effective_sample

    rm(singular_csv; force=true)
    rm(empty_csv; force=true)
end

@testset "结构化载荷输出" begin
    ok = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    ok_payload = result_to_payload(ok)
    @test ok_payload["status"] == "success"
    @test haskey(ok_payload, "result_payload")
    @test haskey(ok_payload["result_payload"], "glance")
    @test haskey(ok_payload["result_payload"], "tidy")
    @test ok_payload["result_payload"]["glance"]["metrics"]["adj_r2"] isa Real
    @test length(ok_payload["result_payload"]["warnings"]) >= 1

    missing_col = fit_ols_file(DEMO_CSV, "y ~ x9")
    err_payload = result_to_payload(missing_col)
    @test err_payload["status"] == "error"
    @test length(err_payload["messages"]) == 1
    @test err_payload["messages"][1]["code"] == "unknown_variable"
end

@testset "数据检查载荷输出" begin
    inspection = inspect_dataset(DEMO_CSV)
    @test inspection isa Dict
    @test inspection["status"] == "success"
    @test haskey(inspection["result_payload"], "dataset_summary")
    @test haskey(inspection["result_payload"], "columns")
    @test haskey(inspection["result_payload"], "preview_rows")
    @test inspection["result_payload"]["dataset_summary"]["row_count"] == 8
    @test inspection["result_payload"]["dataset_summary"]["column_count"] == 3
    @test length(inspection["result_payload"]["columns"]) == 3
    @test length(inspection["result_payload"]["preview_rows"]) > 0

    missing_payload = inspect_dataset("/tmp/does-not-exist.csv")
    @test missing_payload["status"] == "error"
    @test missing_payload["messages"][1]["code"] == "dataset_not_found"
end
