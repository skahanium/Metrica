using MetricaSurvey
using MetricaBase
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
