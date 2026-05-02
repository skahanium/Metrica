using Test
using MetricaBase: fit, coef, vcov, stderror, nobs, dof, r2, fitted, residuals, predict,
    glance, tidy, augment, ModelError, ModelWarning, AugmentTable, AbstractLinearModel, AbstractLinearFitResult
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

    # 不支持的协方差类型
    unsupported = fit_ols_file(DEMO_CSV, "y ~ x1 + x2"; vcov=:gmm)
    @test unsupported isa ModelError
    @test unsupported.code === :unsupported_vcov
end

@testset "Cluster 协方差链路" begin
    # 不含聚类变量的 cluster 请求应返回明确错误
    missing_col = fit_ols_file(DEMO_CSV, "y ~ x1 + x2"; vcov=:cluster)
    @test missing_col isa ModelError
    @test missing_col.code === :missing_cluster_variable

    # 构造含聚类变量的测试数据集（每聚类 3 个观测，两组，x1 与 x2 非共线）
    cluster_csv, cluster_io = mktemp()
    close(cluster_io)
    write(cluster_csv, "y,x1,x2,group\n10,1,5,A\n12,2,3,A\n14,3,1,A\n20,2,6,B\n22,3,4,B\n24,4,2,B\n")

    clustered = fit_ols_file(cluster_csv, "y ~ x1 + x2"; vcov=:cluster, cluster=:group)
    @test clustered isa OLSFitResult
    @test tidy(clustered).vcov_label == "cluster"

    # 所有系数应有标准误
    @test all(row -> row.stderror !== nothing, tidy(clustered).rows)

    # 系数应与 OLS 一致（聚类只影响标准误，不影响点估计）
    ols = fit_ols_file(cluster_csv, "y ~ x1 + x2"; vcov=:classical)
    for (cr, or_) in zip(tidy(clustered).rows, tidy(ols).rows)
        @test cr.estimate ≈ or_.estimate
        @test cr.name == or_.name
    end

    # 聚类标准误应与经典标准误不同（存在组内相关时）
    # 此处验证 x1 的标准误确实不同
    @test coef_row(clustered, :x1).stderror != coef_row(ols, :x1).stderror

    # 单聚类应返回错误
    single_csv, single_io = mktemp()
    close(single_io)
    write(single_csv, "y,x1,x2,group\n10,1,5,A\n12,2,8,A\n14,3,1,A\n15,4,3,A\n")

    single = fit_ols_file(single_csv, "y ~ x1 + x2"; vcov=:cluster, cluster=:group)
    @test single isa ModelError
    @test single.code === :single_cluster

    # 不存在的聚类变量
    bad_cluster = fit_ols_file(cluster_csv, "y ~ x1 + x2"; vcov=:cluster, cluster=:bad_col)
    @test bad_cluster isa ModelError
    @test bad_cluster.code === :unknown_cluster_variable

    rm(cluster_csv; force=true)
    rm(single_csv; force=true)
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
    @test haskey(ok_payload["result_payload"], "augment_preview")
    @test ok_payload["result_payload"]["vcov_label"] == "classical"
    @test ok_payload["result_payload"]["glance"]["metrics"]["adj_r2"] isa Real
    @test length(ok_payload["result_payload"]["warnings"]) >= 1
    @test haskey(ok_payload["result_payload"]["augment_preview"], "fitted")
    @test haskey(ok_payload["result_payload"]["augment_preview"], "residual")
    @test length(ok_payload["result_payload"]["augment_preview"]["fitted"]) == 7

    # 测试 include_augment=false
    ok_payload_no_augment = result_to_payload(ok; include_augment=false)
    @test !haskey(ok_payload_no_augment["result_payload"], "augment_preview")

    missing_col = fit_ols_file(DEMO_CSV, "y ~ x9")
    err_payload = result_to_payload(missing_col)
    @test err_payload["status"] == "error"
    @test length(err_payload["messages"]) == 1
    @test err_payload["messages"][1]["code"] == "unknown_variable"
end

@testset "augment 能力" begin
    ok = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    at = augment(ok)
    @test at isa AugmentTable
    @test at.nobs == 7
    @test length(at.columns) == 6
    @test haskey(at.columns, :observation)
    @test haskey(at.columns, :fitted)
    @test haskey(at.columns, :residual)
    @test haskey(at.columns, :std_residual)
    @test haskey(at.columns, :leverage)
    @test haskey(at.columns, :cooks_d)
    @test at.columns[:observation] == [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]
    @test length(at.columns[:fitted]) == 7
    @test length(at.columns[:residual]) == 7

    # 数值恒等式：fitted + residual = 实际响应值
    y = ok.response_vector
    fitted = at.columns[:fitted]
    residuals = at.columns[:residual]
    @test fitted ≈ ok.fitted_values atol=1e-12
    @test residuals ≈ ok.residual_vector atol=1e-12
    @test fitted + residuals ≈ y atol=1e-12
    @test sum(residuals) ≈ 0.0 atol=1e-10

    # 标准化残差 = 残差 / sigma
    sigma = glance(ok).metrics[:sigma]
    @test sigma > 0
    @test at.columns[:std_residual] ≈ residuals ./ sigma atol=1e-12

    # 杠杆值范围与秩恒等式：0 ≤ h_ii < 1，Σ h_ii = k
    leverage = at.columns[:leverage]
    k = size(ok.design_matrix, 2)
    @test all(0.0 .<= leverage .< 1.0)
    @test sum(leverage) ≈ k atol=1e-10

    # Cook's D 非负
    cooks_d = at.columns[:cooks_d]
    @test all(cooks_d .>= 0.0)
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

@testset "统一 fit 接口与协议方法" begin
    ok = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV)

    @test ok isa OLSFitResult
    @test ok isa AbstractLinearFitResult

    c = coef(ok)
    @test c isa Vector{Pair{Symbol,Float64}}
    @test length(c) == 3

    v = vcov(ok)
    @test v isa Matrix{Float64}
    @test size(v) == (3, 3)

    se = stderror(ok)
    @test se isa Vector{Float64}
    @test length(se) == 3
    @test all(se .> 0)

    @test nobs(ok) == 7
    @test dof(ok) == 4
    @test r2(ok) ≈ 0.993321819228555

    f = fitted(ok)
    @test length(f) == 7
    @test f ≈ ok.fitted_values

    r = residuals(ok)
    @test length(r) == 7
    @test sum(r) ≈ 0.0 atol=1e-10

    p = predict(ok)
    @test length(p) == 7
    @test p ≈ ok.fitted_values atol=1e-12

    ci = predict(ok; interval=:confidence, level=0.95)
    @test ci isa NamedTuple{(:predictions, :lower, :upper)}
    @test all(ci.lower .<= ci.predictions .<= ci.upper)

    pi = predict(ok; interval=:prediction, level=0.95)
    @test pi isa NamedTuple{(:predictions, :lower, :upper)}
    @test all((pi.upper .- pi.lower) .>= (ci.upper .- ci.lower) .- 1e-10)

    old = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    @test old isa OLSFitResult
end

@testset "IV/2SLS 链路" begin
    iv_csv, iv_io = mktemp()
    close(iv_io)
    write(iv_csv, """y,x1,x2,z1,z2
10,1,5,3,8
12,2,3,5,6
14,3,1,7,4
20,2,6,4,9
22,3,4,6,7
24,4,2,8,5
30,5,7,9,10
32,6,5,11,8
""")

    iv_result = fit(IVModel, "y ~ x1 + x2", iv_csv;
                    instruments=["z1", "z2"], endog=["x2"])
    @test iv_result isa IVFitResult
    @test iv_result isa AbstractLinearFitResult
    @test glance(iv_result).model === :iv
    @test glance(iv_result).nobs == 8
    @test length(tidy(iv_result).rows) == 3

    @test length(iv_result.first_stage_stats) >= 1

    @test haskey(glance(iv_result).metrics, :r2)
    @test haskey(glance(iv_result).metrics, :sigma)
    @test all(row -> row.pvalue !== nothing, tidy(iv_result).rows)

    at = augment(iv_result)
    @test at isa AugmentTable
    @test at.nobs == 8

    p = predict(iv_result)
    @test length(p) == 8

    ci = predict(iv_result; interval=:confidence, level=0.95)
    @test ci isa NamedTuple
    @test all(ci.lower .<= ci.predictions .<= ci.upper)

    payload = result_to_payload(iv_result)
    @test payload["status"] == "success"
    @test haskey(payload["result_payload"], "first_stage_stats")

    missing_inst = fit(IVModel, "y ~ x1 + x2", iv_csv;
                       instruments=["z9"], endog=["x2"])
    @test missing_inst isa ModelError
    @test missing_inst.code === :unknown_instrument_variable

    bad_endog = fit(IVModel, "y ~ x1", iv_csv;
                    instruments=["z1"], endog=["x2"])
    @test bad_endog isa ModelError
    @test bad_endog.code === :endog_not_in_formula

    rm(iv_csv; force=true)
end
