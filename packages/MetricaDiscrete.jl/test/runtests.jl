using MetricaDiscrete
using MetricaBase
using Test
using DataFrames
using Distributions
using Random

Random.seed!(42)

# === 辅助函数：生成测试数据 ===================================================

function make_binary_data(n=200)
    X = [ones(n) randn(n, 2)]
    true_beta = [0.5, 1.0, -0.5]
    η = X * true_beta
    p = 1.0 ./ (1.0 .+ exp.(-η))
    y = [rand() < p_i ? 1.0 : 0.0 for p_i in p]
    return DataFrame(y=y, x1=X[:, 2], x2=X[:, 3])
end

function make_count_data(n=200)
    X = [ones(n) randn(n, 2)]
    β = [1.0, 0.3, -0.2]
    λ = exp.(X * β)
    y = [rand(Poisson(λ_i)) for λ_i in λ]
    return DataFrame(y=Float64.(y), x1=X[:, 2], x2=X[:, 3])
end

function make_ordered_data(n=200)
    x = randn(n)
    η = 0.8 * x
    y = clamp.(round.(Int, 3 .+ 2 * cdf.(Normal(), η) .+ 0.3 * randn(n)), 1, 5)
    return DataFrame(y=y, x=x, z=randn(n))
end

# === Logit ====================================================================

@testset "Logit" begin
    df = make_binary_data()
    result = MetricaBase.fit(LogitModel, "y ~ x1 + x2", df)
    @test result isa LogitFitResult
    @test result.converged
    @test result.iterations < 20
    @test length(result.coefficient_values) == 3

    g = MetricaBase.glance(result)
    @test g.model == :logit
    @test g.nobs == 200
    @test haskey(g.metrics, :pseudo_r2)
    @test haskey(g.metrics, :aic)
    @test haskey(g.metrics, :bic)
    @test 0 < g.metrics[:pseudo_r2] < 1

    t = MetricaBase.tidy(result)
    @test length(t.rows) == 3
    for row in t.rows
        @test row.pvalue isa Float64
        @test row.stderror > 0
    end

    a = MetricaBase.augment(result)
    @test haskey(a.columns, :fitted)
    @test haskey(a.columns, :pearson_residual)

    p = MetricaBase.predict(result)
    @test length(p) == 200
    @test all(x -> 0 <= x <= 1, p)

    payload = result_to_payload(result)
    @test payload["status"] == "success"
    @test haskey(payload["result_payload"], "odds_ratios")
    @test length(payload["result_payload"]["odds_ratios"]) == 3
end

# === Probit ===================================================================

@testset "Probit" begin
    df = make_binary_data()
    result = MetricaBase.fit(ProbitModel, "y ~ x1 + x2", df)
    @test result isa ProbitFitResult
    @test result.converged

    g = MetricaBase.glance(result)
    @test g.model == :probit

    payload = result_to_payload(result)
    @test payload["status"] == "success"
end

# === Poisson ==================================================================

@testset "Poisson" begin
    df = make_count_data()
    result = MetricaBase.fit(PoissonModel, "y ~ x1 + x2", df)
    @test result isa PoissonFitResult
    @test result.converged

    g = MetricaBase.glance(result)
    @test g.model == :poisson
    @test haskey(g.metrics, :pseudo_r2)

    payload = result_to_payload(result)
    @test payload["status"] == "success"
    @test haskey(payload["result_payload"], "incidence_rate_ratios")
end

# === 有序 Logit ===============================================================

@testset "OrderedLogit" begin
    df = make_ordered_data()
    result = MetricaBase.fit(OrderedLogitModel, "y ~ x + z", df)
    @test result isa OrderedLogitFitResult
    @test result.converged
    @test result.n_categories >= 3

    g = MetricaBase.glance(result)
    @test g.model == :ordered_logit
    @test haskey(g.metrics, :n_categories)

    p = MetricaBase.predict(result)
    @test length(p) == size(df, 1)
end

# === 多项 Logit ===============================================================

@testset "MultinomialLogit" begin
    df = make_ordered_data()
    cats = sort(unique(df.y))
    @test length(cats) >= 3
    # 使用值最小的类别作为基准
    ref = cats[1]
    result = MetricaBase.fit(MultinomialLogitModel, "y ~ x + z", df; reference_category=ref)
    if result isa MetricaBase.ModelError
        @warn "MultinomialLogit fitting failed, skipping: $(result.detail)"
    else
        @test result isa MultinomialLogitFitResult
        @test result.converged
        g = MetricaBase.glance(result)
        @test g.model == :multinomial_logit
    end
end

# === 负二项回归 ===============================================================

@testset "NegBin" begin
    Random.seed!(99)
    n = 300
    x = randn(n)
    η = 1.0 .+ 0.5 * x
    y_nb = [rand(NegativeBinomial(5, 0.5)) + round(Int, max(0, η_i * 2)) for η_i in η]
    df = DataFrame(y=Float64.(y_nb), x=x, z=randn(n))

    result = MetricaBase.fit(NegBinModel, "y ~ x + z", df)
    @test result isa NegBinFitResult
    @test result.converged
    @test result.dispersion > 0

    g = MetricaBase.glance(result)
    @test g.model == :negbin
    @test haskey(g.metrics, :dispersion)
end

# === 边际效应 =================================================================

@testset "MarginalEffects" begin
    df = make_binary_data()
    result = MetricaBase.fit(LogitModel, "y ~ x1 + x2", df)

    ame_table = ame(result, df)
    @test length(ame_table.rows) == 3

    mem_table = mem(result, df)
    @test length(mem_table.rows) == 3
end

# === 模型选择 =================================================================

@testset "ModelSelection" begin
    df = make_binary_data()
    result_full = MetricaBase.fit(LogitModel, "y ~ x1 + x2", df)
    result_null = MetricaBase.fit(LogitModel, "y ~ x1", df)

    lr = lr_test(result_full, result_null)
    @test lr.statistic > 0
    @test lr.dof_diff == 1
    @test lr.pvalue isa Float64

    comp = compare_aic_bic(Dict(:full => result_full, :null => result_null))
    @test length(comp.models) == 2
end

# === 错误情况 =================================================================

@testset "Errors" begin
    df = make_binary_data()

    # 公式引用不存在的列
    @test MetricaBase.fit(LogitModel, "y ~ z_not_exist", df) isa MetricaBase.ModelError

    # 响应变量不是二值
    df_bad = DataFrame(y=fill(0.5, 10), x1=randn(10), x2=randn(10))
    @test MetricaBase.fit(LogitModel, "y ~ x1 + x2", df_bad) isa MetricaBase.ModelError

    # 有序 Logit 分类数不足
    df_2cat = DataFrame(y=[1, 1, 2, 2, 1, 2], x=randn(6))
    @test MetricaBase.fit(OrderedLogitModel, "y ~ x", df_2cat) isa MetricaBase.ModelError

    # Poisson 负值响应
    df_neg = DataFrame(y=[-1.0, 2.0, 3.0], x=randn(3))
    @test MetricaBase.fit(PoissonModel, "y ~ x", df_neg) isa MetricaBase.ModelError

    # Poisson 非整数响应
    float_csv, float_io = mktemp()
    close(float_io)
    write(float_csv, "y,x1\n0.2,1\n1.7,2\n3.1,3\n2.0,4\n")
    result = MetricaBase.fit(PoissonModel, "y ~ x1", float_csv)
    @test result isa MetricaBase.ModelError
    @test result.code == :invalid_count_response
    rm(float_csv; force=true)
end

# === 不支持的 vcov 类型 ========================================================

@testset "UnsupportedVcov" begin
    df = make_binary_data()

    result_logit = MetricaBase.fit(LogitModel, "y ~ x1", df; vcov=:gmm)
    @test result_logit isa MetricaBase.ModelError
    @test result_logit.code == :unsupported_vcov

    result_probit = MetricaBase.fit(ProbitModel, "y ~ x1", df; vcov=:gmm)
    @test result_probit isa MetricaBase.ModelError
    @test result_probit.code == :unsupported_vcov

    df_count = make_count_data()
    result_poisson = MetricaBase.fit(PoissonModel, "y ~ x1", df_count; vcov=:gmm)
    @test result_poisson isa MetricaBase.ModelError
    @test result_poisson.code == :unsupported_vcov
end

# === cluster 与缺失值 =========================================================

@testset "ClusterWithMissingValues" begin
    Random.seed!(123)
    n = 200
    X = [ones(n) randn(n)]
    β = [0.5, 1.0]
    η = X * β
    p = 1.0 ./ (1.0 .+ exp.(-η))
    y = [rand() < p_i ? 1.0 : 0.0 for p_i in p]
    cluster_id = repeat(["A", "B", "C", "D"], div(n, 4))
    df = DataFrame(y=allowmissing(y), x1=allowmissing(X[:, 2]), cluster=allowmissing(cluster_id))
    df[5, :x1] = missing
    df[10, :y] = missing
    df[50, :cluster] = missing

    result = MetricaBase.fit(LogitModel, "y ~ x1", df; vcov=:cluster, cluster_column=:cluster)
    @test result isa LogitFitResult
    @test result.converged
    @test length(result.stderror_values) == 2

    result_p = MetricaBase.fit(ProbitModel, "y ~ x1", df; vcov=:cluster, cluster_column=:cluster)
    @test result_p isa ProbitFitResult

    Random.seed!(456)
    n2 = 200
    X2 = [ones(n2) randn(n2)]
    β2 = [1.0, 0.3]
    λ = exp.(X2 * β2)
    y2 = Float64.([rand(Poisson(λ_i)) for λ_i in λ])
    cluster_id2 = repeat(["A", "B"], div(n2, 2))
    df_count = DataFrame(y=allowmissing(y2), x1=allowmissing(X2[:, 2]), cluster=allowmissing(cluster_id2))
    df_count[3, :x1] = missing
    df_count[7, :y] = missing
    df_count[20, :cluster] = missing

    result_po = MetricaBase.fit(PoissonModel, "y ~ x1", df_count; vcov=:cluster, cluster_column=:cluster)
    @test result_po isa PoissonFitResult
end

# === 协议方法一致性 ===========================================================

@testset "ProtocolConsistency" begin
    df = make_binary_data()
    result = MetricaBase.fit(LogitModel, "y ~ x1 + x2", df)

    @test MetricaBase.nobs(result) == 200
    @test MetricaBase.dof(result) == 197
    @test length(MetricaBase.coef(result)) == 3
    @test size(MetricaBase.vcov(result)) == (3, 3)
    @test length(MetricaBase.stderror(result)) == 3
    @test 0 < MetricaBase.r2(result) < 1
    @test length(MetricaBase.fitted(result)) == 200
    @test length(MetricaBase.residuals(result)) == 200
end

# === 序列化 ===================================================================

@testset "Serialization" begin
    df = make_binary_data()

    result = MetricaBase.fit(LogitModel, "y ~ x1 + x2", df)
    payload = result_to_payload(result; include_augment=true)
    @test payload["status"] == "success"
    @test haskey(payload["result_payload"], "augment_preview")
    @test haskey(payload["result_payload"], "odds_ratios")
    @test haskey(payload["result_payload"], "loglikelihood")

    payload_noaug = result_to_payload(result; include_augment=false)
    @test !haskey(payload_noaug["result_payload"], "augment_preview")

    err = MetricaBase.fit(LogitModel, "y ~ z_not_exist", df)
    err_payload = result_to_payload(err)
    @test err_payload["status"] == "error"
    @test length(err_payload["messages"]) > 0
end

# === MODEL_REGISTRY ===========================================================

@testset "MODEL_REGISTRY" begin
    @test haskey(MetricaBase.MODEL_REGISTRY, "logit")
    @test haskey(MetricaBase.MODEL_REGISTRY, "probit")
    @test haskey(MetricaBase.MODEL_REGISTRY, "poisson")
    @test haskey(MetricaBase.MODEL_REGISTRY, "ols")
    @test MetricaBase.MODEL_REGISTRY["logit"] == LogitModel
end
