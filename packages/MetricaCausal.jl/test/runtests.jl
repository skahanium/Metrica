using MetricaCausal, MetricaBase, MetricaPanel, MetricaDiscrete
using DataFrames, Distributions, Random, Statistics, Test, LinearAlgebra

Random.seed!(42)

# === TWFE ====================================================================

@testset "TWFE" begin
    n = 100
    ids = repeat(1:10, inner=10)
    times = repeat(1:10, outer=10)
    x = randn(n)
    y = 1.0 .+ 0.5 .* x .+ randn(n) .* 0.05
    X = hcat(ones(n), x)
    twfe = fit_twfe(X, y, ids, times)
    @test length(twfe.coefficients) == 1
    @test abs(twfe.coefficients[1] - 0.5) < 0.2
    @test twfe.dof > 0
    @test size(twfe.vcov) == (1, 1)
end

# === DID =====================================================================

@testset "DID" begin
    # Deterministic DID data: true effect = 2.0
    n = 40
    df = DataFrame(
        id = repeat(1:10, inner=4),
        time = repeat(1:4, outer=10),
        treated = Float64.(repeat([0, 0, 1, 1], inner=10)),
        x1 = ones(n),
    )
    df.post = Float64.(df.time .>= 3)
    df.y = 3.0 .+ 0.5 .* df.treated .+ 0.3 .* df.post .+ 2.0 .* df.treated .* df.post .+ 0.1 .* df.x1

    result = MetricaBase.fit(DIDModel, "y ~ treated * post + x1", df;
        panel_id=:id, panel_time=:time, treated_column=:treated, post_column=:post)
    @test result isa DIDFitResult
    @test abs(result.treat_effect - 2.0) < 1.0
    @test result.treat_effect_se > 0
    @test result.n_treated + result.n_control == 40

    g = MetricaBase.glance(result)
    @test g.model == :did

    t = MetricaBase.tidy(result)
    @test length(t.rows) >= 1

    # 序列化
    payload = MetricaCausal.result_to_payload(result)
    @test payload["status"] == "success"
    @test haskey(payload["result_payload"], "treat_effect")

    # 协议方法
    @test MetricaBase.nobs(result) == 40
    @test length(MetricaBase.coef(result)) >= 1
    @test size(MetricaBase.vcov(result), 1) >= 1
end

# === Event Study =============================================================

@testset "EventStudy" begin
    n = 60
    df = DataFrame(
        id = repeat(1:10, inner=6),
        time = repeat(1:6, outer=10),
        treated = Float64.(repeat([0, 0, 1, 1], inner=15)),
        event_time = repeat([4, 4, 4, 4], inner=15),
        x1 = ones(n),
    )
    df.y = 2.0 .+ 1.0 .* df.treated .* Float64.(df.time .>= 4) .+ 0.1 .* df.x1

    result = MetricaBase.fit(EventStudyModel, "y ~ treated + x1", df;
        panel_id=:id, panel_time=:time, treated_column=:treated,
        event_time_column=:event_time, pre_periods=2, post_periods=2)
    @test result isa EventStudyFitResult
    @test length(result.period_coefficients) >= 1
    @test result.pre_trend_pvalue isa Float64

    g = MetricaBase.glance(result)
    @test g.model == :event_study

    payload = MetricaCausal.result_to_payload(result)
    @test haskey(payload["result_payload"], "period_coefficients")
end

# === IPW =====================================================================

@testset "IPW" begin
    n = 500
    x1 = randn(n); x2 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8*x1 .- 0.3*x2)))
    treat = Float64.(rand(n) .< ps)
    y0 = 2.0 .+ 0.5*x1 .+ 0.2*x2 .+ randn(n)*0.3
    y1 = y0 .+ 1.5
    y = treat.*y1 .+ (1 .- treat).*y0
    df = DataFrame(treat=treat, y=y, x1=x1, x2=x2)

    result = MetricaBase.fit(IPWModel, "", df;
        treatment_column=:treat, outcome_column=:y, propensity_formula="treat ~ x1 + x2")
    @test result isa IPWFitResult
    @test abs(result.ate - 1.5) < 0.5
    @test result.ate_se > 0
    @test result.att_se > 0
    @test result.atu_se > 0
    @test result.atu_se != result.ate_se

    t = MetricaBase.tidy(result)
    @test length(t.rows) == 3
    @test t.rows[1].name == :ATE
    @test t.rows[2].name == :ATT
    @test t.rows[3].name == :ATU
end

# === PSM =====================================================================

@testset "PSM" begin
    n = 500
    x1 = randn(n); x2 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8*x1 .- 0.3*x2)))
    treat = Float64.(rand(n) .< ps)
    y0 = 2.0 .+ 0.5*x1 .+ 0.2*x2 .+ randn(n)*0.3
    y1 = y0 .+ 1.5
    y = treat.*y1 .+ (1 .- treat).*y0
    df = DataFrame(treat=treat, y=y, x1=x1, x2=x2)

    result = MetricaBase.fit(PSMModel, "", df;
        treatment_column=:treat, outcome_column=:y, propensity_formula="treat ~ x1 + x2")
    @test result isa PSMFitResult
    @test result.n_matched > 0
    @test abs(result.att - 1.5) < 0.5
    @test nrow(result.balance_table) > 0

    payload = MetricaCausal.result_to_payload(result)
    @test haskey(payload["result_payload"], "balance_table")
end

# === AIPW ====================================================================

@testset "AIPW" begin
    n = 500
    x1 = randn(n); x2 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8*x1 .- 0.3*x2)))
    treat = Float64.(rand(n) .< ps)
    y0 = 2.0 .+ 0.5*x1 .+ 0.2*x2 .+ randn(n)*0.3
    y1 = y0 .+ 1.5
    y = treat.*y1 .+ (1 .- treat).*y0
    df = DataFrame(treat=treat, y=y, x1=x1, x2=x2)

    result = MetricaBase.fit(AIPWModel, "", df;
        treatment_column=:treat, outcome_column=:y,
        outcome_formula="y ~ x1 + x2", propensity_formula="treat ~ x1 + x2")
    @test result isa AIPWFitResult
    @test abs(result.ate - 1.5) < 0.8
    @test result.ate_se > 0
end

@testset "AIPW 按处理组分别拟合结果模型" begin
    # 验证 AIPW 正确分别拟合 E[Y|X,T=1] 和 E[Y|X,T=0]
    # 当处理组和控制组的协变量系数不同时，分别拟合才能得到正确的 ATE
    Random.seed!(123)
    n = 1000
    x1 = randn(n); x2 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8*x1 .- 0.3*x2)))
    treat = Float64.(rand(n) .< ps)

    # 控制组: y0 = 2.0 + 0.5*x1 + 0.2*x2
    # 处理组: y1 = 5.0 + 1.5*x1 + 0.8*x2  (不同的截距和系数)
    y0 = 2.0 .+ 0.5*x1 .+ 0.2*x2 .+ randn(n)*0.3
    y1 = 5.0 .+ 1.5*x1 .+ 0.8*x2 .+ randn(n)*0.3
    y = treat.*y1 .+ (1 .- treat).*y0
    df = DataFrame(treat=treat, y=y, x1=x1, x2=x2)

    result = MetricaBase.fit(AIPWModel, "", df;
        treatment_column=:treat, outcome_column=:y,
        outcome_formula="y ~ x1 + x2", propensity_formula="treat ~ x1 + x2")
    @test result isa AIPWFitResult

    # 真实 ATE = E[Y1 - Y0] = (5.0-2.0) + (1.5-0.5)*E[x1] + (0.8-0.2)*E[x2]
    # 由于 E[x1]=E[x2]=0，真实 ATE = 3.0
    true_ate = 3.0
    @test abs(result.ate - true_ate) < 0.5

    # 验证 outcome_model 是分别拟合的（存储为 tuple）
    @test result.outcome_model isa NamedTuple
    @test haskey(result.outcome_model, :treated)
    @test haskey(result.outcome_model, :control)

    # 验证处理组和控制组的系数不同
    β_treated = result.outcome_model.treated.coefficient_values
    β_control = result.outcome_model.control.coefficient_values
    @test abs(β_treated[1] - 5.0) < 0.5  # 处理组截距
    @test abs(β_control[1] - 2.0) < 0.5  # 控制组截距
end

# === TreatmentEffectSummary ==================================================

@testset "TreatmentEffectSummary" begin
    n = 300
    x1 = randn(n)
    ps = 1.0 ./ (1.0 .+ exp.(-(0.5 .+ 0.8*x1)))
    treat = Float64.(rand(n) .< ps)
    y0 = 2.0 .+ 0.5*x1 .+ randn(n)*0.3
    y1 = y0 .+ 1.5
    y = treat.*y1 .+ (1 .- treat).*y0
    df = DataFrame(treat=treat, y=y, x1=x1)

    ipw_r = MetricaBase.fit(IPWModel, "", df;
        treatment_column=:treat, outcome_column=:y, propensity_formula="treat ~ x1")
    aipw_r = MetricaBase.fit(AIPWModel, "", df;
        treatment_column=:treat, outcome_column=:y,
        outcome_formula="y ~ x1", propensity_formula="treat ~ x1")

    summaries = compare_estimates(Dict(:ipw => ipw_r, :aipw => aipw_r))
    @test length(summaries) == 2
    @test all(s -> abs(s.ate - 1.5) < 0.8, summaries)
end

# === 聚类标准误一致性 =========================================================

@testset "cluster SE 使用吸收后数据" begin
    # 构造面板数据，使得去均值前后的残差和设计矩阵不同
    Random.seed!(123)
    n_panel = 8
    n_time = 5
    n = n_panel * n_time
    ids = repeat(1:n_panel, inner=n_time)
    times = repeat(1:n_time, outer=n_panel)

    # 每个个体有不同截距，去均值会改变设计矩阵
    group_intercept = repeat(randn(n_panel) .* 3.0, inner=n_time)
    x = randn(n) .+ group_intercept
    treated = Float64.(repeat([0, 0, 1, 1, 1], outer=n_panel))
    post = Float64.(repeat([0, 0, 0, 1, 1], outer=n_panel))
    # 聚类相关误差：每个个体有共同的随机截距
    cluster_effect = repeat(randn(n_panel) .* 2.0, inner=n_time)
    y = 1.0 .+ 0.5 .* treated .+ 0.3 .* post .+ 1.5 .* treated .* post .+
        0.8 .* x .+ cluster_effect .+ randn(n) .* 0.1

    df = DataFrame(id=ids, time=times, treated=treated, post=post, x1=x, y=y)

    # 通过 DID 模型获取聚类标准误
    result = MetricaBase.fit(DIDModel, "y ~ treated * post + x1", df;
        panel_id=:id, panel_time=:time, treated_column=:treated, post_column=:post,
        vcov=:cluster)

    @test result isa DIDFitResult

    # 手动用吸收后数据计算正确的聚类稳健方差
    X_work = hcat(treated, post, treated .* post, x)
    nobs = size(X_work, 1)
    p = size(X_work, 2)

    # 交替投影吸收固定效应
    y_demeaned = copy(y)
    X_demeaned = copy(X_work)
    for iter in 1:10
        y_prev = copy(y_demeaned)
        X_prev = copy(X_demeaned)
        for gid in unique(ids)
            mask = ids .== gid
            y_demeaned[mask] .-= mean(y_demeaned[mask])
            for j in 1:p
                X_demeaned[mask, j] .-= mean(X_demeaned[mask, j])
            end
        end
        for t in unique(times)
            mask = times .== t
            y_demeaned[mask] .-= mean(y_demeaned[mask])
            for j in 1:p
                X_demeaned[mask, j] .-= mean(X_demeaned[mask, j])
            end
        end
        if norm(y_demeaned - y_prev) + norm(X_demeaned - X_prev) < 1e-8 * (norm(y) + norm(X_work) + 1.0)
            break
        end
    end

    # OLS on demeaned data
    β = X_demeaned \ y_demeaned
    e = y_demeaned - X_demeaned * β

    # 手动 cluster sandwich（使用吸收后的 X_demeaned 和 e）
    XtX_inv = try inv(X_demeaned' * X_demeaned) catch; pinv(X_demeaned' * X_demeaned) end
    unique_ids = unique(ids)
    G = length(unique_ids)
    meat = zeros(p, p)
    for g in unique_ids
        idx = ids .== g
        Xg = X_demeaned[idx, :]
        eg = e[idx]
        meat += (Xg' * eg) * (eg' * Xg)
    end
    vcov_correct = XtX_inv * meat * XtX_inv * (G / (G - 1)) * ((nobs - 1) / (nobs - p))
    se_correct = sqrt.(max.(diag(vcov_correct), 0.0))

    # DID 的 treat_post 系数是第 3 个（treated, post, treat_post, x1）
    se_from_did = result.treat_effect_se
    se_manual = se_correct[3]

    @test abs(se_from_did - se_manual) / se_manual < 0.01
end

@testset "fit_twfe 返回吸收后数据" begin
    Random.seed!(456)
    n = 50
    ids = repeat(1:5, inner=10)
    times = repeat(1:10, outer=5)
    x = randn(n)
    y = 1.0 .+ 0.5 .* x .+ randn(n) .* 0.1
    X = hcat(ones(n), x)

    twfe = fit_twfe(X, y, ids, times)

    # 应返回 X_demeaned 和 XtX_inv
    @test :X_demeaned in propertynames(twfe)
    @test :XtX_inv in propertynames(twfe)
    @test size(twfe.X_demeaned) == (n, 1)
    @test size(twfe.XtX_inv) == (1, 1)

    # XtX_inv 应等于 inv(X_demeaned' * X_demeaned)
    @test abs(twfe.XtX_inv[1, 1] - 1.0 / (twfe.X_demeaned' * twfe.X_demeaned)[1, 1]) < 1e-10

    # vcov 应等于 sigma2 * XtX_inv
    dof_absorbed = (5 - 1) + (10 - 1)
    dof = n - 1 - dof_absorbed
    sigma2 = sum(abs2, twfe.residuals) / dof
    @test abs(twfe.vcov[1, 1] - sigma2 * twfe.XtX_inv[1, 1]) < 1e-10
end

# === 聚类标准误一致性 =========================================================

@testset "cluster SE 使用吸收后数据" begin
    # 交错 DID 设计：不同实体在不同时点接受处理
    Random.seed!(789)
    n_panel = 10
    n_time = 5
    n = n_panel * n_time
    ids = repeat(1:n_panel, inner=n_time)
    times = repeat(1:n_time, outer=n_panel)

    treated = zeros(n)
    post = zeros(n)
    for i in 1:n
        id_val = ids[i]
        t_val = times[i]
        if id_val <= 5
            treated[i] = 1.0
            post[i] = Float64(t_val >= 4)
        end
    end

    x = randn(n)
    cluster_effect = repeat(randn(n_panel) .* 0.3, inner=n_time)
    y = 2.0 .+ 0.5 .* treated .+ 0.3 .* post .+ 1.5 .* treated .* post .+
        0.8 .* x .+ cluster_effect .+ randn(n) .* 0.1

    df = DataFrame(id=ids, time=times, treated=treated, post=post, x1=x, y=y)

    result = MetricaBase.fit(DIDModel, "y ~ treated * post + x1", df;
        panel_id=:id, panel_time=:time, treated_column=:treated, post_column=:post,
        vcov=:cluster)

    @test result isa DIDFitResult

    # 手动用吸收后数据计算正确的聚类稳健方差
    X_work = hcat(treated, post, treated .* post, x)
    nobs_v = size(X_work, 1)
    p = size(X_work, 2)

    y_demeaned = copy(y)
    X_demeaned = copy(X_work)
    for iter in 1:20
        y_prev = copy(y_demeaned)
        X_prev = copy(X_demeaned)
        for gid in unique(ids)
            mask = ids .== gid
            y_demeaned[mask] .-= mean(y_demeaned[mask])
            for j in 1:p
                X_demeaned[mask, j] .-= mean(X_demeaned[mask, j])
            end
        end
        for t in unique(times)
            mask = times .== t
            y_demeaned[mask] .-= mean(y_demeaned[mask])
            for j in 1:p
                X_demeaned[mask, j] .-= mean(X_demeaned[mask, j])
            end
        end
        if norm(y_demeaned - y_prev) + norm(X_demeaned - X_prev) < 1e-10 * (norm(y) + norm(X_work) + 1.0)
            break
        end
    end

    beta = X_demeaned \ y_demeaned
    e = y_demeaned - X_demeaned * beta

    XtX = X_demeaned' * X_demeaned
    XtX_inv = try inv(XtX) catch; pinv(XtX) end
    unique_ids = unique(ids)
    G = length(unique_ids)
    meat = zeros(p, p)
    for g in unique_ids
        idx = ids .== g
        Xg = X_demeaned[idx, :]
        eg = e[idx]
        meat += (Xg' * eg) * (eg' * Xg)
    end
    vcov_correct = XtX_inv * meat * XtX_inv * (G / (G - 1)) * ((nobs_v - 1) / (nobs_v - p))
    se_correct = sqrt.(max.(diag(vcov_correct), 0.0))

    se_from_did = result.treat_effect_se
    se_manual = se_correct[3]
    @test abs(se_from_did - se_manual) / se_manual < 0.01
end

@testset "fit_twfe 返回吸收后数据" begin
    Random.seed!(456)
    n = 50
    ids = repeat(1:5, inner=10)
    times = repeat(1:10, outer=5)
    x = randn(n)
    y = 1.0 .+ 0.5 .* x .+ randn(n) .* 0.1
    X = hcat(ones(n), x)

    twfe = fit_twfe(X, y, ids, times)

    @test :X_demeaned in propertynames(twfe)
    @test :XtX_inv in propertynames(twfe)
    @test size(twfe.X_demeaned) == (n, 1)
    @test size(twfe.XtX_inv) == (1, 1)
    @test abs(twfe.XtX_inv[1, 1] - 1.0 / (twfe.X_demeaned' * twfe.X_demeaned)[1, 1]) < 1e-10

    dof_absorbed = (5 - 1) + (10 - 1)
    dof_v = n - 1 - dof_absorbed
    sigma2 = sum(abs2, twfe.residuals) / dof_v
    @test abs(twfe.vcov[1, 1] - sigma2 * twfe.XtX_inv[1, 1]) < 1e-10
end

# === MODEL_REGISTRY ==========================================================

@testset "MODEL_REGISTRY" begin
    @test haskey(MetricaBase.MODEL_REGISTRY, "did")
    @test haskey(MetricaBase.MODEL_REGISTRY, "event_study")
    @test haskey(MetricaBase.MODEL_REGISTRY, "ipw")
    @test haskey(MetricaBase.MODEL_REGISTRY, "psm")
    @test haskey(MetricaBase.MODEL_REGISTRY, "aipw")
end
