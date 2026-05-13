using Test
using MetricaBase

@testset "MetricaBase 协议完整性（alpha 垂直切片）" begin

    # === Severity 枚举 ======================================================

    @testset "Severity 枚举" begin
        @test Severity isa DataType
        @test info isa Severity
        @test warning isa Severity
        @test critical isa Severity
        @test Int(info) == 0
        @test Int(warning) == 1
        @test Int(critical) == 2
        @test Severity(0) == info
        @test Severity(1) == warning
        @test Severity(2) == critical
    end

    # === 抽象类型 ===========================================================

    @testset "抽象协议类型" begin
        @test isabstracttype(AbstractEconModel)
        @test isabstracttype(AbstractFittedModel)
        @test isabstracttype(AbstractCovarianceSpec)
        @test_throws MethodError AbstractEconModel()
        @test_throws MethodError AbstractFittedModel()
        @test_throws MethodError AbstractCovarianceSpec()
    end

    # === MetricValue 类型别名 ================================================

    @testset "MetricValue 类型别名" begin
        @test MetricValue == Union{Float64, Int}
        @test 3.14 isa MetricValue
        @test 42 isa MetricValue
        @test !(1.0 + 0.0im isa MetricValue)
        @test !("string" isa MetricValue)
    end

    # === ModelWarning =======================================================

    @testset "ModelWarning 完整字段" begin
        w = ModelWarning(
            :rows_dropped,
            "Rows dropped",
            "2 rows were removed due to missing values.",
            "Inspect missing columns before fitting.",
            info,
        )

        @test w.code == :rows_dropped
        @test w.title == "Rows dropped"
        @test w.detail == "2 rows were removed due to missing values."
        @test w.hint == "Inspect missing columns before fitting."
        @test w.severity == info
        @test w.severity isa Severity
    end

    @testset "ModelWarning hint 可为 nothing" begin
        w = ModelWarning(:test_code, "Test", "Detail text.", nothing, warning)
        @test w.hint === nothing
        @test w.severity == warning
    end

    @testset "ModelWarning 三种严重程度" begin
        w_info = ModelWarning(:a, "T", "D", nothing, info)
        w_warn = ModelWarning(:b, "T", "D", "H", warning)
        w_err  = ModelWarning(:c, "T", "D", nothing, critical)

        @test w_info.severity == info
        @test w_warn.severity == warning
        @test w_err.severity == critical
    end

    # === ModelError =========================================================

    @testset "ModelError 完整字段" begin
        e = ModelError(
            :singular_design,
            "Design matrix is singular",
            "X'X is not invertible.",
            "Check for collinearity or reduce variables.",
        )

        @test e.code == :singular_design
        @test e.title == "Design matrix is singular"
        @test e.detail == "X'X is not invertible."
        @test e.hint == "Check for collinearity or reduce variables."
    end

    @testset "ModelError hint 可为 nothing" begin
        e = ModelError(:empty_sample, "Empty sample", "No valid observations.", nothing)
        @test e.code == :empty_sample
        @test e.hint === nothing
    end

    @testset "ModelError 不含 severity 字段" begin
        e = ModelError(:x, "X", "D", nothing)
        @test !hasproperty(e, :severity)
    end

    @testset "ModelWarning 与 ModelError 为独立类型" begin
        w = ModelWarning(:x, "T", "D", nothing, info)
        e = ModelError(:x, "T", "D", nothing)
        @test !(w isa ModelError)
        @test !(e isa ModelWarning)
    end

    # === ModelGlance ========================================================

    @testset "ModelGlance 完整字段" begin
        w = ModelWarning(:note, "N", "D", nothing, info)
        gl = ModelGlance(:ols, 100, 3, Dict(:r2 => 0.85, :adj_r2 => 0.84, :sigma => 2.1), [w])

        @test gl.model == :ols
        @test gl.nobs == 100
        @test gl.dof == 3
        @test gl.metrics[:r2] == 0.85
        @test gl.metrics[:adj_r2] == 0.84
        @test gl.metrics[:sigma] == 2.1
        @test length(gl.warnings) == 1
        @test gl.warnings[1].code == :note
    end

    @testset "ModelGlance 空警告与空指标" begin
        gl_empty = ModelGlance(:ols, 0, 0, Dict{Symbol, MetricValue}(), ModelWarning[])
        @test isempty(gl_empty.warnings)
        @test isempty(gl_empty.metrics)
        @test gl_empty.nobs == 0
        @test gl_empty.dof == 0
    end

    @testset "ModelGlance 多警告" begin
        ws = [
            ModelWarning(:w1, "T1", "D1", nothing, info),
            ModelWarning(:w2, "T2", "D2", "H2", warning),
        ]
        gl = ModelGlance(:ols, 50, 2, Dict(:r2 => 0.9), ws)
        @test length(gl.warnings) == 2
        @test gl.warnings[1].code == :w1
        @test gl.warnings[2].code == :w2
    end

    @testset "ModelGlance metrics 拒绝非 MetricValue" begin
        @test_throws MethodError ModelGlance(:ols, 1, 1, Dict(:bad => "string"), ModelWarning[])
        @test_throws MethodError ModelGlance(:ols, 1, 1, Dict(:bad => [1, 2, 3]), ModelWarning[])
    end

    # === CoefRow ============================================================

    @testset "CoefRow 全部字段有值" begin
        cr = CoefRow(:intercept, 1.5, 0.15, 10.0, 1e-6, nothing, nothing)
        @test cr.name == :intercept
        @test cr.estimate == 1.5
        @test cr.stderror == 0.15
        @test cr.statistic == 10.0
        @test cr.pvalue == 1e-6
        @test cr.ci_lower === nothing
        @test cr.ci_upper === nothing
    end

    @testset "CoefRow 可选字段为 nothing" begin
        cr = CoefRow(:beta, 2.0, nothing, nothing, nothing, nothing, nothing)
        @test cr.name == :beta
        @test cr.estimate == 2.0
        @test cr.stderror === nothing
        @test cr.statistic === nothing
        @test cr.pvalue === nothing
        @test cr.ci_lower === nothing
        @test cr.ci_upper === nothing
    end

    @testset "CoefRow 部分可选字段为 nothing" begin
        cr = CoefRow(:gamma, 0.5, 0.05, nothing, 0.03, nothing, nothing)
        @test cr.stderror == 0.05
        @test cr.statistic === nothing
        @test cr.pvalue == 0.03
        @test cr.ci_lower === nothing
        @test cr.ci_upper === nothing
    end

    @testset "CoefRow 字段类型稳定" begin
        cr = CoefRow(:x, 1.0, 0.2, 5.0, 0.01, nothing, nothing)
        @test cr.name isa Symbol
        @test cr.estimate isa Float64
        @test cr.stderror isa Union{Nothing, Float64}
        @test cr.statistic isa Union{Nothing, Float64}
        @test cr.pvalue isa Union{Nothing, Float64}
        @test cr.ci_lower isa Union{Nothing, Float64}
        @test cr.ci_upper isa Union{Nothing, Float64}
    end

    @testset "CoefRow 置信区间有值" begin
        cr = CoefRow(:x1, 1.5, 0.2, 7.5, 0.001, 1.1, 1.9)
        @test cr.ci_lower === 1.1
        @test cr.ci_upper === 1.9
    end

    # === TidyTable ==========================================================

    @testset "TidyTable 完整字段" begin
        rows = [
            CoefRow(:intercept, 1.0, 0.1, 10.0, 0.001, nothing, nothing),
            CoefRow(:x1, 2.0, 0.2, 10.0, 0.001, nothing, nothing),
            CoefRow(:x2, -0.5, 0.15, nothing, nothing, nothing, nothing),
        ]
        td = TidyTable(rows, "classical")

        @test length(td.rows) == 3
        @test td.vcov_label == "classical"
        @test td.rows[1].name == :intercept
        @test td.rows[2].estimate == 2.0
        @test td.rows[3].stderror == 0.15
        @test td.rows[3].statistic === nothing
    end

    @testset "TidyTable 空行" begin
        td = TidyTable(CoefRow[], "HC1")
        @test isempty(td.rows)
        @test td.vcov_label == "HC1"
    end

    @testset "TidyTable 单行" begin
        td = TidyTable([CoefRow(:a, 1.0, nothing, nothing, nothing, nothing, nothing)], "robust")
        @test length(td.rows) == 1
        @test td.vcov_label == "robust"
    end

    @testset "AugmentTable 基本结构" begin
        cols = Dict(
            :observation => [1.0, 2.0, 3.0],
            :fitted => [10.1, 12.3, 14.5],
            :residual => [-0.1, 0.3, -0.5],
        )
        at = AugmentTable(cols, 3)
        @test at.nobs == 3
        @test length(at.columns) == 3
        @test at.columns[:fitted] == [10.1, 12.3, 14.5]
        @test at.columns[:residual] == [-0.1, 0.3, -0.5]
    end

    @testset "PanelData 基本结构" begin
        # 使用简单字典模拟 DataFrame
        data = Dict(
            :firm => [1, 1, 2, 2],
            :year => [1, 2, 1, 2],
            :invest => [10.0, 12.0, 15.0, 18.0],
        )
        pd = PanelData(data, :firm, :year)
        @test pd.id_col === :firm
        @test pd.time_col === :year
        @test length(pd.data[:firm]) == 4
    end

    @testset "AbstractPanelModel 类型层级" begin
        # 验证 AbstractPanelModel 是 AbstractEconModel 的子类型
        @test AbstractPanelModel <: AbstractEconModel
    end

    # === 公共 API 函数接口 ===================================================

    @testset "函数接口存在且可调用（0 方法）" begin
        for fn in [fit, coef, vcov, predict, glance, tidy, augment]
            @test fn isa Function
        end

        @test isempty(methods(fit))
        @test isempty(methods(coef))
        @test isempty(methods(vcov))
        @test isempty(methods(predict))
        @test isempty(methods(glance))
        @test isempty(methods(tidy))
        @test isempty(methods(augment))
    end

    # === 导出完整性 =========================================================

    @testset "导出完整性" begin
        exported = Set([
            :AbstractEconModel, :AbstractFittedModel, :AbstractCovarianceSpec,
            :AbstractPanelModel,
            :Severity, :info, :warning, :critical,
            :ModelWarning, :ModelError, :MetricValue,
            :ModelGlance, :CoefRow, :TidyTable, :AugmentTable, :PanelData,
            :fit, :coef, :vcov, :predict, :glance, :tidy, :augment,
        ])
        for sym in exported
            @test isdefined(MetricaBase, sym)
        end
    end

    # === Alpha 真实 OLS 载荷契约 ============================================

    @testset "Alpha 真实 OLS 载荷契约" begin
        rows_dropped_warning = ModelWarning(
            :rows_dropped,
            "Rows dropped",
            "2 rows were removed due to missing values before estimation.",
            "Inspect missing columns before fitting.",
            info,
        )
        singular_design_error = ModelError(
            :singular_design,
            "Design matrix singular",
            "X'X is not invertible; perfect collinearity detected.",
            "Remove perfectly collinear regressors and refit.",
        )
        ols_glance = ModelGlance(
            :ols,
            98,
            3,
            Dict(
                :r2 => 0.84,
                :adj_r2 => 0.79,
                :rss => 1.2,
                :tss => 7.5,
                :sigma => 0.49,
            ),
            [rows_dropped_warning],
        )
        ols_tidy = TidyTable(
            [
                CoefRow(:Intercept, 1.2, 0.10, 12.0, 0.0001, nothing, nothing),
                CoefRow(:x1, 2.1, 0.18, 11.7, 0.0001, nothing, nothing),
            ],
            "classical",
        )

        @test rows_dropped_warning.code == :rows_dropped
        @test rows_dropped_warning.title == "Rows dropped"
        @test rows_dropped_warning.detail == "2 rows were removed due to missing values before estimation."
        @test rows_dropped_warning.hint == "Inspect missing columns before fitting."
        @test rows_dropped_warning.severity == info

        @test singular_design_error.code == :singular_design
        @test singular_design_error.title == "Design matrix singular"
        @test singular_design_error.detail == "X'X is not invertible; perfect collinearity detected."
        @test singular_design_error.hint == "Remove perfectly collinear regressors and refit."

        @test ols_glance.model == :ols
        @test ols_glance.nobs == 98
        @test ols_glance.dof == 3
        @test ols_glance.metrics == Dict(
            :r2 => 0.84,
            :adj_r2 => 0.79,
            :rss => 1.2,
            :tss => 7.5,
            :sigma => 0.49,
        )
        @test ols_glance.warnings == [rows_dropped_warning]

        @test length(ols_tidy.rows) == 2
        @test ols_tidy.rows[1] == CoefRow(:Intercept, 1.2, 0.10, 12.0, 0.0001, nothing, nothing)
        @test ols_tidy.rows[2] == CoefRow(:x1, 2.1, 0.18, 11.7, 0.0001, nothing, nothing)
        @test ols_tidy.vcov_label == "classical"
    end

    # === confint 通用实现 =====================================================

    @testset "confint 通用实现" begin

        # 模拟一个支持 coef / stderror / dof 协议的结果类型
        struct MockFitResult <: AbstractFittedModel
            _coef::Vector{Float64}
            _stderror::Union{Nothing, Vector{Float64}}
            _dof::Int
        end
        MetricaBase.coef(r::MockFitResult) = r._coef
        MetricaBase.stderror(r::MockFitResult) = r._stderror
        MetricaBase.dof(r::MockFitResult) = r._dof

        @testset "返回值结构与对称性" begin
            r = MockFitResult([1.0, 2.0, -0.5], [0.1, 0.2, 0.05], 95)
            ci_lo, ci_hi = confint(r)

            @test ci_lo isa Vector{Float64}
            @test ci_hi isa Vector{Float64}
            @test length(ci_lo) == 3
            @test length(ci_hi) == 3
            # 置信区间关于系数对称
            for i in 1:3
                @test ci_lo[i] < r._coef[i] < ci_hi[i]
                @test (r._coef[i] - ci_lo[i]) ≈ (ci_hi[i] - r._coef[i])
            end
        end

        @testset "95% 置信区间数值正确（dof=95）" begin
            # t_{0.975, 95} ≈ 1.9852506
            t_crit = 1.9852506
            r = MockFitResult([1.0, 2.0, -0.5], [0.1, 0.2, 0.05], 95)
            ci_lo, ci_hi = confint(r)

            @test ci_lo[1] ≈ 1.0 - t_crit * 0.1 atol=1e-5
            @test ci_hi[1] ≈ 1.0 + t_crit * 0.1 atol=1e-5
            @test ci_lo[2] ≈ 2.0 - t_crit * 0.2 atol=1e-5
            @test ci_hi[2] ≈ 2.0 + t_crit * 0.2 atol=1e-5
            @test ci_lo[3] ≈ -0.5 - t_crit * 0.05 atol=1e-5
            @test ci_hi[3] ≈ -0.5 + t_crit * 0.05 atol=1e-5
        end

        @testset "自定义置信水平 0.99（dof=50）" begin
            # t_{0.995, 50} ≈ 2.6777930
            t_crit = 2.6777930
            r = MockFitResult([1.0], [0.1], 50)
            ci_lo, ci_hi = confint(r; level=0.99)

            @test ci_lo[1] ≈ 1.0 - t_crit * 0.1 atol=1e-5
            @test ci_hi[1] ≈ 1.0 + t_crit * 0.1 atol=1e-5
        end

        @testset "stderror 为 nothing 时返回 nothing 填充" begin
            r = MockFitResult([1.0, 2.0], nothing, 10)
            ci_lo, ci_hi = confint(r)

            @test length(ci_lo) == 2
            @test length(ci_hi) == 2
            @test all(isnothing, ci_lo)
            @test all(isnothing, ci_hi)
        end

        @testset "自由度影响区间宽度" begin
            r_narrow = MockFitResult([1.0], [0.1], 1000)
            r_wide   = MockFitResult([1.0], [0.1], 5)

            ci_lo_n, ci_hi_n = confint(r_narrow)
            ci_lo_w, ci_hi_w = confint(r_wide)

            @test (ci_hi_n - ci_lo_n) < (ci_hi_w - ci_lo_w)
        end

        @testset "更高置信水平产生更宽区间" begin
            r = MockFitResult([1.0], [0.1], 50)
            ci_lo_90, ci_hi_90 = confint(r; level=0.90)
            ci_lo_95, ci_hi_95 = confint(r; level=0.95)
            ci_lo_99, ci_hi_99 = confint(r; level=0.99)

            @test (ci_hi_90 - ci_lo_90) < (ci_hi_95 - ci_lo_95)
            @test (ci_hi_95 - ci_lo_95) < (ci_hi_99 - ci_lo_99)
        end
    end

end
