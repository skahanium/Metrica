using MetricaSurvey
using MetricaBase
import MetricaDiscrete: LogitModel, PoissonModel, LogitFitResult
using Test
using DataFrames
using Distributions
using LinearAlgebra
using Random

Random.seed!(42)

# === 辅助函数：生成复杂调查数据 =================================================

function make_survey_data(; n=200, n_strata=2, n_psu_per_stratum=4)
    data = DataFrame(
        y = Float64[],
        x1 = Float64[],
        x2 = Float64[],
        wt = Float64[],
        stratum = Int[],
        psu = Int[],
        y_bin = Float64[],
    )
    for h in 1:n_strata
        n_h = n ÷ n_strata
        for p in 1:n_psu_per_stratum
            n_psu = n_h ÷ n_psu_per_stratum
            x1_h = randn(n_psu) .+ 0.5*h
            x2_h = randn(n_psu)
            wt_h = rand(1.0:0.5:3.0, n_psu)  # 抽样权重 1-3
            err = randn(n_psu) * 0.5
            y_h = 1.0 .+ 0.8 .* x1_h .- 0.4 .* x2_h .+ err
            p_h = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 1.0 .* x1_h .- 0.5 .* x2_h)))
            y_bin_h = [rand() < pi ? 1.0 : 0.0 for pi in p_h]

            append!(data.y, y_h)
            append!(data.x1, x1_h)
            append!(data.x2, x2_h)
            append!(data.wt, wt_h)
            append!(data.stratum, fill(h, n_psu))
            append!(data.psu, fill((h-1)*n_psu_per_stratum + p, n_psu))
            append!(data.y_bin, y_bin_h)
        end
    end
    return data
end

# === SurveyDesign ===============================================================

@testset "SurveyDesign" begin
    df = make_survey_data()

    @testset "构造成功" begin
        design = SurveyDesign(df, :wt)
        @test design isa SurveyDesign
        @test design.weights_column == :wt
        @test design.strata_column === nothing
    end

    @testset "带 strata 和 psu" begin
        design = SurveyDesign(df, :wt; strata_column=:stratum, psu_column=:psu)
        @test design.strata_column == :stratum
        @test design.psu_column == :psu
    end

    @testset "缺失权重列" begin
        result = SurveyDesign(df, :bad_column)
        @test result isa MetricaBase.ModelError
        @test result.code == :missing_weight_column
    end

    @testset "负权重" begin
        df_bad = copy(df)
        df_bad.wt[1] = -1.0
        result = SurveyDesign(df_bad, :wt)
        @test result isa MetricaBase.ModelError
        @test result.code == :negative_weights
    end

    @testset "全零权重" begin
        df_bad = copy(df)
        df_bad.wt .= 0.0
        result = SurveyDesign(df_bad, :wt)
        @test result isa MetricaBase.ModelError
        @test result.code == :zero_weights
    end
end

# === Survey OLS =================================================================

@testset "Survey OLS" begin
    df = make_survey_data()

    @testset "基础拟合（仅权重）" begin
        result = MetricaBase.fit(SurveyOLSModel, "y ~ x1 + x2", df; weights_column=:wt)
        @test result isa SurveyOLSFitResult

        g = MetricaBase.glance(result)
        @test g.nobs == 200
        @test haskey(g.metrics, :mean_deff)

        coefs = MetricaBase.coef(result)
        @test length(coefs) == 3  # intercept + x1 + x2

        se = MetricaBase.stderror(result)
        @test all(>(0), se)
        @test length(se) == 3
    end

    @testset "分层 + PSU 方差" begin
        result = MetricaBase.fit(SurveyOLSModel, "y ~ x1 + x2", df;
            weights_column=:wt, strata_column=:stratum, psu_column=:psu)

        @test result isa SurveyOLSFitResult
        @test !any(isnan, result.survey_se)
        @test !any(isnan, result.design_effects)

        # survey_vcov 应为正定对称
        v = result.survey_vcov
        @test size(v) == (3, 3)
        @test v ≈ v'
        @test all(diag(v) .>= 0)
    end

    @testset "DEFF 计算" begin
        result = MetricaBase.fit(SurveyOLSModel, "y ~ x1 + x2", df;
            weights_column=:wt, strata_column=:stratum, psu_column=:psu)

        de = design_effect(result)
        @test de isa DEFFResult
        @test length(de.coefficient) == 3
        @test all(>(0), de.deff)
        @test all(>(0), de.n_eff)
        @test all(>(0), de.survey_se)
    end

    @testset "Protocol 方法" begin
        result = MetricaBase.fit(SurveyOLSModel, "y ~ x1 + x2", df; weights_column=:wt)

        @test MetricaBase.glance(result) isa MetricaBase.ModelGlance
        @test MetricaBase.tidy(result) isa MetricaBase.TidyTable
        @test MetricaBase.nobs(result) == 200
        @test MetricaBase.dof(result) > 0
        @test length(MetricaBase.fitted(result)) == 200
        @test length(MetricaBase.residuals(result)) == 200
    end

    @testset "无 strata 时 strata_summary" begin
        design = SurveyDesign(df, :wt)
        ss = strata_summary(design)
        @test ss isa DataFrame
        @test nrow(ss) == 1
        @test ss.stratum[1] == "(全部观测)"
    end

    @testset "有 strata 时 strata_summary" begin
        design = SurveyDesign(df, :wt; strata_column=:stratum)
        ss = strata_summary(design)
        @test ss isa DataFrame
        @test nrow(ss) == 2
        @test "n" in names(ss)
    end
end

@testset "Survey OLS 权重对齐（缺失值）" begin
    # 创建包含缺失值的数据
    df = make_survey_data()
    # 在 x1 中引入一些缺失值
    df.x1_missing = allowmissing(df.x1)
    df.x1_missing[1:10] .= missing  # 前10行有缺失值
    
    # 运行 Survey OLS
    result = MetricaBase.fit(SurveyOLSModel, "y ~ x1_missing + x2", df; 
        weights_column=:wt, strata_column=:stratum, psu_column=:psu)
    
    @test result isa SurveyOLSFitResult
    
    # 验证权重与保留的观测值对齐
    # 预期：前10行被过滤掉，剩余190行
    @test MetricaBase.nobs(result) == 190
    
    # 验证权重向量长度与观测数匹配
    @test length(result.survey_se) == 3  # 3个系数
    
    # 验证权重列与过滤后的数据对齐
    # 我们可以通过检查 design_effects 是否合理来间接验证
    @test all(>(0), result.design_effects)
    
    # 验证 ols_result 内部的 design_matrix 行数与观测数匹配
    @test size(result.ols_result.design_matrix, 1) == 190
end

# === Survey GLM =================================================================

@testset "Survey Logit" begin
    df = make_survey_data()

    @testset "基础拟合" begin
        result = MetricaBase.fit(SurveyLogitModel, "y_bin ~ x1 + x2", df; weights_column=:wt)
        @test result isa SurveyLogitFitResult

        g = MetricaBase.glance(result)
        @test haskey(g.metrics, :mean_deff)

        se = MetricaBase.stderror(result)
        @test all(>(0), se)
        @test length(se) == 3

        # DEFF 应为正
        @test all(>(0), result.design_effects)
    end

    @testset "分层 + PSU" begin
        result = MetricaBase.fit(SurveyLogitModel, "y_bin ~ x1 + x2", df;
            weights_column=:wt, strata_column=:stratum, psu_column=:psu)
        @test result isa SurveyLogitFitResult
        @test !any(isnan, result.survey_se)
    end
end

@testset "Survey Probit" begin
    df = make_survey_data()

    @testset "基础拟合" begin
        result = MetricaBase.fit(SurveyProbitModel, "y_bin ~ x1 + x2", df; weights_column=:wt)
        @test result isa SurveyProbitFitResult
        @test length(MetricaBase.coef(result)) == 3
        @test all(>(0), MetricaBase.stderror(result))
    end
end

@testset "Survey Poisson" begin
    df = make_survey_data()
    df.y_count = round.(Int, max.(df.y .+ 5, 1))

    @testset "基础拟合" begin
        result = MetricaBase.fit(SurveyPoissonModel, "y_count ~ x1 + x2", df; weights_column=:wt)
        @test result isa SurveyPoissonFitResult
        @test length(MetricaBase.coef(result)) == 3
    end
end

# === 加权 vs 未加权估计差异验证 =================================================

@testset "加权 IRLS：加权与未加权估计不同" begin
    # 构造极端权重数据：高权重组 y=1 居多，低权重组 y=0 居多
    n = 400
    Random.seed!(123)
    x = randn(n)
    # 生成 y 使得 x 的效应在加权前后有明显差异
    prob = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 2.0 .* x)))
    y = [rand() < p ? 1.0 : 0.0 for p in prob]

    # 构造权重：x > 0 的观测权重为 10，x <= 0 的权重为 1
    wt = [xi > 0 ? 10.0 : 1.0 for xi in x]

    df_w = DataFrame(y=y, x=x, wt=wt)

    # 未加权 Logit
    unweighted = MetricaBase.fit(LogitModel, "y ~ x", df_w)
    @test unweighted isa LogitFitResult

    # Survey Logit（加权 IRLS）
    weighted = MetricaBase.fit(SurveyLogitModel, "y ~ x", df_w; weights_column=:wt)
    @test weighted isa SurveyLogitFitResult

    uw_coefs = last.(MetricaBase.coef(unweighted))
    w_coefs = MetricaBase.coef(weighted)

    # 加权与未加权的系数应明显不同
    @test !isapprox(uw_coefs, w_coefs; rtol=0.01)

    # 加权 IRLS 的标准误应为正
    @test all(>(0), MetricaBase.stderror(weighted))

    # survey_vcov 应为正定对称矩阵
    v = weighted.survey_vcov
    @test size(v) == (2, 2)
    @test v ≈ v'
    @test all(diag(v) .>= 0)

    # 设计效应应为正
    @test all(>(0), weighted.design_effects)
end

@testset "加权 IRLS：Poisson 加权与未加权不同" begin
    n = 300
    Random.seed!(456)
    x = randn(n)
    λ = exp.(1.0 .+ 0.5 .* x)
    y_count = [rand(Poisson(l)) for l in λ]
    wt = [xi > 0 ? 5.0 : 1.0 for xi in x]

    df_p = DataFrame(y_count=Float64.(y_count), x=x, wt=wt)

    unweighted = MetricaBase.fit(PoissonModel, "y_count ~ x", df_p)
    weighted = MetricaBase.fit(SurveyPoissonModel, "y_count ~ x", df_p; weights_column=:wt)

    @test weighted isa SurveyPoissonFitResult
    uw_coefs = last.(MetricaBase.coef(unweighted))
    w_coefs = MetricaBase.coef(weighted)
    @test !isapprox(uw_coefs, w_coefs; rtol=0.01)
    @test all(>(0), MetricaBase.stderror(weighted))
end

# === Serialization ==============================================================

@testset "result_to_payload" begin
    df = make_survey_data()

    @testset "SurveyOLS" begin
        result = MetricaBase.fit(SurveyOLSModel, "y ~ x1 + x2", df;
            weights_column=:wt, strata_column=:stratum, psu_column=:psu)
        payload = result_to_payload(result; include_augment=false)
        @test payload["status"] == "success"
        @test haskey(payload["result_payload"], "design_effects")
        @test haskey(payload["result_payload"], "summary_text")
        @test occursin("survey_ols", payload["result_payload"]["summary_text"])

        deff = payload["result_payload"]["design_effects"]
        @test length(deff) == 3
        @test haskey(deff[1], "deff")
        @test haskey(deff[1], "n_eff")
    end

    @testset "SurveyLogit" begin
        result = MetricaBase.fit(SurveyLogitModel, "y_bin ~ x1 + x2", df; weights_column=:wt)
        payload = result_to_payload(result; include_augment=false)
        @test payload["status"] == "success"
        @test haskey(payload["result_payload"], "odds_ratios")
    end

    @testset "SurveyPoisson" begin
        df.y_count = round.(Int, max.(df.y .+ 5, 1))
        result = MetricaBase.fit(SurveyPoissonModel, "y_count ~ x1 + x2", df; weights_column=:wt)
        payload = result_to_payload(result; include_augment=false)
        @test payload["status"] == "success"
        @test haskey(payload["result_payload"], "incidence_rate_ratios")
    end

    @testset "ModelError" begin
        err = MetricaBase.ModelError(:test, "测试", "test error", nothing)
        payload = result_to_payload(err)
        @test payload["status"] == "error"
        @test length(payload["messages"]) == 1
    end
end

# === MODEL_REGISTRY =============================================================

@testset "MODEL_REGISTRY" begin
    @test haskey(MetricaBase.MODEL_REGISTRY, "survey_ols")
    @test haskey(MetricaBase.MODEL_REGISTRY, "survey_logit")
    @test haskey(MetricaBase.MODEL_REGISTRY, "survey_probit")
    @test haskey(MetricaBase.MODEL_REGISTRY, "survey_poisson")

    @test MetricaBase.MODEL_REGISTRY["survey_ols"] == SurveyOLSModel
    @test MetricaBase.MODEL_REGISTRY["survey_logit"] == SurveyLogitModel
end

# === Task 22-23: Wald F 和置信区间验证 =========================================

@testset "Survey OLS Wald F 检验" begin
    df = make_survey_data()
    result = MetricaBase.fit(SurveyOLSModel, "y ~ x1 + x2", df;
        weights_column=:wt, strata_column=:stratum, psu_column=:psu)

    g = MetricaBase.glance(result)
    @test haskey(g.metrics, :wald_f)
    @test haskey(g.metrics, :wald_pvalue)
    @test g.metrics[:wald_f] > 0
    @test 0.0 <= g.metrics[:wald_pvalue] <= 1.0
end

@testset "Survey OLS 置信区间" begin
    df = make_survey_data()
    result = MetricaBase.fit(SurveyOLSModel, "y ~ x1 + x2", df;
        weights_column=:wt, strata_column=:stratum, psu_column=:psu)

    t = MetricaBase.tidy(result)
    for row in t.rows
        @test row.ci_lower !== nothing
        @test row.ci_upper !== nothing
        @test row.ci_lower < row.estimate
        @test row.ci_upper > row.estimate
    end
end

@testset "Survey Logit Wald F 和置信区间" begin
    df = make_survey_data()
    result = MetricaBase.fit(SurveyLogitModel, "y_bin ~ x1 + x2", df;
        weights_column=:wt, strata_column=:stratum, psu_column=:psu)

    g = MetricaBase.glance(result)
    @test haskey(g.metrics, :wald_f)
    @test haskey(g.metrics, :wald_pvalue)
    @test g.metrics[:wald_f] > 0

    t = MetricaBase.tidy(result)
    for row in t.rows
        @test row.ci_lower !== nothing
        @test row.ci_upper !== nothing
        @test row.ci_lower < row.estimate
        @test row.ci_upper > row.estimate
    end
end

@testset "Survey Poisson Wald F 和置信区间" begin
    df = make_survey_data()
    df.y_count = round.(Int, max.(df.y .+ 5, 1))
    result = MetricaBase.fit(SurveyPoissonModel, "y_count ~ x1 + x2", df;
        weights_column=:wt)

    g = MetricaBase.glance(result)
    @test haskey(g.metrics, :wald_f)
    @test haskey(g.metrics, :wald_pvalue)

    t = MetricaBase.tidy(result)
    for row in t.rows
        @test row.ci_lower !== nothing
        @test row.ci_upper !== nothing
        @test row.ci_lower < row.estimate
        @test row.ci_upper > row.estimate
    end
end

@testset "Survey 序列化包含 CI" begin
    df = make_survey_data()
    result = MetricaBase.fit(SurveyOLSModel, "y ~ x1 + x2", df;
        weights_column=:wt, strata_column=:stratum, psu_column=:psu)
    payload = result_to_payload(result; include_augment=false)
    tidy_payload = payload["result_payload"]["tidy"]
    @test haskey(tidy_payload[1], "ci_lower")
    @test haskey(tidy_payload[1], "ci_upper")
    @test tidy_payload[1]["ci_lower"] < tidy_payload[1]["estimate"]
    @test tidy_payload[1]["ci_upper"] > tidy_payload[1]["estimate"]
end
