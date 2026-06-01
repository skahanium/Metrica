using Test

include("test_golden.jl")
using MetricaBase
using MetricaSystem

const DEMO = joinpath(@__DIR__, "..", "..", "..", "datasets", "demo")

@testset "SUR 主路径" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ x1 + x2", "y2 ~ x1 + x2"])
    @test r isa SystemEquationsFitResult
    @test length(r.equation_glances) == 2
    @test length(r.tidy_table.rows) > 2
    @test length(r.tidy_equation_labels) == length(r.tidy_table.rows)
    Σ = r.diagnostics[:sigma_residual]
    @test size(Σ, 1) == size(Σ, 2) == 2
    @test sqrt(sum(abs2, Σ .- Σ')) < 1e-8
    @test all(Σ[i, i] > 0 for i in 1:size(Σ, 1))
    p = result_to_payload(r)
    @test p["status"] == "success"
    @test haskey(p["result_payload"], "equation_glances")
    @test haskey(p["result_payload"]["diagnostics"], "sigma_residual")
end

@testset "system_2sls 小样本" begin
    path = joinpath(DEMO, "system_2sls_demo.csv")
    r = fit(
        System2SLSModel, "", path;
        equations = ["y1 ~ x1 + x2"],
        system_endogenous = [["x1"]],
        system_instruments = [["z1"]],
    )
    @test r isa SystemEquationsFitResult
    @test r.system_method == "2sls"
    g = glance(r)
    @test g.nobs >= 5
    pl = result_to_payload(r)
    @test pl["status"] == "success"
end

@testset "system_3sls 主路径" begin
    path = joinpath(DEMO, "system_2sls_demo.csv")
    r = fit(
        System3SLSModel, "", path;
        equations = ["y1 ~ x1 + x2"],
        system_endogenous = [["x1"]],
        system_instruments = [["z1"]],
    )
    @test r isa SystemEquationsFitResult
    @test r.system_method == "3sls"
    @test length(r.equation_glances) == 1
    p = result_to_payload(r)
    @test haskey(p["result_payload"]["diagnostics"], "system_method")
end

@testset "SUR 系数与残差结构" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ x1", "y2 ~ x1"])
    @test r isa SystemEquationsFitResult
    tidy = MetricaBase.tidy(r)
    @test length(tidy.rows) >= 2
    names = [String(row.name) for row in tidy.rows]
    @test any(occursin("x1", n) for n in names)
    aug = augment(r)
    @test aug isa AugmentTable
    @test aug.nobs == 0
end

@testset "2SLS 内生结构" begin
    path = joinpath(DEMO, "system_2sls_demo.csv")
    r = fit(
        System2SLSModel, "", path;
        equations = ["y1 ~ x1 + x2"],
        system_endogenous = [["x1"]],
        system_instruments = [["z1"]],
    )
    @test r isa SystemEquationsFitResult
    coefs = [row.estimate for row in MetricaBase.tidy(r).rows]
    @test any(isfinite, coefs)
end

@testset "方程数过多" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    eqs = ["y1 ~ x1" for _ in 1:9]
    r = fit(SURModel, "", path; equations = eqs)
    @test r isa MetricaBase.ModelError
    @test r.code == :too_many_equations
end

@testset "单方程 SUR 退化" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ x1 + x2"])
    @test r isa SystemEquationsFitResult || r isa MetricaBase.ModelError
end

@testset "system IV 形状错误" begin
    path = joinpath(DEMO, "system_2sls_demo.csv")
    r = fit(
        System2SLSModel, "", path;
        equations = ["y1 ~ x1", "y2 ~ x2"],
        system_endogenous = [["x1"]],
        system_instruments = [["z1"]],
    )
    @test r isa MetricaBase.ModelError
    @test r.code == :system_iv_shape
end

@testset "方程语法错误" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["not_a_formula"])
    @test r isa MetricaBase.ModelError
end

@testset "变量不存在" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ no_such_var"])
    @test r isa MetricaBase.ModelError
end

@testset "SUR 自定义迭代" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(
        SURModel, "", path;
        equations = ["y1 ~ x1 + x2", "y2 ~ x1 + x2"],
        sur_max_iter=5,
        sur_tol=1e-4,
    )
    @test r isa SystemEquationsFitResult
end

@testset "跨方程相关矩阵" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ x1 + x2", "y2 ~ x1 + x2"])
    ρ = r.diagnostics[:equation_correlation]
    @test ρ !== nothing
    @test size(ρ, 1) == 2
    @test all(-1.0 .<= ρ .<= 1.0 .+ 1e-8)
end

@testset "SUR model_capabilities" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ x1", "y2 ~ x1"])
    caps = model_capabilities(r)
    @test caps.model_family == :system
    @test :sur in caps.supported_models
    @test :sigma_residual in caps.diagnostics_available
end

@testset "2SLS 与 3SLS capabilities" begin
    path = joinpath(DEMO, "system_2sls_demo.csv")
    r2 = fit(
        System2SLSModel, "", path;
        equations = ["y1 ~ x1 + x2"],
        system_endogenous = [["x1"]],
        system_instruments = [["z1"]],
    )
    r3 = fit(
        System3SLSModel, "", path;
        equations = ["y1 ~ x1 + x2"],
        system_endogenous = [["x1"]],
        system_instruments = [["z1"]],
    )
    @test model_capabilities(r2).supported_models == [:sur, :system_2sls, :system_3sls]
    @test model_capabilities(r3).estimators == ["2SLS residuals Σ + single-step GLS"]
end

@testset "SUR equation_glances 指标" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ x1 + x2", "y2 ~ x1 + x2"])
    for g in r.equation_glances
        @test g.nobs > 0
        @test !isempty(g.metrics)
    end
    g_all = glance(r)
    @test g_all.nobs == r.nobs
end

@testset "SUR payload 与 messages" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ x1", "y2 ~ x1"])
    p = result_to_payload(r; include_augment=false)
    @test p["status"] == "success"
    @test haskey(p["result_payload"], "tidy")
    @test haskey(p["result_payload"]["tidy"][1], "equation")
end

@testset "空方程列表" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = String[])
    @test r isa MetricaBase.ModelError
end

@testset "SUR 系数估计有限" begin
    path = joinpath(DEMO, "sur_system_demo.csv")
    r = fit(SURModel, "", path; equations = ["y1 ~ x1 + x2", "y2 ~ x1 + x2"])
    est = [row.estimate for row in tidy(r).rows]
    @test all(isfinite, est)
    ses = [row.stderror for row in tidy(r).rows]
    @test any(s -> s !== nothing && isfinite(s), ses)
end

@testset "3SLS diagnostics system_method" begin
    path = joinpath(DEMO, "system_2sls_demo.csv")
    r = fit(
        System3SLSModel, "", path;
        equations = ["y1 ~ x1 + x2"],
        system_endogenous = [["x1"]],
        system_instruments = [["z1"]],
    )
    @test r.diagnostics[:system_method] == "3sls"
    p = result_to_payload(r)
    @test p["result_payload"]["diagnostics"]["system_method"] == "3sls"
end

@testset "2SLS 工具不足" begin
    path = joinpath(DEMO, "system_2sls_demo.csv")
    r = fit(
        System2SLSModel, "", path;
        equations = ["y1 ~ x1 + x2"],
        system_endogenous = [["x1", "x2"]],
        system_instruments = [["z1"]],
    )
    @test r isa MetricaBase.ModelError || r isa SystemEquationsFitResult
end

@testset "SUR 已知 DGP 系数符号与量级" begin
    n = 500
    x1 = [sin(0.17 * i) + 0.3 * cos(0.11 * i) for i in 1:n]
    x2 = [cos(0.13 * i) - 0.2 * sin(0.09 * i) for i in 1:n]
    e1 = [0.4 * sin(0.31 * i + 1.0) for i in 1:n]
    e2 = [0.4 * cos(0.27 * i + 2.0) + 0.25 * e1[i] for i in 1:n]
    y1 = 1.0 .+ 2.0 .* x1 .+ e1
    y2 = -0.5 .+ 1.5 .* x2 .+ e2
    tmp = joinpath(@__DIR__, "sur_dgp.csv")
    open(tmp, "w") do io
        println(io, "y1,y2,x1,x2")
        for i in 1:n
            println(io, "$(y1[i]),$(y2[i]),$(x1[i]),$(x2[i])")
        end
    end
    r = fit(SURModel, "", tmp; equations=["y1 ~ x1", "y2 ~ x2"])
    rm(tmp; force=true)
    @test r isa SystemEquationsFitResult
    rows = tidy(r).rows
    labels = r.tidy_equation_labels
    b_y1_x1 = only(row.estimate for (lab, row) in zip(labels, rows) if lab == "eq1" && row.name == :x1)
    b_y2_x2 = only(row.estimate for (lab, row) in zip(labels, rows) if lab == "eq2" && row.name == :x2)
    @test b_y1_x1 > 1.2
    @test b_y2_x2 > 0.9
end
