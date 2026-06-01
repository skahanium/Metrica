using Test
using DataFrames
using MetricaBase
using MetricaGMM

include("test_golden.jl")

@testset "GMMLinearModel 恰识别" begin
    io = IOBuffer()
    println(io, "y,x1,z1")
    for i in 1:20
        z = Float64(i)
        x = 0.5z + randn() * 0.1
        y = 1.0 + 2.0x + randn() * 0.2
        println(io, "$y,$x,$z")
    end
    path, f = mktemp()
    write(path, take!(io))
    close(f)
    r = fit(GMMLinearModel, "y ~ x1", path; instruments = ["z1"], endog = ["x1"], gmm_weight = "two_step")
    rm(path; force = true)
    @test r isa GMMLinearFitResult
    d = r.gmm_diagnostics
    @test d[:exactly_identified] === true
    @test d[:j_df] == 0
    @test d[:j_pvalue] === nothing
end

@testset "GMMLinearModel 过识别与 J 检验" begin
    path, io = mktemp()
    write(io, """y,x1,x2,z1,z2
10,1,2,3,1
12,2,1,6,2
14,3,3,9,3
20,2,2,4,4
22,3,1,7,5
24,4,2,10,6
30,5,1,5,7
32,6,3,11,8
""")
    close(io)
    r = fit(GMMLinearModel, "y ~ x1 + x2", path; instruments = ["z1", "z2"], endog = ["x1"], gmm_weight = "two_step")
    rm(path; force = true)
    @test r isa GMMLinearFitResult
    d = r.gmm_diagnostics
    @test d[:n_moments] == 4  # 截距 + x2 + z1 + z2
    @test d[:n_params] == 3   # 截距 + x1 + x2
    @test d[:j_df] == 1
    @test d[:j_pvalue] !== nothing
    @test d[:j_statistic] >= 0
    @test d[:gmm_weight] == "two_step"
    @test d[:iterations] == 2
end

@testset "GMMLinearModel 欠识别（矩条件不足）" begin
    # 单工具、双内生：在 IV 阶即拒绝
    path, io = mktemp()
    write(io, "y,x1,x2,z\n1,1,1,1\n")
    close(io)
    r = fit(GMMLinearModel, "y ~ x1 + x2", path; instruments = ["z"], endog = ["x1", "x2"], gmm_weight = "two_step")
    rm(path; force = true)
    @test r isa MetricaBase.ModelError
    @test r.code == :underidentified_model
end

@testset "GMMLinearModel 非法 gmm_weight" begin
    path, io = mktemp()
    write(io, "y,x,z\n1,1,1\n2,2,2\n3,3,3\n")
    close(io)
    r = fit(GMMLinearModel, "y ~ x", path; instruments = ["z"], endog = ["x"], gmm_weight = "bogus")
    rm(path; force = true)
    @test r isa MetricaBase.ModelError
    @test r.code == :invalid_gmm_weight
end

@testset "GMMLinearModel 弱工具警告" begin
    weak_csv, weak_io = mktemp()
    close(weak_io)
    write(weak_csv, """y,x,x1,z
10,3,1,1.1
12,5,2,1.9
14,7,3,3.2
16,9,4,3.8
18,11,5,5.3
20,13,6,5.7
22,15,7,7.1
24,17,8,8.2
26,19,9,8.9
28,21,10,10.1
30,23,11,11.3
32,25,12,11.8
34,27,13,13.1
36,29,14,13.9
38,31,15,15.2
40,33,16,15.7
42,35,17,17.1
44,37,18,18.3
46,39,19,18.8
48,41,20,20.2
""")
    r = fit(GMMLinearModel, "y ~ x1 + x", weak_csv; instruments = ["z"], endog = ["x"], gmm_weight = "one_step")
    rm(weak_csv; force = true)
    @test r isa GMMLinearFitResult
    @test any(w.code == :weak_instrument for w in r.glance_table.warnings)
end

@testset "GMMLinearModel 奇异一步权重 (Z'Z)" begin
    io = IOBuffer()
    println(io, "y,x1,x2,z1")
    for i in 1:25
        println(io, "$(10 + i),$(0.1 * i),$i,$(i * i)")
    end
    path, f = mktemp()
    write(path, take!(io))
    close(f)
    r = fit(GMMLinearModel, "y ~ x1 + x2", path; instruments = ["z1", "z1"], endog = ["x1"], gmm_weight = "one_step")
    rm(path; force = true)
    @test r isa MetricaBase.ModelError
    @test r.code == :singular_weight_matrix
end

@testset "result_to_payload 含 diagnostics" begin
    path, io = mktemp()
    write(io, """y,x1,x2,z1,z2
10,1,2,3,1
12,2,1,6,2
14,3,3,9,3
20,2,2,4,4
22,3,1,7,5
24,4,2,10,6
30,5,1,5,7
""")
    close(io)
    r = fit(GMMLinearModel, "y ~ x1 + x2", path; instruments = ["z1", "z2"], endog = ["x1"], gmm_weight = "two_step")
    rm(path; force = true)
    @test r isa GMMLinearFitResult
    p = result_to_payload(r; include_augment = false)
    @test p["status"] == "success"
    diag = p["result_payload"]["diagnostics"]
    @test haskey(diag, "j_statistic")
    @test haskey(diag, "j_df")
end
