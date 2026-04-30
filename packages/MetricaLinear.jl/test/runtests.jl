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

function coef_row(fit::OLSFitResult, name::Symbol)
    return only(row for row in tidy(fit).rows if row.name === name)
end

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
    @test glance(ok).metrics[:r2] ≈ 0.993321819228555
    @test glance(ok).metrics[:sigma] ≈ 0.5255382728122434
    @test coef_row(ok, :x1).estimate ≈ 2.7333333333333347
    @test coef_row(ok, :x1).stderror ≈ 0.7180219742845957

    missing_col = fit_ols_file(DEMO_CSV, "y ~ x9")
    @test missing_col isa ModelError
    @test missing_col.code === :unknown_variable
end

@testset "WLS 基础链路" begin
    weighted = fit_ols_file(DEMO_CSV, "y ~ x1 + x2"; weights=:x1)
    @test weighted isa OLSFitResult
    @test glance(weighted).model === :wls
    @test tidy(weighted).vcov_label == "classical"
    @test length(tidy(weighted).rows) == 3
    @test glance(weighted).metrics[:r2] ≈ 0.9939949706951068
    @test coef_row(weighted, :x1).estimate ≈ 2.396059113300492
    @test coef_row(weighted, :x1).stderror ≈ 0.6371988621545017

    missing_weight = fit_ols_file(DEMO_CSV, "y ~ x1 + x2"; weights=:w9)
    @test missing_weight isa ModelError
    @test missing_weight.code === :unknown_weight_variable
end

@testset "HC1 协方差链路" begin
    robust = fit_ols_file(DEMO_CSV, "y ~ x1 + x2"; vcov=:HC1)
    @test robust isa OLSFitResult
    @test tidy(robust).vcov_label == "HC1"
    @test all(row -> row.stderror !== nothing, tidy(robust).rows)
    @test coef_row(robust, :x1).estimate ≈ 2.7333333333333347
    @test coef_row(robust, :x1).stderror ≈ 0.7950774478930701

    unsupported = fit_ols_file(DEMO_CSV, "y ~ x1 + x2"; vcov=:cluster)
    @test unsupported isa ModelError
    @test unsupported.code === :unsupported_vcov
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
    @test ok_payload["result_payload"]["vcov_label"] == "classical"
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
