using MetricaBase, Test

@testset "serialize.jl helpers" begin
    @testset "severity_to_string" begin
        @test severity_to_string(info) == "info"
        @test severity_to_string(warning) == "warning"
        @test severity_to_string(critical) == "critical"
    end

    @testset "warning_to_dict" begin
        w = ModelWarning(:rows_dropped, "行删除", "删除了 3 行", "检查缺失", warning)
        d = warning_to_dict(w)
        @test d["code"] == "rows_dropped"
        @test d["title"] == "行删除"
        @test d["detail"] == "删除了 3 行"
        @test d["hint"] == "检查缺失"
        @test d["severity"] == "warning"
        w2 = ModelWarning(:x, "T", "D", nothing, info)
        @test warning_to_dict(w2)["hint"] === nothing
    end

    @testset "error_to_payload" begin
        e = ModelError(:bad, "失败", "细节", "提示")
        p = error_to_payload(e)
        @test p["status"] == "error"
        @test length(p["messages"]) == 1
        @test p["messages"][1]["code"] == "bad"
        @test p["messages"][1]["text"] == "细节"
    end

    @testset "capabilities_to_dict" begin
        caps = ModelCapabilities(
            :partial, :linear, [:ols], ["ols"],
            [:r2], [:vif], Symbol[], true, ["note"],
        )
        d = capabilities_to_dict(caps)
        @test d["status"] == "partial"
        @test d["model_family"] == "linear"
        @test d["supported_models"] == ["ols"]
        @test d["prediction_available"] === true
    end

    @testset "dict_symbol_to_string" begin
        inner = Dict{Symbol, Any}(:a => 1, :b => nothing)
        out = dict_symbol_to_string(Dict{Symbol, Any}(:k => :sym, :inner => inner, :x => 2))
        @test out["k"] == "sym"
        @test out["inner"]["a"] == 1
        @test out["inner"]["b"] === nothing
        @test out["x"] == 2
    end

    @testset "build_glance_envelope" begin
        w = ModelWarning(:w, "T", "D", nothing, info)
        gl = ModelGlance(:ols, 10, 2, Dict(:r2 => 0.5), [w])
        gd, ws = build_glance_envelope(gl)
        @test gd["model"] == "ols"
        @test gd["nobs"] == 10
        @test gd["metrics"]["r2"] == 0.5
        @test length(ws) == 1
        @test ws[1]["code"] == "w"
    end

    @testset "build_tidy_rows" begin
        rows = [
            CoefRow(:x1, 1.0, 0.1, 10.0, 0.01, 0.8, 1.2),
            CoefRow(:x2, 2.0, NaN, nothing, nothing, nothing, nothing),
        ]
        tr = build_tidy_rows(TidyTable(rows, "classical"))
        @test tr[1]["name"] == "x1"
        @test tr[1]["stderror"] == 0.1
        @test tr[2]["stderror"] === nothing
    end

    @testset "build_messages" begin
        w = ModelWarning(:code, "T", "detail text", "hint", warning)
        gl = ModelGlance(:ols, 5, 1, Dict{Symbol, MetricValue}(), [w])
        msgs = build_messages(gl)
        @test msgs[1]["level"] == "warning"
        @test msgs[1]["code"] == "code"
        @test msgs[1]["text"] == "detail text"
    end

    @testset "build_augment_status" begin
        s1 = build_augment_status(
            nothing;
            available=true,
            columns_available=["fitted"],
            preview_included=true,
            preview_rows=5,
        )
        @test s1["available"] === true
        @test s1["columns_available"] == ["fitted"]
        s2 = build_augment_status(nothing; available=false, columns_unavailable=["leverage"])
        @test s2["available"] === false
        @test s2["columns_unavailable"] == ["leverage"]
    end

    @testset "build_augment_preview" begin
        at = AugmentTable(Dict(:fitted => [1.0, 2.0, 3.0], :residual => [0.1, 0.2, 0.3]), 3)
        prev = build_augment_preview(at; max_rows=2)
        @test length(prev) == 2
        @test prev[1]["fitted"] == 1.0
        empty_at = AugmentTable()
        @test build_augment_preview(empty_at) == []
    end

    @testset "try_capabilities" begin
        struct CapResultTest end
        MetricaBase.model_capabilities(::CapResultTest) = ModelCapabilities(
            :full, :test, [:t], String[], Symbol[], Symbol[], Symbol[], true, String[],
        )
        d = try_capabilities(CapResultTest())
        @test d !== nothing
        @test d["model_family"] == "test"
        struct EmptyCapsTest end
        MetricaBase.model_capabilities(::EmptyCapsTest) = nothing
        @test try_capabilities(EmptyCapsTest()) === nothing
    end
end

@testset "parse_metrica_formula" begin
    @test parse_metrica_formula("y ~ x1 + x2") == ("y", ["x1", "x2"])
    @test parse_metrica_formula("  y  ~  x1  +  x2  ") == ("y", ["x1", "x2"])
    e1 = parse_metrica_formula(" ~ x1")
    @test e1 isa ModelError
    e2 = parse_metrica_formula("y ~ x1 ~ x2")
    @test e2 isa ModelError
    e3 = parse_metrica_formula("")
    @test e3 isa ModelError
end
