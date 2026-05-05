using Test
using Random
using Statistics
using DataFrames
using MetricaBase
using MetricaTimeSeries
import MetricaBase: fit, glance, tidy, augment, coef, nobs
import MetricaTimeSeries: ForecastResult, acf, pacf, ljung_box_test, forecast

@testset "MetricaTimeSeries.jl" begin
    @testset "Module Loading" begin
        @test isdefined(MetricaTimeSeries, :AbstractTimeSeriesModel)
        @test isdefined(MetricaTimeSeries, :AbstractTSFitResult)
        @test isdefined(MetricaTimeSeries, :UnitRootModel)
        @test isdefined(MetricaTimeSeries, :UnitRootFitResult)
        @test isdefined(MetricaTimeSeries, :sort_by_time)
        @test isdefined(MetricaTimeSeries, :create_lags)
        @test isdefined(MetricaTimeSeries, :difference)
        @test isdefined(MetricaTimeSeries, :standardize_series)
    end

    @testset "Time Utilities" begin
        # 测试 sort_by_time
        df = DataFrame(time = [3, 1, 2], value = [30, 10, 20])
        sorted = MetricaTimeSeries.sort_by_time(df, :time)
        @test sorted.time == [1, 2, 3]
        @test sorted.value == [10, 20, 30]

        # 测试 create_lags
        y = [1.0, 2.0, 3.0, 4.0, 5.0]
        lag_matrix = MetricaTimeSeries.create_lags(y, 2)
        @test size(lag_matrix) == (3, 3)
        @test lag_matrix[1, 1] == 3.0  # y[t]
        @test lag_matrix[1, 2] == 2.0  # y[t-1]
        @test lag_matrix[1, 3] == 1.0  # y[t-2]

        # 测试 difference
        y = [1.0, 3.0, 6.0, 10.0, 15.0]
        d1 = MetricaTimeSeries.difference(y, 1)
        @test d1 == [2.0, 3.0, 4.0, 5.0]

        d2 = MetricaTimeSeries.difference(y, 2)
        @test d2 == [1.0, 1.0, 1.0]

        # 测试 standardize_series
        y = [1.0, 2.0, 3.0, 4.0, 5.0]
        z = MetricaTimeSeries.standardize_series(y)
        @test abs(Statistics.mean(z)) < 1e-10
        @test abs(Statistics.std(z) - 1.0) < 1e-10
    end

    @testset "Unit Root Tests" begin
        Random.seed!(1234)

        @testset "ADF Test" begin
            # 生成平稳序列（AR(1) with |φ| < 1）
            n = 200
            y_stationary = zeros(n)
            y_stationary[1] = randn()
            for t in 2:n
                y_stationary[t] = 0.5 * y_stationary[t-1] + randn()
            end

            # 生成非平稳序列（随机游走）
            y_random_walk = cumsum(randn(n))

            # 测试平稳序列
            result_stationary = MetricaTimeSeries.adf_test(y_stationary, deterministic=:constant)
            @test result_stationary.test_name == "ADF"
            @test result_stationary.p_value < 0.05  # 应拒绝单位根
            @test result_stationary.conclusion == "reject"

            # 测试非平稳序列
            result_rw = MetricaTimeSeries.adf_test(y_random_walk, deterministic=:constant)
            @test result_rw.p_value > 0.05  # 不应拒绝单位根
            @test result_rw.conclusion == "fail_to_reject"

            # 测试带趋势的序列
            result_trend = MetricaTimeSeries.adf_test(y_stationary, deterministic=:trend)
            @test result_trend.test_name == "ADF"
        end

        @testset "Phillips-Perron Test" begin
            # 生成平稳序列
            n = 200
            y_stationary = zeros(n)
            y_stationary[1] = randn()
            for t in 2:n
                y_stationary[t] = 0.5 * y_stationary[t-1] + randn()
            end

            # 生成非平稳序列
            y_random_walk = cumsum(randn(n))

            # 测试平稳序列
            result_stationary = MetricaTimeSeries.pp_test(y_stationary, deterministic=:constant)
            @test result_stationary.test_name == "Phillips-Perron"
            @test result_stationary.p_value < 0.05
            @test result_stationary.conclusion == "reject"

            # 测试非平稳序列
            result_rw = MetricaTimeSeries.pp_test(y_random_walk, deterministic=:constant)
            @test result_rw.p_value > 0.05
            @test result_rw.conclusion == "fail_to_reject"
        end

        @testset "KPSS Test" begin
            # 生成平稳序列
            n = 200
            y_stationary = zeros(n)
            y_stationary[1] = randn()
            for t in 2:n
                y_stationary[t] = 0.5 * y_stationary[t-1] + randn()
            end

            # 生成非平稳序列
            y_random_walk = cumsum(randn(n))

            # 测试平稳序列（KPSS 零假设为平稳）
            result_stationary = MetricaTimeSeries.kpss_test(y_stationary, deterministic=:constant)
            @test result_stationary.test_name == "KPSS"
            @test result_stationary.p_value > 0.05  # 不应拒绝平稳假设
            @test result_stationary.conclusion == "fail_to_reject"

            # 测试非平稳序列
            result_rw = MetricaTimeSeries.kpss_test(y_random_walk, deterministic=:constant)
            @test result_rw.p_value < 0.05  # 应拒绝平稳假设
            @test result_rw.conclusion == "reject"
        end

        @testset "UnitRootModel" begin
            # 生成测试数据
            n = 200
            Random.seed!(1234)
            y = zeros(n)
            y[1] = randn()
            for t in 2:n
                y[t] = 0.5 * y[t-1] + randn()
            end

            df = DataFrame(time = 1:n, y = y)

            # 测试 UnitRootModel 构造
            model = UnitRootModel(variable=:y, time_column=:time, deterministic=:constant)
            @test model.variable == :y
            @test model.time_column == :time
            @test model.deterministic == :constant

            # 测试 fit
            result = fit(model, df)
            @test result isa UnitRootFitResult
            @test result.variable_name == "y"
            @test !isnothing(result.adf)
            @test !isnothing(result.pp)
            @test !isnothing(result.kpss)

            # 测试 glance
            g = glance(result)
            @test g isa MetricaBase.ModelGlance
            @test g.nobs == n

            # 测试 tidy
            t = tidy(result)
            @test t isa MetricaBase.TidyTable
            @test length(t.rows) == 3  # ADF, PP, KPSS

            # 测试 nobs
            @test nobs(result) == n

            # 测试 coef
            c = coef(result)
            @test length(c) == 3  # ADF, PP, KPSS 统计量

            # 测试 augment
            a = augment(result)
            @test a isa MetricaBase.AugmentTable

            # 测试 result_to_payload
            payload = MetricaTimeSeries.result_to_payload(result)
            @test payload["model_type"] == "unitroot"
            @test payload["variable"] == "y"
            @test haskey(payload, "adf")
            @test haskey(payload, "pp")
            @test haskey(payload, "kpss")

            # 测试 include_augment
            payload_with_aug = MetricaTimeSeries.result_to_payload(result, include_augment=true)
            @test haskey(payload_with_aug, "augment_preview")
            payload_no_aug = MetricaTimeSeries.result_to_payload(result, include_augment=false)
            @test !haskey(payload_no_aug, "augment_preview")
        end
    end

    @testset "ARIMA" begin
        Random.seed!(1234)

        @testset "ARIMA(1,0,0) - AR(1)" begin
            # 生成 AR(1) 过程
            n = 200
            y = zeros(n)
            y[1] = randn()
            for t in 2:n
                y[t] = 0.5 * y[t-1] + randn()
            end

            df = DataFrame(time = 1:n, y = y)

            # 测试 ARIMAModel 构造
            model = ARIMAModel(variable=:y, time_column=:time, order=(1, 0, 0))
            @test model.variable == :y
            @test model.order == (1, 0, 0)

            # 测试 CSS 拟合
            result = fit(ARIMAModel(variable=:y, time_column=:time, order=(1, 0, 0), method=:css), df)
            @test result isa ARIMAFitResult
            @test result.order == (1, 0, 0)
            @test haskey(result.coefficients, Symbol("ar_L1"))
            @test result.aic < Inf
            @test result.bic < Inf

            # 测试协议方法
            g = glance(result)
            @test g isa MetricaBase.ModelGlance
            @test g.nobs == n

            t = tidy(result)
            @test t isa MetricaBase.TidyTable
            @test length(t.rows) >= 1

            @test nobs(result) == n
        end

        @testset "ARIMA(0,1,0) - Random Walk" begin
            n = 200
            y = cumsum(randn(n))
            df = DataFrame(time = 1:n, y = y)

            # 测试差分模型
            result = fit(ARIMAModel(variable=:y, time_column=:time, order=(0, 1, 0), method=:css), df)
            @test result isa ARIMAFitResult
            @test result.order == (0, 1, 0)
        end

        @testset "ARIMA(1,0,1) - CSS with MA estimation" begin
            # 生成 ARMA(1,1) 过程
            n = 200
            Random.seed!(42)
            y = zeros(n)
            eps = randn(n)
            y[1] = eps[1]
            for t in 2:n
                y[t] = 0.5 * y[t-1] + eps[t] + 0.3 * eps[t-1]
            end

            df = DataFrame(time = 1:n, y = y)
            result = fit(ARIMAModel(variable=:y, time_column=:time, order=(1, 0, 1), method=:css), df)
            @test result isa ARIMAFitResult
            # CSS 应同时估计 AR 和 MA 参数
            @test haskey(result.coefficients, Symbol("ar_L1"))
            @test haskey(result.coefficients, Symbol("ma_L1"))
        end

        @testset "ARIMA Serialization" begin
            n = 100
            y = zeros(n)
            y[1] = randn()
            for t in 2:n
                y[t] = 0.3 * y[t-1] + randn()
            end

            df = DataFrame(time = 1:n, y = y)
            result = fit(ARIMAModel(variable=:y, time_column=:time, order=(1, 0, 0), method=:css), df)

            payload = MetricaTimeSeries.result_to_payload(result)
            @test payload["model_type"] == "arima"
            @test payload["variable"] == "y"
            @test haskey(payload, "coefficients")
            @test haskey(payload, "glance")
            @test haskey(payload, "tidy")
            @test haskey(payload, "acf_values")
            @test haskey(payload, "pacf_values")
            @test length(payload["acf_values"]) >= 2
            @test length(payload["pacf_values"]) >= 2
            # ACF 滞后 0 应为 1
            @test payload["acf_values"][1] ≈ 1.0

            # 测试 include_augment
            payload_with_aug = MetricaTimeSeries.result_to_payload(result, include_augment=true)
            @test haskey(payload_with_aug, "augment_preview")
            payload_no_aug = MetricaTimeSeries.result_to_payload(result, include_augment=false)
            @test !haskey(payload_no_aug, "augment_preview")
        end
    end

    @testset "VAR" begin
        Random.seed!(1234)

        @testset "VAR(1) Estimation" begin
            # 生成双变量 VAR(1) 过程
            n = 200
            A1 = [0.5 0.2; -0.1 0.3]

            y = zeros(n, 2)
            y[1, :] = randn(2)
            for t in 2:n
                y[t, :] = A1 * y[t-1, :] + randn(2)
            end

            df = DataFrame(time = 1:n, x1 = y[:, 1], x2 = y[:, 2])

            # 测试 VARModel 构造
            model = VARModel(variables=[:x1, :x2], time_column=:time, lags=1)
            @test model.variables == [:x1, :x2]
            @test model.lags == 1

            # 测试 fit
            result = fit(model, df)
            @test result isa VARFitResult
            @test result.lags == 1
            @test size(result.coefficients) == (3, 2)  # 2 lags + constant × 2 vars
            @test result.aic < Inf
            @test result.bic < Inf

            # 测试协议方法
            g = glance(result)
            @test g isa MetricaBase.ModelGlance
            @test g.nobs == n - 1

            t = tidy(result)
            @test t isa MetricaBase.TidyTable
            @test length(t.rows) >= 1

            @test nobs(result) == n
        end

        @testset "Granger Causality" begin
            n = 200
            A1 = [0.5 0.2; -0.1 0.3]
            y = zeros(n, 2)
            y[1, :] = randn(2)
            for t in 2:n
                y[t, :] = A1 * y[t-1, :] + randn(2)
            end

            df = DataFrame(time = 1:n, x1 = y[:, 1], x2 = y[:, 2])

            model = VARModel(variables=[:x1, :x2], time_column=:time, lags=2)
            result = fit(model, df)

            gc = granger_causality(result, :x1, :x2)
            @test haskey(gc, :f_stat)
            @test haskey(gc, :p_value)
            @test haskey(gc, :conclusion)
            @test gc.f_stat > 0
            @test 0 <= gc.p_value <= 1
        end

        @testset "Impulse Response" begin
            n = 200
            A1 = [0.5 0.2; -0.1 0.3]
            y = zeros(n, 2)
            y[1, :] = randn(2)
            for t in 2:n
                y[t, :] = A1 * y[t-1, :] + randn(2)
            end

            df = DataFrame(time = 1:n, x1 = y[:, 1], x2 = y[:, 2])

            model = VARModel(variables=[:x1, :x2], time_column=:time, lags=1)
            result = fit(model, df)

            irf = impulse_response(result, periods=10)
            @test size(irf) == (11, 2, 2)
        end

        @testset "Variance Decomposition" begin
            n = 200
            A1 = [0.5 0.2; -0.1 0.3]
            y = zeros(n, 2)
            y[1, :] = randn(2)
            for t in 2:n
                y[t, :] = A1 * y[t-1, :] + randn(2)
            end

            df = DataFrame(time = 1:n, x1 = y[:, 1], x2 = y[:, 2])

            model = VARModel(variables=[:x1, :x2], time_column=:time, lags=1)
            result = fit(model, df)

            vd = variance_decomposition(result, periods=10)
            @test size(vd) == (11, 2, 2)
            # 方差分解应和为 1
            for t in 1:11
                for i in 1:2
                    @test abs(sum(vd[t, i, :]) - 1.0) < 1e-10
                end
            end
        end

        @testset "VAR Serialization" begin
            n = 100
            A1 = [0.5 0.2; -0.1 0.3]
            y = zeros(n, 2)
            y[1, :] = randn(2)
            for t in 2:n
                y[t, :] = A1 * y[t-1, :] + randn(2)
            end

            df = DataFrame(time = 1:n, x1 = y[:, 1], x2 = y[:, 2])

            model = VARModel(variables=[:x1, :x2], time_column=:time, lags=1)
            result = fit(model, df)

            payload = MetricaTimeSeries.result_to_payload(result)
            @test payload["model_type"] == "var"
            @test payload["variables"] == ["x1", "x2"]
            @test haskey(payload, "coefficients")
            @test haskey(payload, "glance")
            @test haskey(payload, "tidy")

            # 测试 include_augment
            payload_with_aug = MetricaTimeSeries.result_to_payload(result, include_augment=true)
            @test haskey(payload_with_aug, "augment_preview")
            payload_no_aug = MetricaTimeSeries.result_to_payload(result, include_augment=false)
            @test !haskey(payload_no_aug, "augment_preview")
        end
    end

    @testset "Cointegration" begin
        Random.seed!(1234)

        @testset "Engle-Granger" begin
            # 生成协整序列
            n = 200
            common_trend = cumsum(randn(n))

            x1 = common_trend + randn(n) * 0.5
            x2 = 0.8 * common_trend + randn(n) * 0.5

            df = DataFrame(time = 1:n, x1 = x1, x2 = x2)

            # 测试 CointegrationModel 构造
            model = CointegrationModel(
                variables=[:x1, :x2],
                time_column=:time,
                method=:engle_granger
            )
            @test model.variables == [:x1, :x2]
            @test model.method == :engle_granger

            # 测试 fit
            result = fit(model, df)
            @test result isa CointegrationFitResult
            @test result.method == :engle_granger
            @test result.n_cointegrating_relations == 1  # 应该检测到协整

            # 测试协议方法
            g = glance(result)
            @test g isa MetricaBase.ModelGlance
            @test g.nobs == n

            t = tidy(result)
            @test t isa MetricaBase.TidyTable
            @test length(t.rows) == 2  # x1, x2

            @test nobs(result) == n

            # 测试 coef
            c = coef(result)
            @test length(c) == 2  # x1, x2

            # 测试序列化
            payload = MetricaTimeSeries.result_to_payload(result)
            @test payload["model_type"] == "cointegration"
            @test payload["method"] == "engle_granger"
            @test haskey(payload, "cointegrating_vector")
        end

        @testset "Johansen" begin
            # 生成协整序列
            n = 200
            common_trend = cumsum(randn(n))

            x1 = common_trend + randn(n) * 0.5
            x2 = 0.8 * common_trend + randn(n) * 0.5

            df = DataFrame(time = 1:n, x1 = x1, x2 = x2)

            # 测试 Johansen 检验
            model = CointegrationModel(
                variables=[:x1, :x2],
                time_column=:time,
                method=:johansen,
                lags=2
            )

            result = fit(model, df)
            @test result isa CointegrationFitResult
            @test result.method == :johansen
            @test result.n_cointegrating_relations >= 1

            # 测试序列化
            payload = MetricaTimeSeries.result_to_payload(result)
            @test payload["model_type"] == "cointegration"
            @test payload["method"] == "johansen"
            @test haskey(payload, "eigenvalues")
            @test haskey(payload, "trace_stats")

            # 测试 include_augment
            payload_with_aug = MetricaTimeSeries.result_to_payload(result, include_augment=true)
            @test haskey(payload_with_aug, "augment_preview")
            payload_no_aug = MetricaTimeSeries.result_to_payload(result, include_augment=false)
            @test !haskey(payload_no_aug, "augment_preview")
        end

        @testset "Non-cointegrated Series" begin
            # 生成非协整序列（独立随机游走）
            n = 200
            x1 = cumsum(randn(n))
            x2 = cumsum(randn(n))

            df = DataFrame(time = 1:n, x1 = x1, x2 = x2)

            model = CointegrationModel(
                variables=[:x1, :x2],
                time_column=:time,
                method=:engle_granger
            )

            result = fit(model, df)
            @test result.n_cointegrating_relations == 0  # 不应检测到协整
        end
    end

    @testset "Forecast" begin
        Random.seed!(1234)

        @testset "ARIMA Forecast" begin
            # 生成 AR(1) 过程
            n = 200
            y = zeros(n)
            y[1] = randn()
            for t in 2:n
                y[t] = 0.5 * y[t-1] + randn()
            end

            df = DataFrame(time = 1:n, y = y)

            # 拟合 ARIMA(1,0,0)
            model = ARIMAModel(variable=:y, time_column=:time, order=(1, 0, 0), method=:css)
            result = fit(model, df)

            # 测试预测
            fc = forecast(result, steps=10, level=0.95)
            @test fc isa ForecastResult
            @test length(fc.point_forecast) == 10
            @test length(fc.lower_bound) == 10
            @test length(fc.upper_bound) == 10
            @test all(fc.lower_bound .<= fc.point_forecast)
            @test all(fc.point_forecast .<= fc.upper_bound)
            @test fc.confidence_level == 0.95
            @test fc.forecast_origin == n
            @test fc.steps == 10
        end

        @testset "VAR Forecast" begin
            # 生成 VAR(1) 过程
            n = 200
            A1 = [0.5 0.2; -0.1 0.3]
            y = zeros(n, 2)
            y[1, :] = randn(2)
            for t in 2:n
                y[t, :] = A1 * y[t-1, :] + randn(2)
            end

            df = DataFrame(time = 1:n, x1 = y[:, 1], x2 = y[:, 2])

            model = VARModel(variables=[:x1, :x2], time_column=:time, lags=1)
            result = fit(model, df)

            # 测试预测
            fcs = forecast(result, steps=10, level=0.95)
            @test length(fcs) == 2
            @test haskey(fcs, "x1")
            @test haskey(fcs, "x2")
            @test fcs["x1"] isa ForecastResult
            @test fcs["x2"] isa ForecastResult
        end

        @testset "ACF and PACF" begin
            # 生成 AR(1) 过程
            n = 200
            y = zeros(n)
            y[1] = randn()
            for t in 2:n
                y[t] = 0.5 * y[t-1] + randn()
            end

            # 测试 ACF
            acf_values = acf(y, max_lags=20)
            @test length(acf_values) == 21
            @test acf_values[1] ≈ 1.0
            @test abs(acf_values[2]) > 0.1  # AR(1) 应有显著的一阶自相关

            # 测试 PACF
            pacf_values = pacf(y, max_lags=20)
            @test length(pacf_values) == 21
            @test pacf_values[1] ≈ 1.0
            @test abs(pacf_values[2]) > 0.1  # AR(1) 应有显著的一阶偏自相关
            # AR(1) 的 PACF 在滞后 1 后应截尾
            for k in 3:20
                @test abs(pacf_values[k]) < 0.3  # 应该接近 0
            end
        end

        @testset "Ljung-Box Test" begin
            # 生成白噪声
            n = 200
            y = randn(n)

            # 白噪声不应拒绝无自相关的零假设
            lb = ljung_box_test(y, lags=10)
            @test lb.test_statistic > 0
            @test 0 <= lb.p_value <= 1
            @test lb.conclusion == "fail_to_reject"

            # 生成 AR(1) 过程
            y_ar = zeros(n)
            y_ar[1] = randn()
            for t in 2:n
                y_ar[t] = 0.8 * y_ar[t-1] + randn()
            end

            # AR(1) 的残差应拒绝无自相关的零假设
            lb_ar = ljung_box_test(y_ar, lags=10)
            @test lb_ar.conclusion == "reject"
        end
    end
end
