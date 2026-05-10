using Test
using LinearAlgebra: I
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
    ok = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV)
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

    missing_col = fit(OLSModel, "y ~ x9", DEMO_CSV)
    @test missing_col isa ModelError
    @test missing_col.code === :unknown_variable
end

@testset "无截距 OLS 链路" begin
    ok = fit(OLSModel, "y ~ 0 + x1 + x2", DEMO_CSV)
    @test ok isa OLSFitResult
    @test glance(ok).model === :ols
    @test glance(ok).nobs == 7
    @test glance(ok).dof == 5
    @test length(tidy(ok).rows) == 2
    @test all(row -> row.name != Symbol("(Intercept)"), tidy(ok).rows)
    @test [row.name for row in tidy(ok).rows] == [:x1, :x2]
    @test coef_row(ok, :x1).estimate ≈ 3.170526558359258
    @test coef_row(ok, :x2).estimate ≈ 1.3463532665053577
end

@testset "WLS 基础链路" begin
    weighted = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV; weights=:x1)
    @test weighted isa OLSFitResult
    @test glance(weighted).model === :wls
    @test tidy(weighted).vcov_label == "classical"
    @test length(tidy(weighted).rows) == 3
    @test glance(weighted).metrics[:r2] ≈ 0.9939949706951068
    @test coef_row(weighted, :x1).estimate ≈ 2.396059113300492
    @test coef_row(weighted, :x1).stderror ≈ 0.6371988621545017

    missing_weight = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV; weights=:w9)
    @test missing_weight isa ModelError
    @test missing_weight.code === :unknown_weight_variable
end

@testset "HC1 协方差链路" begin
    robust = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV; vcov=:HC1)
    @test robust isa OLSFitResult
    @test tidy(robust).vcov_label == "HC1"
    @test all(row -> row.stderror !== nothing, tidy(robust).rows)
    @test coef_row(robust, :x1).estimate ≈ 2.7333333333333347
    @test coef_row(robust, :x1).stderror ≈ 0.7950774478930701

    # 不支持的协方差类型
    unsupported = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV; vcov=:gmm)
    @test unsupported isa ModelError
    @test unsupported.code === :unsupported_vcov
end

@testset "Cluster 协方差链路" begin
    # 不含聚类变量的 cluster 请求应返回明确错误
    missing_col = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV; vcov=:cluster)
    @test missing_col isa ModelError
    @test missing_col.code === :missing_cluster_variable

    # 构造含聚类变量的测试数据集（每聚类 3 个观测，两组，x1 与 x2 非共线）
    cluster_csv, cluster_io = mktemp()
    close(cluster_io)
    write(cluster_csv, "y,x1,x2,group\n10,1,5,A\n12,2,3,A\n14,3,1,A\n20,2,6,B\n22,3,4,B\n24,4,2,B\n")

    clustered = fit(OLSModel, "y ~ x1 + x2", cluster_csv; vcov=:cluster, cluster_column=:group)
    @test clustered isa OLSFitResult
    @test tidy(clustered).vcov_label == "cluster"

    # 所有系数应有标准误
    @test all(row -> row.stderror !== nothing, tidy(clustered).rows)

    # 系数应与 OLS 一致（聚类只影响标准误，不影响点估计）
    ols = fit(OLSModel, "y ~ x1 + x2", cluster_csv; vcov=:classical)
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

    single = fit(OLSModel, "y ~ x1 + x2", single_csv; vcov=:cluster, cluster_column=:group)
    @test single isa ModelError
    @test single.code === :single_cluster

    # 不存在的聚类变量
    bad_cluster = fit(OLSModel, "y ~ x1 + x2", cluster_csv; vcov=:cluster, cluster_column=:bad_col)
    @test bad_cluster isa ModelError
    @test bad_cluster.code === :unknown_cluster_variable

    rm(cluster_csv; force=true)
    rm(single_csv; force=true)
end

@testset "奇异矩阵与空样本" begin
    singular_csv, singular_io = mktemp()
    close(singular_io)
    write(singular_csv, "y,x1,x2\n1,1,2\n2,2,4\n3,3,6\n")

    singular = fit(OLSModel, "y ~ x1 + x2", singular_csv)
    @test singular isa ModelError
    @test singular.code === :singular_design

    empty_csv, empty_io = mktemp()
    close(empty_io)
    write(empty_csv, "y,x1\n,1\n,2\n")

    empty_result = fit(OLSModel, "y ~ x1", empty_csv)
    @test empty_result isa ModelError
    @test empty_result.code === :empty_effective_sample

    rm(singular_csv; force=true)
    rm(empty_csv; force=true)
end

@testset "近共线 OLS" begin
    # x2 ≈ x1（偏差 1e-12），20 行确保 rank 满秩但条件数极高
    near_csv, near_io = mktemp()
    close(near_io)
    write(near_csv, join([
        "y,x1,x2",
        "2,1,1.000000000001",
        "4,2,1.999999999998",
        "6,3,3.0000000000015",
        "8,4,3.9999999999995",
        "10,5,5.000000000003",
        "12,6,5.999999999999",
        "14,7,7.000000000002",
        "16,8,7.9999999999985",
        "18,9,9.0000000000005",
        "20,10,9.9999999999975",
        "22,11,11.000000000001",
        "24,12,11.999999999998",
        "26,13,13.0000000000015",
        "28,14,13.9999999999995",
        "30,15,15.000000000003",
        "32,16,15.999999999999",
        "34,17,17.000000000002",
        "36,18,17.9999999999985",
        "38,19,19.0000000000005",
        "40,20,19.9999999999975",
    ], "\n") * "\n")
    result = fit(OLSModel, "y ~ x1 + x2", near_csv)
    @test result isa ModelError
    @test result.code == :near_singular_design
    rm(near_csv; force=true)
end

@testset "结构化载荷输出" begin
    ok = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV)
    ok_payload = result_to_payload(ok)
    @test ok_payload["status"] == "success"
    @test haskey(ok_payload, "result_payload")
    @test haskey(ok_payload["result_payload"], "glance")
    @test haskey(ok_payload["result_payload"], "tidy")
    @test haskey(ok_payload["result_payload"], "augment_preview")
    @test ok_payload["result_payload"]["vcov_label"] == "classical"
    @test ok_payload["result_payload"]["glance"]["metrics"]["adj_r2"] isa Real
    @test length(ok_payload["result_payload"]["warnings"]) >= 1
    @test length(ok_payload["result_payload"]["augment_preview"]) == 7
    @test haskey(ok_payload["result_payload"]["augment_preview"][1], "fitted")
    @test haskey(ok_payload["result_payload"]["augment_preview"][1], "residual")

    # 测试 include_augment=false
    ok_payload_no_augment = result_to_payload(ok; include_augment=false)
    @test !haskey(ok_payload_no_augment["result_payload"], "augment_preview")

    missing_col = fit(OLSModel, "y ~ x9", DEMO_CSV)
    err_payload = result_to_payload(missing_col)
    @test err_payload["status"] == "error"
    @test length(err_payload["messages"]) == 1
    @test err_payload["messages"][1]["code"] == "unknown_variable"
end

@testset "augment 能力" begin
    ok = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV)
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

    old = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV)
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

@testset "IV 欠识别" begin
    # instruments 数量 < endog 数量
    iv_csv, iv_io = mktemp()
    close(iv_io)
    write(iv_csv, "y,x1,x2,z1\n10,1,5,3\n12,2,3,6\n14,3,8,9\n20,2,2,4\n22,3,4,7\n24,4,6,10\n30,5,1,5\n32,6,7,11\n")
    result = fit(IVModel, "y ~ x1 + x2", iv_csv; instruments=["z1"], endog=["x1", "x2"])
    @test result isa ModelError
    @test result.code == :underidentified_model
    rm(iv_csv; force=true)
end

@testset "IV residual口径" begin
    iv_csv, iv_io = mktemp()
    close(iv_io)
    write(iv_csv, """y,x1,x2,z1
10,1,5,3
12,2,3,6
14,3,8,9
20,2,2,4
22,3,4,7
24,4,6,10
30,5,1,5
32,6,7,11
""")

    result = fit(IVModel, "y ~ x1 + x2", iv_csv;
                 instruments=["z1"], endog=["x2"])
    @test result isa IVFitResult

    # 残差口径检验：fitted 应基于原始解释变量，而非第二阶段预测值
    X_orig = result.design_matrix
    x2_actual = Float64[5,3,8,2,4,6,1,7]
    @test X_orig ≈ hcat(ones(8), Float64[1,2,3,2,3,4,5,6], x2_actual) atol=1e-12

    manual_fitted = X_orig * result.coef_values
    @test result.fitted_values ≈ manual_fitted atol=1e-12
    @test result.residual_vector ≈ result.response_vector - manual_fitted atol=1e-12

    rm(iv_csv; force=true)
end

@testset "GLS 链路" begin
    identity_omega = r -> Matrix{Float64}(I, length(r), length(r))
    gls_result = fit(GLSModel, "y ~ x1 + x2", DEMO_CSV; omega_fn=identity_omega)

    @test gls_result isa GLSFitResult
    @test gls_result isa AbstractLinearFitResult
    @test glance(gls_result).model === :gls
    @test glance(gls_result).nobs == 7

    ols_result = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV)
    for (g, o) in zip(tidy(gls_result).rows, tidy(ols_result).rows)
        @test g.estimate ≈ o.estimate atol=1e-10
    end

    @test haskey(glance(gls_result).metrics, :r2)
    @test augment(gls_result) isa AugmentTable

    p = predict(gls_result)
    @test length(p) == 7

    ci = predict(gls_result; interval=:confidence, level=0.95)
    @test ci isa NamedTuple
    @test all(ci.lower .<= ci.predictions .<= ci.upper)

    payload = result_to_payload(gls_result)
    @test payload["status"] == "success"

    bad_omega = r -> -Matrix{Float64}(I, length(r), length(r))
    bad_result = fit(GLSModel, "y ~ x1 + x2", DEMO_CSV; omega_fn=bad_omega)
    @test bad_result isa ModelError
    @test bad_result.code === :omega_not_positive_definite

    wrong_dim_omega = r -> Matrix{Float64}(I, 3, 3)
    wrong_result = fit(GLSModel, "y ~ x1 + x2", DEMO_CSV; omega_fn=wrong_dim_omega)
    @test wrong_result isa ModelError
    @test wrong_result.code === :omega_dimension_mismatch
end

@testset "黄金样例与模型比较载荷" begin
    # OLS 黄金样例：demo.csv 已知值对齐
    ols = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV)
    @test coef_row(ols, :x1).estimate ≈ 2.7333333333333347
    @test coef_row(ols, :x1).stderror ≈ 0.7180219742845957
    @test coef_row(ols, :x2).estimate ≈ 0.8285714285714295
    @test r2(ols) ≈ 0.993321819228555
    @test nobs(ols) == 7
    @test dof(ols) == 4

    # AIC/BIC 载荷
    payload = result_to_payload(ols)
    @test haskey(payload["result_payload"], "loglikelihood")
    @test haskey(payload["result_payload"], "aic")
    @test haskey(payload["result_payload"], "bic")
    @test payload["result_payload"]["aic"] isa Float64
    @test payload["result_payload"]["bic"] isa Float64

    # predict 区间覆盖率：置信区间应包含所有点预测
    ci = predict(ols; interval=:confidence, level=0.95)
    @test all(ci.lower .<= ci.predictions .<= ci.upper)

    # 预测区间应比置信区间宽
    pi = predict(ols; interval=:prediction, level=0.95)
    @test all((pi.upper .- pi.lower) .>= (ci.upper .- ci.lower) .- 1e-10)

    # IV 黄金样例：含工具变量数据
    iv_csv, iv_io = mktemp()
    close(iv_io)
    write(iv_csv, """y,x,z
3,1,2
5,2,4
7,3,6
9,4,8
11,5,10
13,6,12
15,7,14
17,8,16
""")
    iv = fit(IVModel, "y ~ x", iv_csv; instruments=["z"], endog=["x"])
    @test iv isa IVFitResult
    # z 与 x 完全共线性情况下，IV 应给出合理估计
    @test length(coef(iv)) == 2
    @test all(isfinite(last(p)) for p in coef(iv))
    rm(iv_csv; force=true)
end
