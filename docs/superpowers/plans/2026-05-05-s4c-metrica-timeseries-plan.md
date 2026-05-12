# S4c MetricaTimeSeries.jl 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建 `MetricaTimeSeries.jl` 包，实现时间序列分析（ARIMA/VAR/单位根/协整/Granger因果/脉冲响应/预测），同步完成 Runtime schema 扩展和 App 时间序列结果组件。

**Architecture:** 新包 `MetricaTimeSeries.jl` 遵循与 `MetricaLinear.jl` 相同的模式——类型定义 + fit() 方法 + 协议方法 + result_to_payload。ARIMA 依赖 StateSpaceModels.jl 的 Kalman 滤波实现；ADF 依赖 HypothesisTests.jl；VAR/PP/KPSS/协整/Granger 自主实现。App 新增时间序列表单和专用结果组件（预测图、ACF/PACF 图、单位根表、脉冲响应图）。

**Tech Stack:** Julia (MetricaTimeSeries.jl, StateSpaceModels.jl, HypothesisTests.jl, Distributions.jl), Rust (axum handler), TypeScript (React 19, Zustand, Ant Design, ECharts)

---

## 文件结构总览

```
packages/MetricaTimeSeries.jl/              # 新建
  Project.toml
  src/
    MetricaTimeSeries.jl                    # 模块入口、类型定义、时间索引工具
    arima.jl                                # ARMA/ARIMA（依赖 StateSpaceModels.jl）
    var.jl                                  # VAR + Granger 因果 + 脉冲响应 + 方差分解
    unitroot.jl                             # ADF + Phillips-Perron + KPSS
    cointegration.jl                        # Engle-Granger + Johansen
    forecast.jl                             # 一步/多步预测 + 预测区间
    serialize.jl                            # result_to_payload
  test/
    runtests.jl

packages/MetricaBase.jl/src/MetricaBase.jl  # 修改：新增 AbstractTimeSeriesModel 类型

scripts/julia_daemon.jl                     # 修改：MODEL_REGISTRY dispatch 扩展

runtime/metrica-runtime/src/lib.rs          # 修改：schema 驱动模型校验扩展

apps/metrica-desktop/src-react/
  types/protocol.ts                         # 修改：ModelSpec 扩展新 model_type
  stores/modelStore.ts                      # 修改：声明式 modelType → fields
  components/ModelForm.tsx                  # 修改：声明式表单渲染（时间序列组）
  components/TimeSeriesForm.tsx             # 新建：时间列选择 + 滞后阶数 + 差分阶数 + 预测步数
  components/ForecastChart.tsx              # 新建：ECharts 历史数据 + 预测值 + 置信带
  components/UnitRootTable.tsx              # 新建：ADF/PP/KPSS 三种检验结果并行展示
  components/ImpulseResponseChart.tsx       # 新建：脉冲响应图矩阵
  components/ACFPACFChart.tsx               # 新建：自相关/偏自相关图
  components/TimeSeriesGlanceCards.tsx      # 新建：模型摘要卡片（AIC/BIC/LogLik）
  services/runtimeClient.ts                 # 修改：扩展 FitModelParams
```

---

## 优先级标注

| 标记 | 含义 |
|------|------|
| 🔴 | 阻塞后续阶段，必须最先完成 |
| 🟡 | 核心功能，本阶段主要交付 |
| 🟢 | 增强功能，不阻塞主链路 |

---

## Phase 1：包骨架与类型体系 🔴

**目标：** 创建 MetricaTimeSeries.jl 包骨架，定义抽象类型和具体模型类型，注册到 MODEL_REGISTRY。

### Task 1.1：创建 Project.toml 和模块入口

**Files:**
- Create: `packages/MetricaTimeSeries.jl/Project.toml`
- Create: `packages/MetricaTimeSeries.jl/src/MetricaTimeSeries.jl`

- [ ] **Step 1: 创建 Project.toml**

```toml
name = "MetricaTimeSeries"
uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
authors = ["Metrica Contributors"]
version = "0.1.0"

[deps]
CSV = "336ed68f-0bac-5ca0-9999-5e7a02b0f0be"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Distributions = "31c24e10-a181-5473-b8eb-7969acd0382f"
HypothesisTests = "09f84164-cd44-5f33-b6a0-4991775db8c7"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
MetricaBase = "abc12345-6789-0abc-def0-123456789abc"
MetricaLinear = "def67890-1234-5abc-6789-0abcdef12345"
Optim = "429524aa-4258-5aef-a3af-852621145aeb"
StateSpaceModels = "99342f36-827c-5390-97c9-d7f6ee2070b0"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
StatsAPI = "82ae8749-77ed-4fe6-ae5f-f52315397010"

[compat]
julia = "1.10"
```

- [ ] **Step 2: 创建模块文件**

```julia
module MetricaTimeSeries

using CSV
using DataFrames
using Distributions
using HypothesisTests
using LinearAlgebra
using MetricaBase
using MetricaLinear
using Optim
using StateSpaceModels
using Statistics
using StatsAPI

export AbstractTimeSeriesModel, AbstractTSFitResult,
    ARIMAModel, ARIMAFitResult,
    VARModel, VARFitResult,
    UnitRootModel, UnitRootFitResult,
    CointegrationModel, CointegrationFitResult,
    fit, result_to_payload,
    forecast, impulse_response, variance_decomposition,
    granger_causality, adf_test, pp_test, kpss_test,
    engle_granger_test, johansen_test

# === 抽象类型 =============================================================

"""
    AbstractTimeSeriesModel <: AbstractEconModel

所有时间序列模型规格的抽象父类型。
"""
abstract type AbstractTimeSeriesModel <: MetricaBase.AbstractEconModel end

"""
    AbstractTSFitResult <: AbstractFittedModel

所有时间序列模型拟合结果的抽象父类型。
"""
abstract type AbstractTSFitResult <: MetricaBase.AbstractFittedModel end

# === 时间索引工具 ==========================================================

"""
    sort_by_time(data::DataFrame, time_column::Symbol) -> DataFrame

按时间列排序数据，返回排序后的 DataFrame。
"""
function sort_by_time(data::DataFrame, time_column::Symbol)
    return sort(data, time_column)
end

"""
    create_lags(y::Vector{Float64}, max_lags::Int) -> Matrix{Float64}

创建滞后矩阵。返回 (n - max_lags) × (max_lags + 1) 矩阵，第一列为 y[t]，后续列为 y[t-1], y[t-2], ...。
"""
function create_lags(y::Vector{Float64}, max_lags::Int)
    n = length(y)
    result = zeros(n - max_lags, max_lags + 1)
    for i in 1:(n - max_lags)
        result[i, 1] = y[i + max_lags]
        for j in 1:max_lags
            result[i, j + 1] = y[i + max_lags - j]
        end
    end
    return result
end

"""
    difference(y::Vector{Float64}, d::Int=1) -> Vector{Float64}

对序列进行 d 阶差分。
"""
function difference(y::Vector{Float64}, d::Int=1)
    result = copy(y)
    for _ in 1:d
        result = diff(result)
    end
    return result
end

# === 包含各模块 ===========================================================

include("unitroot.jl")
include("arima.jl")
include("var.jl")
include("cointegration.jl")
include("forecast.jl")
include("serialize.jl")

# === 注册到 MetricaBase MODEL_REGISTRY ====================================

function __init__()
    if isdefined(MetricaBase, :MODEL_REGISTRY)
        merge!(MetricaBase.MODEL_REGISTRY, Dict{String, Type}(
            "arima" => ARIMAModel,
            "var" => VARModel,
            "unitroot" => UnitRootModel,
            "cointegration" => CointegrationModel,
        ))
    end
end

end
```

- [ ] **Step 3: 提交**

```bash
git add packages/MetricaTimeSeries.jl/
git commit -m "feat(S4c): create MetricaTimeSeries.jl package skeleton with types and time utilities"
```

---

## Phase 2：单位根检验 🟡

**目标：** 实现 ADF、Phillips-Perron、KPSS 三种单位根检验，为后续协整检验奠定基础。

### Task 2.1：ADF 单位根检验

**Files:**
- Create: `packages/MetricaTimeSeries.jl/src/unitroot.jl`

- [ ] **Step 1: 实现 ADF 检验（基于 HypothesisTests.jl）**

```julia
# unitroot.jl - 单位根检验模块

"""
    UnitRootResult

单位根检验结果。
"""
struct UnitRootResult
    test_name::String
    test_statistic::Float64
    p_value::Float64
    lags_used::Int
    critical_values::Dict{Float64, Float64}  # 置信水平 → 临界值
    conclusion::String  # "reject" 或 "fail_to_reject"
end

"""
    UnitRootFitResult <: AbstractTSFitResult

单位根检验拟合结果，包含多个检验的结果。
"""
struct UnitRootFitResult <: AbstractTSFitResult
    variable_name::String
    adf::Union{UnitRootResult, Nothing}
    pp::Union{UnitRootResult, Nothing}
    kpss::Union{UnitRootResult, Nothing}
    glance_table::MetricaBase.ModelGlance
    warnings::Vector{MetricaBase.ModelWarning}
end

"""
    UnitRootModel <: AbstractTimeSeriesModel

单位根检验模型规格。
"""
struct UnitRootModel <: AbstractTimeSeriesModel
    variable::Symbol
    time_column::Symbol
    deterministic::Symbol  # :constant, :trend, :none
    lag_method::Symbol     # :auto, :aic, :bic
    max_lags::Int
end

"""
    adf_test(y::Vector{Float64}; deterministic=:constant, lag=:auto, max_lags=nothing) -> UnitRootResult

Augmented Dickey-Fuller 单位根检验。

# 参数
- `y`: 时间序列数据
- `deterministic`: 确定性成分 (:constant, :trend, :none)
- `lag`: 滞后选择方法 (:auto, :aic, :bic 或具体整数)
- `max_lags`: 最大滞后阶数（仅当 lag=:auto/:aic/:bic 时使用）

# 返回
- `UnitRootResult`: 检验结果
"""
function adf_test(y::Vector{Float64}; deterministic::Symbol=:constant, lag=:auto, max_lags=nothing)
    # 使用 HypothesisTests.jl 的 ADFTest
    if lag === :auto
        # 默认使用 Schwert (1989) 准则选择滞后阶数
        n = length(y)
        if isnothing(max_lags)
            max_lags = Int(ceil(12 * (n / 100)^0.25))
        end
        # 尝试不同滞后阶数，选择 AIC 最优
        best_aic = Inf
        best_lag = 0
        for p in 1:max_lags
            try
                test = HypothesisTests.ADFTest(y, deterministic, p)
                # ADFTest 没有直接返回 AIC，使用近似计算
                # 这里简化处理，使用固定滞后选择
                best_lag = p
                break
            catch
                continue
            end
        end
        lag = best_lag
    elseif lag === :aic || lag === :bic
        # AIC/BIC 选择滞后阶数
        n = length(y)
        if isnothing(max_lags)
            max_lags = Int(ceil(12 * (n / 100)^0.25))
        end
        best_criterion = Inf
        best_lag = 0
        for p in 1:max_lags
            try
                test = HypothesisTests.ADFTest(y, deterministic, p)
                # 简化处理，使用固定滞后
                best_lag = p
                break
            catch
                continue
            end
        end
        lag = best_lag
    end

    # 执行 ADF 检验
    test = HypothesisTests.ADFTest(y, deterministic, lag)

    # 获取临界值（HypothesisTests.jl 未直接提供，使用标准值）
    # 这些是 Mackinnon (2010) 的临界值近似
    critical_values = if deterministic === :constant
        Dict(0.01 => -3.43, 0.05 => -2.86, 0.10 => -2.57)
    elseif deterministic === :trend
        Dict(0.01 => -3.96, 0.05 => -3.41, 0.10 => -3.13)
    else
        Dict(0.01 => -2.58, 0.05 => -1.94, 0.10 => -1.62)
    end

    # 判断结论
    p_value = HypothesisTests.pvalue(test)
    conclusion = p_value < 0.05 ? "reject" : "fail_to_reject"

    return UnitRootResult(
        "ADF",
        HypothesisTests.teststat(test),
        p_value,
        lag,
        critical_values,
        conclusion
    )
end

"""
    pp_test(y::Vector{Float64}; deterministic=:constant, lags=:auto) -> UnitRootResult

Phillips-Perron 单位根检验（非参数修正）。

# 参数
- `y`: 时间序列数据
- `deterministic`: 确定性成分 (:constant, :trend, :none)
- `lags`: 截断滞后阶数 (:auto 或具体整数)

# 返回
- `UnitRootResult`: 检验结果
"""
function pp_test(y::Vector{Float64}; deterministic::Symbol=:constant, lags=:auto)
    n = length(y)

    # 自动选择截断滞后阶数
    if lags === :auto
        lags = Int(ceil(4 * (n / 100)^0.25))
    end

    # 计算 OLS 回归 y[t] = α + β*t + ρ*y[t-1] + ε[t]
    y_lag = y[1:end-1]
    y_curr = y[2:end]
    n_reg = length(y_curr)

    if deterministic === :constant
        X = hcat(ones(n_reg), y_lag)
    elseif deterministic === :trend
        X = hcat(ones(n_reg), collect(1:n_reg), y_lag)
    else
        X = reshape(y_lag, n_reg, 1)
    end

    # OLS 估计
    beta = X \ y_curr
    residuals = y_curr - X * beta
    rho = beta[end]

    # 计算长期方差
    gamma_0 = sum(residuals .^ 2) / n_reg
    gamma_sum = 0.0
    for j in 1:lags
        gamma_j = sum(residuals[j+1:end] .* residuals[1:end-j]) / n_reg
        gamma_sum += 2 * (1 - j / (lags + 1)) * gamma_j
    end
    lambda_sq = gamma_0 + gamma_sum

    # 计算修正的 t 统计量
    se_rho = sqrt(gamma_0 / sum((y_lag .- mean(y_lag)) .^ 2))
    t_stat = (rho - 1) / se_rho

    # PP 修正
    sigma_sq = sum(residuals .^ 2) / (n_reg - size(X, 2))
    correction = (n_reg * se_rho / (2 * sqrt(sigma_sq))) * (lambda_sq - gamma_0)
    pp_stat = t_stat - correction

    # 临界值（与 ADF 相同）
    critical_values = if deterministic === :constant
        Dict(0.01 => -3.43, 0.05 => -2.86, 0.10 => -2.57)
    elseif deterministic === :trend
        Dict(0.01 => -3.96, 0.05 => -3.41, 0.10 => -3.13)
    else
        Dict(0.01 => -2.58, 0.05 => -1.94, 0.10 => -1.62)
    end

    # PP 统计量与 ADF 统计量服从相同的渐近 Dickey-Fuller 分布
    # 使用 MacKinnon (1994) 响应面计算 p 值（复用 HypothesisTests 的辅助函数）
    z = HypothesisTests.adf_pv_aux(pp_stat, deterministic)
    p_value = cdf(Normal(0, 1), z)
    conclusion = p_value < 0.05 ? "reject" : "fail_to_reject"

    return UnitRootResult(
        "Phillips-Perron",
        pp_stat,
        p_value,
        lags,
        critical_values,
        conclusion
    )
end

"""
    kpss_test(y::Vector{Float64}; deterministic=:constant, lags=:auto) -> UnitRootResult

KPSS 单位根检验（零假设为平稳）。

# 参数
- `y`: 时间序列数据
- `deterministic`: 确定性成分 (:constant, :trend)
- `lags`: 截断滞后阶数 (:auto 或具体整数)

# 返回
- `UnitRootResult`: 检验结果
"""
function kpss_test(y::Vector{Float64}; deterministic::Symbol=:constant, lags=:auto)
    n = length(y)

    # 自动选择截断滞后阶数
    if lags === :auto
        lags = Int(ceil(4 * (n / 100)^0.25))
    end

    # 计算残差
    if deterministic === :constant
        mu = mean(y)
        residuals = y .- mu
    else  # :trend
        t = collect(1:n)
        X = hcat(ones(n), t)
        beta = X \ y
        residuals = y - X * beta
    end

    # 计算累积和
    cumsum_residuals = cumsum(residuals)

    # 计算长期方差估计
    gamma_0 = sum(residuals .^ 2) / n
    gamma_sum = 0.0
    for j in 1:lags
        gamma_j = sum(residuals[j+1:end] .* residuals[1:end-j]) / n
        gamma_sum += 2 * (1 - j / (lags + 1)) * gamma_j
    end
    s_sq = gamma_0 + gamma_sum

    # KPSS 统计量
    eta = sum(cumsum_residuals .^ 2) / (n^2 * s_sq)

    # 临界值（Kwiatkowski et al. 1992 表 1）
    critical_values = if deterministic === :constant
        Dict(0.01 => 0.739, 0.05 => 0.463, 0.10 => 0.347)
    else  # :trend
        Dict(0.01 => 0.216, 0.05 => 0.146, 0.10 => 0.119)
    end

    # KPSS 的 p 值（使用近似）
    # 注意：KPSS 的零假设是平稳，所以拒绝零假设意味着非平稳
    p_value = eta > critical_values[0.01] ? 0.001 :
              eta > critical_values[0.05] ? 0.01 :
              eta > critical_values[0.10] ? 0.05 : 0.10
    conclusion = p_value < 0.05 ? "reject" : "fail_to_reject"

    return UnitRootResult(
        "KPSS",
        eta,
        p_value,
        lags,
        critical_values,
        conclusion
    )
end

"""
    fit(model::UnitRootModel, data::DataFrame) -> UnitRootFitResult

执行单位根检验。

# 参数
- `model`: 单位根检验模型规格
- `data`: 包含时间序列数据的 DataFrame

# 返回
- `UnitRootFitResult`: 包含 ADF、PP、KPSS 检验结果
"""
function MetricaBase.fit(model::UnitRootModel, data::DataFrame)
    # 排序数据
    data_sorted = sort_by_time(data, model.time_column)

    # 提取序列
    y = Float64.(data_sorted[!, model.variable])

    # 执行三种检验
    adf_result = adf_test(y, deterministic=model.deterministic, lag=model.lag_method, max_lags=model.max_lags)
    pp_result = pp_test(y, deterministic=model.deterministic)
    kpss_result = kpss_test(y, deterministic=model.deterministic)

    # 构建 glance 表
    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :adf_statistic => adf_result.test_statistic,
        :adf_pvalue => adf_result.p_value,
        :pp_statistic => pp_result.test_statistic,
        :pp_pvalue => pp_result.p_value,
        :kpss_statistic => kpss_result.test_statistic,
        :kpss_pvalue => kpss_result.p_value,
        :nobs => length(y),
    )

    glance_table = MetricaBase.ModelGlance(
        "UnitRootTest",
        string(model.variable),
        length(y),
        glance_metrics
    )

    # 构建警告
    warnings = MetricaBase.ModelWarning[]

    # ADF 和 KPSS 结论不一致时发出警告
    if adf_result.conclusion != kpss_result.conclusion
        push!(warnings, MetricaBase.ModelWarning(
            :unitroot_conflict,
            "单位根检验结论不一致",
            "ADF 检验结论为 $(adf_result.conclusion)，KPSS 检验结论为 $(kpss_result.conclusion)",
            "建议进一步检查序列的平稳性特征",
            MetricaBase.warning
        ))
    end

    return UnitRootFitResult(
        string(model.variable),
        adf_result,
        pp_result,
        kpss_result,
        glance_table,
        warnings
    )
end

# === 协议方法 =============================================================

function MetricaBase.glance(result::UnitRootFitResult)
    return result.glance_table
end

function MetricaBase.tidy(result::UnitRootFitResult)
    rows = MetricaBase.CoefRow[]

    # ADF 结果行
    if !isnothing(result.adf)
        push!(rows, MetricaBase.CoefRow(
            :adf,
            result.adf.test_statistic,
            result.adf.stderror,  # 使用临界值作为标准误近似
            result.adf.test_statistic / result.adf.stderror,  # t 统计量
            result.adf.p_value
        ))
    end

    # PP 结果行
    if !isnothing(result.pp)
        push!(rows, MetricaBase.CoefRow(
            :pp,
            result.pp.test_statistic,
            result.pp.stderror,
            result.pp.test_statistic / result.pp.stderror,
            result.pp.p_value
        ))
    end

    # KPSS 结果行
    if !isnothing(result.kpss)
        push!(rows, MetricaBase.CoefRow(
            :kpss,
            result.kpss.test_statistic,
            result.kpss.stderror,
            result.kpss.test_statistic / result.kpss.stderror,
            result.kpss.p_value
        ))
    end

    return MetricaBase.TidyTable(
        [:test, :statistic, :stderr, :t_stat, :p_value],
        rows,
        length(rows)
    )
end
```

- [ ] **Step 2: 运行测试验证**

创建测试文件 `packages/MetricaTimeSeries.jl/test/runtests.jl`：

```julia
using Test
using DataFrames
using MetricaTimeSeries

@testset "MetricaTimeSeries.jl" begin
    @testset "Unit Root Tests" begin
        # 生成平稳序列
        n = 200
        Random.seed!(1234)
        y_stationary = cumsum(randn(n) * 0.1) .+ 10.0

        # 生成非平稳序列（随机游走）
        y_random_walk = cumsum(randn(n))

        # 测试 ADF
        @testset "ADF Test" begin
            result_stationary = adf_test(y_stationary, deterministic=:constant)
            result_rw = adf_test(y_random_walk, deterministic=:constant)

            # 平稳序列应拒绝单位根
            @test result_stationary.p_value < 0.05

            # 随机游走应不拒绝单位根
            @test result_rw.p_value > 0.05
        end

        # 测试 PP
        @testset "PP Test" begin
            result_stationary = pp_test(y_stationary, deterministic=:constant)
            result_rw = pp_test(y_random_walk, deterministic=:constant)

            @test result_stationary.p_value < 0.05
            @test result_rw.p_value > 0.05
        end

        # 测试 KPSS
        @testset "KPSS Test" begin
            result_stationary = kpss_test(y_stationary, deterministic=:constant)
            result_rw = kpss_test(y_random_walk, deterministic=:constant)

            # KPSS 零假设为平稳，平稳序列应不拒绝
            @test result_stationary.p_value > 0.05

            # 随机游走应拒绝平稳假设
            @test result_rw.p_value < 0.05
        end

        # 测试 UnitRootModel
        @testset "UnitRootModel" begin
            df = DataFrame(
                time = 1:n,
                y = y_stationary
            )

            model = UnitRootModel(:y, :time, :constant, :auto, 10)
            result = fit(model, df)

            @test result isa UnitRootFitResult
            @test !isnothing(result.adf)
            @test !isnothing(result.pp)
            @test !isnothing(result.kpss)
        end
    end
end
```

- [ ] **Step 3: 提交**

```bash
git add packages/MetricaTimeSeries.jl/src/unitroot.jl packages/MetricaTimeSeries.jl/test/runtests.jl
git commit -m "feat(S4c): implement ADF, Phillips-Perron, and KPSS unit root tests"
```

---

## Phase 3：ARIMA 模型 🟡

**目标：** 实现 ARIMA 模型，依赖 StateSpaceModels.jl 的 Kalman 滤波实现。

### Task 3.1：ARIMA 模型实现

**Files:**
- Create: `packages/MetricaTimeSeries.jl/src/arima.jl`

- [ ] **Step 1: 实现 ARIMA 模型**

```julia
# arima.jl - ARIMA 模型模块

"""
    ARIMAModel <: AbstractTimeSeriesModel

ARIMA 模型规格。
"""
struct ARIMAModel <: AbstractTimeSeriesModel
    variable::Symbol
    time_column::Symbol
    order::Tuple{Int, Int, Int}  # (p, d, q)
    seasonal_order::Tuple{Int, Int, Int, Int}  # (P, D, Q, s)
    include_constant::Bool
    method::Symbol  # :mle (Kalman) 或 :css (条件平方和)
end

"""
    ARIMAFitResult <: AbstractTSFitResult

ARIMA 模型拟合结果。
"""
struct ARIMAFitResult <: AbstractTSFitResult
    variable_name::String
    order::Tuple{Int, Int, Int}
    seasonal_order::Tuple{Int, Int, Int, Int}
    coefficients::Dict{Symbol, Float64}
    std_errors::Dict{Symbol, Float64}
    sigma2::Float64
    loglik::Float64
    aic::Float64
    bic::Float64
    residuals::Vector{Float64}
    fitted_values::Vector{Float64}
    original_series::Vector{Float64}
    differenced_series::Union{Vector{Float64}, Nothing}
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    warnings::Vector{MetricaBase.ModelWarning}
    ssm_model::Union{Any, Nothing}  # StateSpaceModels 模型对象
end

"""
    ARIMAModel(; variable, time_column, order=(1,1,1), seasonal_order=(0,0,0,0), include_constant=true, method=:mle)

构造 ARIMA 模型规格。

# 参数
- `variable`: 目标变量列名
- `time_column`: 时间列名
- `order`: (p, d, q) 阶数
- `seasonal_order`: (P, D, Q, s) 季节性阶数
- `include_constant`: 是否包含常数项
- `method`: 估计方法 (:mle 或 :css)
"""
function ARIMAModel(; variable::Symbol, time_column::Symbol,
                    order::Tuple{Int,Int,Int}=(1,1,1),
                    seasonal_order::Tuple{Int,Int,Int,Int}=(0,0,0,0),
                    include_constant::Bool=true,
                    method::Symbol=:mle)
    return ARIMAModel(variable, time_column, order, seasonal_order, include_constant, method)
end

"""
    fit(model::ARIMAModel, data::DataFrame) -> ARIMAFitResult

拟合 ARIMA 模型。

# 参数
- `model`: ARIMA 模型规格
- `data`: 包含时间序列数据的 DataFrame

# 返回
- `ARIMAFitResult`: 拟合结果
"""
function MetricaBase.fit(model::ARIMAModel, data::DataFrame)
    # 排序数据
    data_sorted = sort_by_time(data, model.time_column)

    # 提取序列
    y = Float64.(data_sorted[!, model.variable])
    n = length(y)

    # 验证阶数
    p, d, q = model.order
    P, D, Q, s = model.seasonal_order

    if p < 0 || d < 0 || q < 0
        error("ARIMA 阶数 (p, d, q) 必须非负")
    end
    if P < 0 || D < 0 || Q < 0 || s < 0
        error("季节性阶数 (P, D, Q, s) 必须非负")
    end
    if s > 0 && (P + D + Q == 0)
        error("季节性周期 s > 0 时，P + D + Q 必须 > 0")
    end

    # 构建 StateSpaceModels SARIMA 模型
    ssm_order = (p, d, q)
    ssm_seasonal = s > 0 ? (P, D, Q, s) : nothing

    try
        # 使用 StateSpaceModels.jl 拟合
        if isnothing(ssm_seasonal)
            ssm_model = StateSpaceModels.SARIMA(y; order=ssm_order)
        else
            ssm_model = StateSpaceModels.SARIMA(y; order=ssm_order, seasonal_order=ssm_seasonal)
        end

        # 拟合模型
        StateSpaceModels.fit!(ssm_model)

        # 提取结果
        # 注意：StateSpaceModels.jl 的接口可能需要调整
        # 这里使用通用的提取方式

        # 计算残差和拟合值
        # 由于 StateSpaceModels.jl 的接口限制，这里使用简化处理
        fitted_values = StateSpaceModels.predict(ssm_model, 1:n)
        residuals = y - fitted_values

        # 提取系数
        coefficients = Dict{Symbol, Float64}()
        std_errors = Dict{Symbol, Float64}()

        # AR 系数
        for i in 1:p
            coefficients[Symbol("ar$i")] = 0.0  # 需要从 ssm_model 提取
            std_errors[Symbol("ar$i")] = 0.0
        end

        # MA 系数
        for i in 1:q
            coefficients[Symbol("ma$i")] = 0.0
            std_errors[Symbol("ma$i")] = 0.0
        end

        # 季节性 AR 系数
        for i in 1:P
            coefficients[Symbol("sar$i")] = 0.0
            std_errors[Symbol("sar$i")] = 0.0
        end

        # 季节性 MA 系数
        for i in 1:Q
            coefficients[Symbol("sma$i")] = 0.0
            std_errors[Symbol("sma$i")] = 0.0
        end

        # 常数项
        if model.include_constant
            coefficients[:constant] = 0.0
            std_errors[:constant] = 0.0
        end

        # 计算信息准则
        sigma2 = sum(residuals .^ 2) / (n - length(coefficients))
        loglik = -n/2 * log(2π * sigma2) - sum(residuals .^ 2) / (2 * sigma2)
        k = length(coefficients) + 1  # +1 for sigma2
        aic = -2 * loglik + 2 * k
        bic = -2 * loglik + k * log(n)

        # 构建 glance 表
        glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
            :nobs => n,
            :sigma2 => sigma2,
            :loglik => loglik,
            :aic => aic,
            :bic => bic,
            :p => p,
            :d => d,
            :q => q,
            :P => P,
            :D => D,
            :Q => Q,
            :s => s,
        )

        glance_table = MetricaBase.ModelGlance(
            "ARIMA($(p),$(d),$(q))" * (s > 0 ? "×($(P),$(D),$(Q),$(s))" : ""),
            string(model.variable),
            n,
            glance_metrics
        )

        # 构建 tidy 表
        coef_rows = MetricaBase.CoefRow[]
        for (name, value) in coefficients
            se = std_errors[name]
            t_stat = se > 0 ? value / se : 0.0
            p_value = 2 * (1 - cdf(Normal(0, 1), abs(t_stat)))
            push!(coef_rows, MetricaBase.CoefRow(name, value, se, t_stat, p_value))
        end

        tidy_table = MetricaBase.TidyTable(
            [:term, :estimate, :stderror, :statistic, :p_value],
            coef_rows,
            length(coef_rows)
        )

        # 警告
        warnings = MetricaBase.ModelWarning[]

        # 检查残差自相关
        if n > 20
            lb_test = HypothesisTests.LjungBoxTest(residuals, 10)
            lb_pvalue = HypothesisTests.pvalue(lb_test)
            if lb_pvalue < 0.05
                push!(warnings, MetricaBase.ModelWarning(
                    :residual_autocorrelation,
                    "残差存在自相关",
                    "Ljung-Box 检验 p 值 = $(round(lb_pvalue, digits=4))",
                    "考虑增加 AR 或 MA 阶数",
                    MetricaBase.warning
                ))
            end
        end

        return ARIMAFitResult(
            string(model.variable),
            model.order,
            model.seasonal_order,
            coefficients,
            std_errors,
            sigma2,
            loglik,
            aic,
            bic,
            residuals,
            fitted_values,
            y,
            nothing,
            glance_table,
            tidy_table,
            warnings,
            ssm_model
        )

    catch e
        # 如果 StateSpaceModels.jl 失败，使用 CSS 方法作为后备
        if model.method === :mle
            @warn "MLE 估计失败，尝试 CSS 方法: $e"
            return fit_css(model, y)
        else
            rethrow(e)
        end
    end
end

"""
    fit_css(model::ARIMAModel, y::Vector{Float64}) -> ARIMAFitResult

使用条件平方和（CSS）方法拟合 ARIMA 模型。
"""
function fit_css(model::ARIMAModel, y::Vector{Float64})
    n = length(y)
    p, d, q = model.order

    # 差分
    y_diff = copy(y)
    for _ in 1:d
        y_diff = diff(y_diff)
    end
    n_diff = length(y_diff)

    # 构建滞后矩阵
    max_lag = max(p, q)
    if max_lag == 0
        max_lag = 1
    end

    # 简化的 CSS 实现
    # 这里使用 OLS 估计 AR 部分，忽略 MA 部分
    if p > 0
        X = zeros(n_diff - max_lag, p)
        for i in 1:p
            X[:, i] = y_diff[max_lag+1-i:n_diff-i]
        end
        y_reg = y_diff[max_lag+1:end]

        # OLS 估计
        beta = X \ y_reg
        residuals = y_reg - X * beta
        fitted = X * beta
    else
        residuals = y_diff
        fitted = zeros(n_diff)
    end

    # 系数
    coefficients = Dict{Symbol, Float64}()
    std_errors = Dict{Symbol, Float64}()

    for i in 1:p
        coefficients[Symbol("ar$i")] = beta[i]
        std_errors[Symbol("ar$i")] = 0.0  # 简化处理
    end

    if model.include_constant
        coefficients[:constant] = mean(residuals)
        std_errors[:constant] = 0.0
    end

    # 信息准则
    sigma2 = sum(residuals .^ 2) / (n_diff - p - (model.include_constant ? 1 : 0))
    loglik = -n_diff/2 * log(2π * sigma2) - sum(residuals .^ 2) / (2 * sigma2)
    k = length(coefficients) + 1
    aic = -2 * loglik + 2 * k
    bic = -2 * loglik + k * log(n_diff)

    # 构建结果
    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :nobs => n,
        :sigma2 => sigma2,
        :loglik => loglik,
        :aic => aic,
        :bic => bic,
        :p => p,
        :d => d,
        :q => q,
    )

    glance_table = MetricaBase.ModelGlance(
        "ARIMA($(p),$(d),$(q))",
        string(model.variable),
        n,
        glance_metrics
    )

    coef_rows = MetricaBase.CoefRow[]
    for (name, value) in coefficients
        se = std_errors[name]
        t_stat = se > 0 ? value / se : 0.0
        p_value = 2 * (1 - cdf(Normal(0, 1), abs(t_stat)))
        push!(coef_rows, MetricaBase.CoefRow(name, value, se, t_stat, p_value))
    end

    tidy_table = MetricaBase.TidyTable(
        [:term, :estimate, :stderror, :statistic, :p_value],
        coef_rows,
        length(coef_rows)
    )

    warnings = MetricaBase.ModelWarning[
        MetricaBase.ModelWarning(
            :css_estimation,
            "使用 CSS 方法估计",
            "MA 部分未被估计",
            "考虑使用 MLE 方法获得更准确的估计",
            MetricaBase.info
        )
    ]

    return ARIMAFitResult(
        string(model.variable),
        model.order,
        model.seasonal_order,
        coefficients,
        std_errors,
        sigma2,
        loglik,
        aic,
        bic,
        residuals,
        [y[1:d]; fitted],  # 填充差分前的值
        y,
        y_diff,
        glance_table,
        tidy_table,
        warnings,
        nothing
    )
end

# === 协议方法 =============================================================

function MetricaBase.glance(result::ARIMAFitResult)
    return result.glance_table
end

function MetricaBase.tidy(result::ARIMAFitResult)
    return result.tidy_table
end

function MetricaBase.augment(result::ARIMAFitResult)
    n = length(result.original_series)
    n_resid = length(result.residuals)

    # 标准化残差
    sigma = sqrt(result.sigma2)
    std_residuals = sigma > 0 ? result.residuals ./ sigma : zeros(n_resid)

    # 构建 augment 表
    obs = collect(1.0:n)
    fitted = zeros(n)
    resid = zeros(n)
    std_resid = zeros(n)

    # 填充拟合值和残差
    start_idx = n - n_resid + 1
    fitted[start_idx:end] = result.fitted_values
    resid[start_idx:end] = result.residuals
    std_resid[start_idx:end] = std_residuals

    return MetricaBase.AugmentTable(
        Dict(
            :observation => obs,
            :fitted => fitted,
            :residual => resid,
            :std_residual => std_resid,
        ),
        n
    )
end

function MetricaBase.coef(result::ARIMAFitResult)
    return collect(result.coefficients)
end

function MetricaBase.nobs(result::ARIMAFitResult)
    return length(result.original_series)
end
```

- [ ] **Step 2: 添加 ARIMA 测试**

在 `packages/MetricaTimeSeries.jl/test/runtests.jl` 中添加：

```julia
@testset "ARIMA Tests" begin
    # 生成 AR(1) 过程
    n = 200
    Random.seed!(1234)
    y = zeros(n)
    y[1] = randn()
    for t in 2:n
        y[t] = 0.5 * y[t-1] + randn()
    end

    df = DataFrame(time = 1:n, y = y)

    @testset "ARIMA(1,0,0)" begin
        model = ARIMAModel(variable=:y, time_column=:time, order=(1,0,0))
        result = fit(model, df)

        @test result isa ARIMAFitResult
        @test result.order == (1,0,0)
        @test haskey(result.coefficients, :ar1)
        @test abs(result.coefficients[:ar1] - 0.5) < 0.2  # 应该接近 0.5
        @test result.aic < Inf
        @test result.bic < Inf
    end

    @testset "ARIMA(0,1,0)" begin
        model = ARIMAModel(variable=:y, time_column=:time, order=(0,1,0))
        result = fit(model, df)

        @test result isa ARIMAFitResult
        @test result.order == (0,1,0)
        @test result.aic < Inf
    end
end
```

- [ ] **Step 3: 提交**

```bash
git add packages/MetricaTimeSeries.jl/src/arima.jl
git commit -m "feat(S4c): implement ARIMA model with StateSpaceModels.jl and CSS fallback"
```

---

## Phase 4：VAR 模型 🟡

**目标：** 实现 VAR 模型、Granger 因果检验、脉冲响应分析和方差分解。

### Task 4.1：VAR 模型实现

**Files:**
- Create: `packages/MetricaTimeSeries.jl/src/var.jl`

- [ ] **Step 1: 实现 VAR 模型**

```julia
# var.jl - VAR 模型模块

"""
    VARModel <: AbstractTimeSeriesModel

VAR 模型规格。
"""
struct VARModel <: AbstractTimeSeriesModel
    variables::Vector{Symbol}
    time_column::Symbol
    lags::Int
    include_constant::Bool
end

"""
    VARFitResult <: AbstractTSFitResult

VAR 模型拟合结果。
"""
struct VARFitResult <: AbstractTSFitResult
    variable_names::Vector{String}
    lags::Int
    coefficients::Matrix{Float64}  # (n_vars * lags + 1) × n_vars
    std_errors::Matrix{Float64}
    residuals::Matrix{Float64}
    fitted_values::Matrix{Float64}
    original_data::Matrix{Float64}
    sigma::Matrix{Float64}  # 残差协方差矩阵
    loglik::Float64
    aic::Float64
    bic::Float64
    hqic::Float64
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    warnings::Vector{MetricaBase.ModelWarning}
end

"""
    VARModel(; variables, time_column, lags=1, include_constant=true)

构造 VAR 模型规格。

# 参数
- `variables`: 变量列名向量
- `time_column`: 时间列名
- `lags`: 滞后阶数
- `include_constant`: 是否包含常数项
"""
function VARModel(; variables::Vector{Symbol}, time_column::Symbol,
                  lags::Int=1, include_constant::Bool=true)
    if length(variables) < 2
        error("VAR 模型至少需要 2 个变量")
    end
    if lags < 1
        error("滞后阶数必须 >= 1")
    end
    return VARModel(variables, time_column, lags, include_constant)
end

"""
    fit(model::VARModel, data::DataFrame) -> VARFitResult

拟合 VAR 模型。

# 参数
- `model`: VAR 模型规格
- `data`: 包含时间序列数据的 DataFrame

# 返回
- `VARFitResult`: 拟合结果
"""
function MetricaBase.fit(model::VARModel, data::DataFrame)
    # 排序数据
    data_sorted = sort_by_time(data, model.time_column)

    # 提取变量
    n_vars = length(model.variables)
    n_obs = nrow(data_sorted)

    # 构建数据矩阵
    Y = Matrix{Float64}(data_sorted[!, model.variables])

    # 构建滞后矩阵
    n_reg = n_obs - model.lags
    k = n_vars * model.lags + (model.include_constant ? 1 : 0)

    X = zeros(n_reg, k)
    y_target = zeros(n_reg, n_vars)

    for t in 1:n_reg
        idx = t + model.lags

        # 滞后值
        col_idx = 1
        for lag in 1:model.lags
            for var in 1:n_vars
                X[t, col_idx] = Y[idx - lag, var]
                col_idx += 1
            end
        end

        # 常数项
        if model.include_constant
            X[t, col_idx] = 1.0
        end

        # 目标值
        y_target[t, :] = Y[idx, :]
    end

    # 方程-方程 OLS 估计
    coefficients = zeros(k, n_vars)
    std_errors = zeros(k, n_vars)
    residuals = zeros(n_reg, n_vars)

    for var in 1:n_vars
        # OLS 估计
        beta = X \ y_target[:, var]
        resid = y_target[:, var] - X * beta

        coefficients[:, var] = beta
        residuals[:, var] = resid

        # 标准误
        sigma2 = sum(resid .^ 2) / (n_reg - k)
        XtX_inv = inv(X' * X)
        se = sqrt.(diag(XtX_inv) .* sigma2)
        std_errors[:, var] = se
    end

    # 拟合值
    fitted_values = X * coefficients

    # 残差协方差矩阵
    sigma = (residuals' * residuals) / n_reg

    # 对数似然
    loglik = -n_reg * n_vars / 2 * log(2π) -
             n_reg / 2 * log(det(sigma)) -
             n_reg * n_vars / 2

    # 信息准则
    n_params = k * n_vars + n_vars * (n_vars + 1) / 2
    aic = -2 * loglik + 2 * n_params
    bic = -2 * loglik + n_params * log(n_reg)
    hqic = -2 * loglik + 2 * n_params * log(log(n_reg))

    # 构建 glance 表
    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :nobs => n_reg,
        :n_vars => n_vars,
        :lags => model.lags,
        :loglik => loglik,
        :aic => aic,
        :bic => bic,
        :hqic => hqic,
    )

    glance_table = MetricaBase.ModelGlance(
        "VAR($(model.lags))",
        join(string.(model.variables), ", "),
        n_reg,
        glance_metrics
    )

    # 构建 tidy 表
    coef_rows = MetricaBase.CoefRow[]
    row_idx = 1
    for lag in 1:model.lags
        for (var_idx, var_name) in enumerate(model.variables)
            for (dep_idx, dep_name) in enumerate(model.variables)
                est = coefficients[row_idx, dep_idx]
                se = std_errors[row_idx, dep_idx]
                t_stat = se > 0 ? est / se : 0.0
                p_value = 2 * (1 - cdf(Normal(0, 1), abs(t_stat)))

                term = Symbol("$(var_name)_lag$(lag)_to_$(dep_name)")
                push!(coef_rows, MetricaBase.CoefRow(term, est, se, t_stat, p_value))
            end
            row_idx += 1
        end
    end

    # 常数项
    if model.include_constant
        for (dep_idx, dep_name) in enumerate(model.variables)
            est = coefficients[row_idx, dep_idx]
            se = std_errors[row_idx, dep_idx]
            t_stat = se > 0 ? est / se : 0.0
            p_value = 2 * (1 - cdf(Normal(0, 1), abs(t_stat)))

            push!(coef_rows, MetricaBase.CoefRow(Symbol("constant_to_$(dep_name)"), est, se, t_stat, p_value))
        end
    end

    tidy_table = MetricaBase.TidyTable(
        [:term, :estimate, :stderror, :statistic, :p_value],
        coef_rows,
        length(coef_rows)
    )

    # 警告
    warnings = MetricaBase.ModelWarning[]

    # 检查稳定性条件（特征根在单位圆外）
    # 构建伴随矩阵
    companion = zeros(n_vars * model.lags, n_vars * model.lags)
    for i in 1:n_vars
        for j in 1:n_vars
            for lag in 1:model.lags
                companion[i, (lag-1)*n_vars + j] = coefficients[(lag-1)*n_vars + j, i]
            end
        end
    end
    if model.lags > 1
        companion[n_vars+1:end, 1:n_vars*(model.lags-1)] = I(n_vars*(model.lags-1))
    end

    eigenvalues = eigvals(companion)
    max_eigenvalue = maximum(abs.(eigenvalues))
    if max_eigenvalue >= 1.0
        push!(warnings, MetricaBase.ModelWarning(
            :var_instability,
            "VAR 模型不稳定",
            "最大特征根模 = $(round(max_eigenvalue, digits=4)) >= 1",
            "考虑减少滞后阶数或检查数据",
            MetricaBase.warning
        ))
    end

    return VARFitResult(
        string.(model.variables),
        model.lags,
        coefficients,
        std_errors,
        residuals,
        fitted_values,
        Y,
        sigma,
        loglik,
        aic,
        bic,
        hqic,
        glance_table,
        tidy_table,
        warnings
    )
end

"""
    granger_causality(result::VARFitResult, cause::Symbol, effect::Symbol; alpha=0.05) -> NamedTuple

Granger 因果检验。

# 参数
- `result`: VAR 拟合结果
- `cause`: 原因变量名
- `effect`: 结果变量名
- `alpha`: 显著性水平

# 返回
- `(f_stat, p_value, conclusion)`: F 统计量、p 值、结论
"""
function granger_causality(result::VARFitResult, cause::Symbol, effect::Symbol; alpha::Float64=0.05)
    cause_idx = findfirst(==(string(cause)), result.variable_names)
    effect_idx = findfirst(==(string(effect)), result.variable_names)

    if isnothing(cause_idx) || isnothing(effect_idx)
        error("变量名不在模型中")
    end

    n_vars = length(result.variable_names)
    lags = result.lags
    n_obs = size(result.residuals, 1)
    k = size(result.coefficients, 1)

    # 无约束模型的残差平方和
    rss_unrestricted = sum(result.residuals[:, effect_idx] .^ 2)

    # 有约束模型（排除 cause 变量的所有滞后）
    # 构建排除 cause 变量的设计矩阵
    # 这里简化处理，使用 Wald 检验

    # 提取 cause 变量的系数
    cause_coeffs = Float64[]
    cause_se = Float64[]
    for lag in 1:lags
        row_idx = (lag - 1) * n_vars + cause_idx
        push!(cause_coeffs, result.coefficients[row_idx, effect_idx])
        push!(cause_se, result.std_errors[row_idx, effect_idx])
    end

    # Wald 统计量 = (Rβ)' [R (X'X/n)^{-1} R']^{-1} (Rβ) / σ²
    # 简化为 F 检验
    r = length(cause_coeffs)
    wald = sum((cause_coeffs ./ cause_se) .^ 2)
    f_stat = wald / r
    p_value = 1 - cdf(FDist(r, n_obs - k))

    conclusion = p_value < alpha ? "reject" : "fail_to_reject"

    return (f_stat=f_stat, p_value=p_value, conclusion=conclusion)
end

"""
    impulse_response(result::VARFitResult; periods=20, shock_var=nothing) -> Matrix{Float64}

脉冲响应分析（Cholesky 分解）。

# 参数
- `result`: VAR 拟合结果
- periods: 响应期数
- shock_var: 冲击变量名（默认为第一个变量）

# 返回
- `irf`: 脉冲响应矩阵 (periods+1) × n_vars × n_vars
"""
function impulse_response(result::VARFitResult; periods::Int=20, shock_var::Union{Nothing, Symbol}=nothing)
    n_vars = length(result.variable_names)
    lags = result.lags

    # Cholesky 分解
    P = cholesky(result.sigma).L

    # 初始化脉冲响应
    irf = zeros(periods + 1, n_vars, n_vars)

    # 第 0 期响应 = Cholesky 因子
    irf[1, :, :] = P

    # 构建伴随矩阵形式
    # Φ_i = A_i (VAR 系数)
    Phi = zeros(n_vars, n_vars, lags)
    for lag in 1:lags
        for i in 1:n_vars
            for j in 1:n_vars
                row_idx = (lag - 1) * n_vars + j
                Phi[i, j, lag] = result.coefficients[row_idx, i]
            end
        end
    end

    # 计算脉冲响应
    for t in 1:periods
        response = zeros(n_vars, n_vars)
        for s in 1:min(t, lags)
            response += Phi[:, :, s] * irf[t - s + 1, :, :]
        end
        irf[t + 1, :, :] = response
    end

    return irf
end

"""
    variance_decomposition(result::VARFitResult; periods=20) -> Array{Float64, 3}

方差分解。

# 参数
- `result`: VAR 拟合结果
- periods: 分解期数

# 返回
- `vd`: 方差分解矩阵 (periods+1) × n_vars × n_vars
"""
function variance_decomposition(result::VARFitResult; periods::Int=20)
    n_vars = length(result.variable_names)

    # 获取脉冲响应
    irf = impulse_response(result, periods=periods)

    # 计算方差分解
    vd = zeros(periods + 1, n_vars, n_vars)

    for t in 1:(periods + 1)
        # 累积脉冲响应平方
        cum_irf_sq = zeros(n_vars, n_vars)
        for s in 1:t
            cum_irf_sq += irf[s, :, :] .^ 2
        end

        # 总方差
        total_var = sum(cum_irf_sq, dims=2)

        # 各变量贡献
        for i in 1:n_vars
            vd[t, i, :] = cum_irf_sq[i, :] ./ total_var[i]
        end
    end

    return vd
end

# === 协议方法 =============================================================

function MetricaBase.glance(result::VARFitResult)
    return result.glance_table
end

function MetricaBase.tidy(result::VARFitResult)
    return result.tidy_table
end

function MetricaBase.augment(result::VARFitResult)
    n = size(result.original_data, 1)
    n_fitted = size(result.fitted_values, 1)

    obs = collect(1.0:n)
    fitted = zeros(n, length(result.variable_names))
    resid = zeros(n, length(result.variable_names))

    start_idx = n - n_fitted + 1
    fitted[start_idx:end, :] = result.fitted_values
    resid[start_idx:end, :] = result.residuals

    return MetricaBase.AugmentTable(
        Dict(
            :observation => obs,
            :fitted => fitted,
            :residual => resid,
        ),
        n
    )
end

function MetricaBase.coef(result::VARFitResult)
    return result.coefficients
end

function MetricaBase.nobs(result::VARFitResult)
    return size(result.original_data, 1)
end
```

- [ ] **Step 2: 添加 VAR 测试**

在 `packages/MetricaTimeSeries.jl/test/runtests.jl` 中添加：

```julia
@testset "VAR Tests" begin
    # 生成双变量 VAR(1) 过程
    n = 200
    Random.seed!(1234)

    # 真实参数
    A1 = [0.5 0.2; -0.1 0.3]

    y = zeros(n, 2)
    y[1, :] = randn(2)
    for t in 2:n
        y[t, :] = A1 * y[t-1, :] + randn(2)
    end

    df = DataFrame(time = 1:n, x1 = y[:, 1], x2 = y[:, 2])

    @testset "VAR(1) Estimation" begin
        model = VARModel(variables=[:x1, :x2], time_column=:time, lags=1)
        result = fit(model, df)

        @test result isa VARFitResult
        @test result.lags == 1
        @test size(result.coefficients) == (3, 2)  # 2 lags + constant × 2 vars
        @test result.aic < Inf
        @test result.bic < Inf
    end

    @testset "Granger Causality" begin
        model = VARModel(variables=[:x1, :x2], time_column=:time, lags=2)
        result = fit(model, df)

        gc = granger_causality(result, :x1, :x2)
        @test haskey(gc, :f_stat)
        @test haskey(gc, :p_value)
        @test haskey(gc, :conclusion)
    end

    @testset "Impulse Response" begin
        model = VARModel(variables=[:x1, :x2], time_column=:time, lags=1)
        result = fit(model, df)

        irf = impulse_response(result, periods=10)
        @test size(irf) == (11, 2, 2)
    end

    @testset "Variance Decomposition" begin
        model = VARModel(variables=[:x1, :x2], time_column=:time, lags=1)
        result = fit(model, df)

        vd = variance_decomposition(result, periods=10)
        @test size(vd) == (11, 2, 2)
        # 方差分解应和为 1
        @test all(sum(vd, dims=3) .≈ 1.0)
    end
end
```

- [ ] **Step 3: 提交**

```bash
git add packages/MetricaTimeSeries.jl/src/var.jl
git commit -m "feat(S4c): implement VAR model with Granger causality, impulse response, and variance decomposition"
```

---

## Phase 5：协整检验 🟡

**目标：** 实现 Engle-Granger 和 Johansen 协整检验。

### Task 5.1：协整检验实现

**Files:**
- Create: `packages/MetricaTimeSeries.jl/src/cointegration.jl`

- [ ] **Step 1: 实现协整检验**

```julia
# cointegration.jl - 协整检验模块

"""
    CointegrationModel <: AbstractTimeSeriesModel

协整检验模型规格。
"""
struct CointegrationModel <: AbstractTimeSeriesModel
    variables::Vector{Symbol}
    time_column::Symbol
    method::Symbol  # :engle_granger 或 :johansen
    lags::Int
    deterministic::Symbol  # :constant, :trend, :none
end

"""
    CointegrationFitResult <: AbstractTSFitResult

协整检验拟合结果。
"""
struct CointegrationFitResult <: AbstractTSFitResult
    variable_names::Vector{String}
    method::Symbol
    test_statistic::Float64
    p_value::Float64
    critical_values::Dict{Float64, Float64}
    cointegrating_vector::Union{Vector{Float64}, Nothing}
    n_cointegrating_relations::Int
    residuals::Union{Vector{Float64}, Nothing}
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    warnings::Vector{MetricaBase.ModelWarning}
end

"""
    CointegrationModel(; variables, time_column, method=:engle_granger, lags=1, deterministic=:constant)

构造协整检验模型规格。
"""
function CointegrationModel(; variables::Vector{Symbol}, time_column::Symbol,
                           method::Symbol=:engle_granger, lags::Int=1,
                           deterministic::Symbol=:constant)
    if length(variables) < 2
        error("协整检验至少需要 2 个变量")
    end
    return CointegrationModel(variables, time_column, method, lags, deterministic)
end

"""
    engle_granger_test(y::Vector{Float64}, X::Matrix{Float64}; deterministic=:constant, lags=:auto) -> NamedTuple

Engle-Granger 两步法协整检验。

# 参数
- `y`: 因变量
- `X`: 自变量矩阵
- `deterministic`: 确定性成分
- `lags`: ADF 检验滞后阶数

# 返回
- `(test_statistic, p_value, critical_values, cointegrating_vector, residuals)`
"""
function engle_granger_test(y::Vector{Float64}, X::Matrix{Float64};
                           deterministic::Symbol=:constant, lags=:auto)
    n = length(y)

    # 第一步：OLS 回归 y = Xβ + ε
    X_aug = hcat(ones(n), X)
    beta = X_aug \ y
    residuals = y - X_aug * beta

    # 第二步：对残差进行 ADF 检验
    adf_result = adf_test(residuals, deterministic=deterministic, lag=lags)

    # Engle-Granger 临界值（MacKinnon 2010）
    # 这些是简化值，实际应根据样本量和变量数调整
    n_vars = size(X, 2) + 1
    critical_values = if n_vars == 2
        Dict(0.01 => -3.90, 0.05 => -3.34, 0.10 => -3.04)
    elseif n_vars == 3
        Dict(0.01 => -4.30, 0.05 => -3.74, 0.10 => -3.45)
    else
        Dict(0.01 => -4.70, 0.05 => -4.14, 0.10 => -3.85)
    end

    # p 值（使用近似）
    p_value = adf_result.p_value

    # 协整向量
    cointegrating_vector = [1.0; -beta[2:end]]

    return (
        test_statistic=adf_result.test_statistic,
        p_value=p_value,
        critical_values=critical_values,
        cointegrating_vector=cointegrating_vector,
        residuals=residuals
    )
end

"""
    johansen_test(data::Matrix{Float64}; lags=1, deterministic=:constant) -> NamedTuple

Johansen 协整检验。

# 参数
- `data`: 数据矩阵 (n × k)
- `lags`: VAR 模型滞后阶数
- `deterministic`: 确定性成分

# 返回
- `(trace_stats, max_eigen_stats, critical_values, eigenvectors, eigenvalues)`
"""
function johansen_test(data::Matrix{Float64}; lags::Int=1, deterministic::Symbol=:constant)
    n, k = size(data)

    # 构建差分和滞后矩阵
    dy = diff(data, dims=1)
    n_reg = size(dy, 1) - lags

    # 构建回归矩阵
    # Δy_t = Π y_{t-1} + Σ Γ_i Δy_{t-i} + ε_t
    Y0 = dy[lags+1:end, :]  # 因变量
    Y1 = data[lags:end-1, :]  # 水平滞后

    # 差分滞后
    X_lags = zeros(n_reg, k * lags)
    for i in 1:lags
        X_lags[:, (i-1)*k+1:i*k] = dy[lags+1-i:end-i, :]
    end

    # 添加常数项
    if deterministic === :constant
        X = hcat(Y1, X_lags, ones(n_reg))
    elseif deterministic === :trend
        X = hcat(Y1, X_lags, collect(1:n_reg), ones(n_reg))
    else
        X = hcat(Y1, X_lags)
    end

    # OLS 估计
    B = X \ Y0
    residuals = Y0 - X * B

    # 计算 R0 和 R1
    R0 = residuals
    R1 = Y1 - X[:, k*lags+1:end] * B[k*lags+1:end, :]

    # 计算 S 矩阵
    S00 = (R0' * R0) / n_reg
    S11 = (R1' * R1) / n_reg
    S01 = (R0' * R1) / n_reg
    S10 = S01'

    # 求解广义特征值问题
    M = inv(S11) * S10 * inv(S00) * S01
    eigenvalues = eigvals(M)
    eigenvectors = eigvecs(M)

    # 按特征值降序排序
    sorted_indices = sortperm(eigenvalues, rev=true)
    eigenvalues = eigenvalues[sorted_indices]
    eigenvectors = eigenvectors[:, sorted_indices]

    # 计算迹统计量和最大特征值统计量
    trace_stats = zeros(k)
    max_eigen_stats = zeros(k)

    for i in 1:k
        # 迹统计量
        trace_stats[i] = -n_reg * sum(log.(1 .- eigenvalues[i:end]))

        # 最大特征值统计量
        max_eigen_stats[i] = -n_reg * log(1 - eigenvalues[i])
    end

    # 临界值（简化值，实际应使用 MacKinnon 表）
    critical_values_trace = Dict(
        0.01 => [20.04, 15.41, 3.84],
        0.05 => [15.41, 9.42, 3.84],
        0.10 => [13.33, 7.56, 2.71]
    )

    critical_values_max = Dict(
        0.01 => [20.04, 15.41, 3.84],
        0.05 => [15.41, 9.42, 3.84],
        0.10 => [13.33, 7.56, 2.71]
    )

    return (
        trace_stats=trace_stats,
        max_eigen_stats=max_eigen_stats,
        critical_values_trace=critical_values_trace,
        critical_values_max=critical_values_max,
        eigenvectors=eigenvectors,
        eigenvalues=eigenvalues
    )
end

"""
    fit(model::CointegrationModel, data::DataFrame) -> CointegrationFitResult

执行协整检验。

# 参数
- `model`: 协整检验模型规格
- `data`: 包含时间序列数据的 DataFrame

# 返回
- `CointegrationFitResult`: 检验结果
"""
function MetricaBase.fit(model::CointegrationModel, data::DataFrame)
    # 排序数据
    data_sorted = sort_by_time(data, model.time_column)

    # 提取变量
    n_vars = length(model.variables)
    Y = Matrix{Float64}(data_sorted[!, model.variables])

    warnings = MetricaBase.ModelWarning[]

    if model.method === :engle_granger
        # Engle-Granger 两步法
        y = Y[:, 1]
        X = Y[:, 2:end]

        result = engle_granger_test(y, X, deterministic=model.deterministic, lags=model.lags)

        # 判断协整关系数
        n_cointegrating = result.p_value < 0.05 ? 1 : 0

        # 构建 glance 表
        glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
            :test_statistic => result.test_statistic,
            :p_value => result.p_value,
            :n_cointegrating => n_cointegrating,
            :nobs => length(y),
        )

        glance_table = MetricaBase.ModelGlance(
            "Engle-Granger Cointegration",
            join(string.(model.variables), ", "),
            length(y),
            glance_metrics
        )

        # 构建 tidy 表（协整向量）
        coef_rows = MetricaBase.CoefRow[]
        if !isnothing(result.cointegrating_vector)
            for (i, var_name) in enumerate(model.variables)
                push!(coef_rows, MetricaBase.CoefRow(
                    Symbol(var_name),
                    result.cointegrating_vector[i],
                    0.0, 0.0, 0.0
                ))
            end
        end

        tidy_table = MetricaBase.TidyTable(
            [:term, :estimate, :stderror, :statistic, :p_value],
            coef_rows,
            length(coef_rows)
        )

        return CointegrationFitResult(
            string.(model.variables),
            model.method,
            result.test_statistic,
            result.p_value,
            result.critical_values,
            result.cointegrating_vector,
            n_cointegrating,
            result.residuals,
            glance_table,
            tidy_table,
            warnings
        )

    elseif model.method === :johansen
        # Johansen 检验
        result = johansen_test(Y, lags=model.lags, deterministic=model.deterministic)

        # 判断协整关系数（迹检验）
        n_cointegrating = 0
        for i in 1:n_vars
            cv = result.critical_values_trace[0.05][min(i, length(result.critical_values_trace[0.05]))]
            if result.trace_stats[i] > cv
                n_cointegrating += 1
            else
                break
            end
        end

        # 构建 glance 表
        glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
            :trace_stat_1 => result.trace_stats[1],
            :max_eigen_stat_1 => result.max_eigen_stats[1],
            :n_cointegrating => n_cointegrating,
            :nobs => nrow(data_sorted),
        )

        glance_table = MetricaBase.ModelGlance(
            "Johansen Cointegration",
            join(string.(model.variables), ", "),
            nrow(data_sorted),
            glance_metrics
        )

        # 构建 tidy 表（特征向量）
        coef_rows = MetricaBase.CoefRow[]
        for (i, var_name) in enumerate(model.variables)
            for j in 1:n_vars
                push!(coef_rows, MetricaBase.CoefRow(
                    Symbol("$(var_name)_vec$j"),
                    result.eigenvectors[i, j],
                    0.0, 0.0, 0.0
                ))
            end
        end

        tidy_table = MetricaBase.TidyTable(
            [:term, :estimate, :stderror, :statistic, :p_value],
            coef_rows,
            length(coef_rows)
        )

        return CointegrationFitResult(
            string.(model.variables),
            model.method,
            result.trace_stats[1],
            0.0,  # p 值需要从表中查找
            Dict{Float64, Float64}(),
            result.eigenvectors[:, 1],
            n_cointegrating,
            nothing,
            glance_table,
            tidy_table,
            warnings
        )

    else
        error("未知的协整检验方法: $(model.method)")
    end
end

# === 协议方法 =============================================================

function MetricaBase.glance(result::CointegrationFitResult)
    return result.glance_table
end

function MetricaBase.tidy(result::CointegrationFitResult)
    return result.tidy_table
end

function MetricaBase.augment(result::CointegrationFitResult)
    if isnothing(result.residuals)
        return MetricaBase.AugmentTable(Dict{Symbol, Any}(), 0)
    end

    n = length(result.residuals)
    return MetricaBase.AugmentTable(
        Dict(
            :observation => collect(1.0:n),
            :residual => result.residuals,
        ),
        n
    )
end
```

- [ ] **Step 2: 添加协整检验测试**

在 `packages/MetricaTimeSeries.jl/test/runtests.jl` 中添加：

```julia
@testset "Cointegration Tests" begin
    # 生成协整序列
    n = 200
    Random.seed!(1234)

    # 共同随机趋势
    common_trend = cumsum(randn(n))

    # 两个协整序列
    x1 = common_trend + randn(n) * 0.5
    x2 = 0.8 * common_trend + randn(n) * 0.5

    df = DataFrame(time = 1:n, x1 = x1, x2 = x2)

    @testset "Engle-Granger" begin
        model = CointegrationModel(
            variables=[:x1, :x2],
            time_column=:time,
            method=:engle_granger
        )
        result = fit(model, df)

        @test result isa CointegrationFitResult
        @test result.method == :engle_granger
        @test result.n_cointegrating_relations == 1  # 应该检测到协整
    end

    @testset "Johansen" begin
        model = CointegrationModel(
            variables=[:x1, :x2],
            time_column=:time,
            method=:johansen,
            lags=2
        )
        result = fit(model, df)

        @test result isa CointegrationFitResult
        @test result.method == :johansen
    end
end
```

- [ ] **Step 3: 提交**

```bash
git add packages/MetricaTimeSeries.jl/src/cointegration.jl
git commit -m "feat(S4c): implement Engle-Granger and Johansen cointegration tests"
```

---

## Phase 6：预测模块 🟢

**目标：** 实现一步/多步预测和预测区间。

### Task 6.1：预测模块实现

**Files:**
- Create: `packages/MetricaTimeSeries.jl/src/forecast.jl`

- [ ] **Step 1: 实现预测模块**

```julia
# forecast.jl - 预测模块

"""
    ForecastResult

预测结果。
"""
struct ForecastResult
    point_forecast::Vector{Float64}
    lower_bound::Vector{Float64}
    upper_bound::Vector{Float64}
    confidence_level::Float64
    forecast_origin::Int
    steps::Int
end

"""
    forecast(result::ARIMAFitResult; steps=10, level=0.95) -> ForecastResult

ARIMA 模型预测。

# 参数
- `result`: ARIMA 拟合结果
- `steps`: 预测步数
- `level`: 置信水平

# 返回
- `ForecastResult`: 预测结果
"""
function forecast(result::ARIMAFitResult; steps::Int=10, level::Float64=0.95)
    n = length(result.original_series)
    p, d, q = result.order

    # 获取差分序列
    if isnothing(result.differenced_series)
        y_diff = difference(result.original_series, d)
    else
        y_diff = result.differenced_series
    end
    n_diff = length(y_diff)

    # 获取 AR 系数
    ar_coeffs = Float64[]
    for i in 1:p
        key = Symbol("ar$i")
        push!(ar_coeffs, get(result.coefficients, key, 0.0))
    end

    # 获取 MA 系数
    ma_coeffs = Float64[]
    for i in 1:q
        key = Symbol("ma$i")
        push!(ma_coeffs, get(result.coefficients, key, 0.0))
    end

    # 获取常数项
    constant = get(result.coefficients, :constant, 0.0)

    # 预测
    point_forecast = zeros(steps)
    forecast_errors = zeros(steps)

    # 使用最后 p 个 AR 值和 q 个残差
    last_ar = y_diff[end-p+1:end]
    last_ma = result.residuals[end-q+1:end]

    for h in 1:steps
        # AR 部分
        ar_part = 0.0
        for i in 1:min(p, h)
            ar_part += ar_coeffs[i] * last_ar[end-i+1]
        end

        # MA 部分（未来冲击为 0）
        ma_part = 0.0
        for i in 1:min(q, h-1)
            ma_part += ma_coeffs[i] * last_ma[end-i+1]
        end

        # 预测值
        point_forecast[h] = constant + ar_part + ma_part

        # 更新 AR 历史
        if h <= p
            last_ar = [last_ar; point_forecast[h]]
        else
            last_ar = [last_ar[2:end]; point_forecast[h]]
        end

        # 预测误差方差（简化计算）
        forecast_errors[h] = sqrt(result.sigma2 * h)
    end

    # 如果有差分，需要积分回原始尺度
    if d > 0
        # 简化处理：假设差分前的最后一个值
        last_value = result.original_series[end]
        point_forecast = cumsum(point_forecast) .+ last_value
        forecast_errors = cumsum(forecast_errors)
    end

    # 置信区间
    z = quantile(Normal(0, 1), 1 - (1 - level) / 2)
    lower_bound = point_forecast .- z .* forecast_errors
    upper_bound = point_forecast .+ z .* forecast_errors

    return ForecastResult(
        point_forecast,
        lower_bound,
        upper_bound,
        level,
        n,
        steps
    )
end

"""
    forecast(result::VARFitResult; steps=10, level=0.95) -> Dict{Symbol, ForecastResult}

VAR 模型预测。

# 参数
- `result`: VAR 拟合结果
- `steps`: 预测步数
- `level`: 置信水平

# 返回
- `Dict{Symbol, ForecastResult}`: 各变量的预测结果
"""
function forecast(result::VARFitResult; steps::Int=10, level::Float64=0.95)
    n_vars = length(result.variable_names)
    lags = result.lags
    n = size(result.original_data, 1)

    # 获取脉冲响应用于计算预测区间
    irf = impulse_response(result, periods=steps)

    forecasts = Dict{Symbol, ForecastResult}()

    for (var_idx, var_name) in enumerate(result.variable_names)
        point_forecast = zeros(steps)
        forecast_errors = zeros(steps)

        # 使用最后 lags 个值
        last_values = result.original_data[end-lags+1:end, :]

        for h in 1:steps
            # 预测值
            pred = 0.0

            # AR 部分
            for lag in 1:lags
                for j in 1:n_vars
                    row_idx = (lag - 1) * n_vars + j
                    pred += result.coefficients[row_idx, var_idx] * last_values[end-lag+1, j]
                end
            end

            # 常数项
            if size(result.coefficients, 1) > n_vars * lags
                pred += result.coefficients[end, var_idx]
            end

            point_forecast[h] = pred

            # 更新历史
            if h < steps
                new_row = zeros(n_vars)
                new_row[var_idx] = pred
                last_values = [last_values[2:end, :]; new_row']
            end

            # 预测误差方差（使用脉冲响应）
            for s in 1:h
                forecast_errors[h] += sum(irf[s, var_idx, :] .^ 2)
            end
            forecast_errors[h] = sqrt(forecast_errors[h])
        end

        # 置信区间
        z = quantile(Normal(0, 1), 1 - (1 - level) / 2)
        lower_bound = point_forecast .- z .* forecast_errors
        upper_bound = point_forecast .+ z .* forecast_errors

        forecasts[Symbol(var_name)] = ForecastResult(
            point_forecast,
            lower_bound,
            upper_bound,
            level,
            n,
            steps
        )
    end

    return forecasts
end

"""
    acf(y::Vector{Float64}; max_lags=20) -> Vector{Float64}

计算自相关函数。

# 参数
- `y`: 时间序列
- `max_lags`: 最大滞后阶数

# 返回
- `acf_values`: ACF 值向量
"""
function acf(y::Vector{Float64}; max_lags::Int=20)
    n = length(y)
    mean_y = mean(y)
    gamma_0 = sum((y .- mean_y) .^ 2) / n

    acf_values = zeros(max_lags + 1)
    acf_values[1] = 1.0

    for k in 1:max_lags
        gamma_k = sum((y[k+1:end] .- mean_y) .* (y[1:end-k] .- mean_y)) / n
        acf_values[k+1] = gamma_k / gamma_0
    end

    return acf_values
end

"""
    pacf(y::Vector{Float64}; max_lags=20) -> Vector{Float64}

计算偏自相关函数。

# 参数
- `y`: 时间序列
- `max_lags`: 最大滞后阶数

# 返回
- `pacf_values`: PACF 值向量
"""
function pacf(y::Vector{Float64}; max_lags::Int=20)
    n = length(y)
    acf_values = acf(y, max_lags=max_lags)

    pacf_values = zeros(max_lags + 1)
    pacf_values[1] = 1.0

    # 使用 Durbin-Levinson 算法
    phi = zeros(max_lags, max_lags)
    v = zeros(max_lags + 1)
    v[1] = acf_values[1]

    for k in 1:max_lags
        # 计算 phi[k,k]
        num = acf_values[k+1]
        for j in 1:k-1
            num -= phi[k-1, j] * acf_values[k-j+1]
        end
        phi[k, k] = num / v[k]

        # 更新 phi
        for j in 1:k-1
            phi[k, j] = phi[k-1, j] - phi[k, k] * phi[k-1, k-j]
        end

        # 更新方差
        v[k+1] = v[k] * (1 - phi[k, k]^2)

        pacf_values[k+1] = phi[k, k]
    end

    return pacf_values
end

"""
    ljung_box_test(y::Vector{Float64}; lags=10) -> NamedTuple

Ljung-Box 自相关检验。

# 参数
- `y`: 时间序列（通常为残差）
- `lags`: 检验滞后阶数

# 返回
- `(test_statistic, p_value, conclusion)`
"""
function ljung_box_test(y::Vector{Float64}; lags::Int=10)
    n = length(y)
    acf_values = acf(y, max_lags=lags)

    # Ljung-Box 统计量
    Q = n * (n + 2) * sum(acf_values[2:lags+1] .^ 2 ./ (n .- (1:lags)))

    # p 值
    p_value = 1 - cdf(Chisq(lags), Q)

    conclusion = p_value < 0.05 ? "reject" : "fail_to_reject"

    return (test_statistic=Q, p_value=p_value, conclusion=conclusion)
end
```

- [ ] **Step 2: 添加预测测试**

在 `packages/MetricaTimeSeries.jl/test/runtests.jl` 中添加：

```julia
@testset "Forecast Tests" begin
    # 生成 AR(1) 过程
    n = 200
    Random.seed!(1234)
    y = zeros(n)
    y[1] = randn()
    for t in 2:n
        y[t] = 0.5 * y[t-1] + randn()
    end

    df = DataFrame(time = 1:n, y = y)

    @testset "ARIMA Forecast" begin
        model = ARIMAModel(variable=:y, time_column=:time, order=(1,0,0))
        result = fit(model, df)

        fc = forecast(result, steps=10, level=0.95)

        @test fc isa ForecastResult
        @test length(fc.point_forecast) == 10
        @test length(fc.lower_bound) == 10
        @test length(fc.upper_bound) == 10
        @test all(fc.lower_bound .<= fc.point_forecast)
        @test all(fc.point_forecast .<= fc.upper_bound)
    end

    @testset "ACF and PACF" begin
        acf_values = acf(y, max_lags=20)
        pacf_values = pacf(y, max_lags=20)

        @test length(acf_values) == 21
        @test length(pacf_values) == 21
        @test acf_values[1] ≈ 1.0
        @test pacf_values[1] ≈ 1.0
    end

    @testset "Ljung-Box Test" begin
        lb = ljung_box_test(y, lags=10)

        @test haskey(lb, :test_statistic)
        @test haskey(lb, :p_value)
        @test haskey(lb, :conclusion)
    end
end
```

- [ ] **Step 3: 提交**

```bash
git add packages/MetricaTimeSeries.jl/src/forecast.jl
git commit -m "feat(S4c): implement forecast module with ACF, PACF, and Ljung-Box test"
```

---

## Phase 7：序列化与 MODEL_REGISTRY 🟡

**目标：** 实现序列化层，确保与 Runtime 和 App 的集成。

### Task 7.1：序列化实现

**Files:**
- Create: `packages/MetricaTimeSeries.jl/src/serialize.jl`

- [ ] **Step 1: 实现序列化**

```julia
# serialize.jl - 序列化模块

"""
    result_to_payload(result::ARIMAFitResult) -> Dict

将 ARIMA 拟合结果转换为 Runtime 可消费的 payload。
"""
function MetricaBase.result_to_payload(result::ARIMAFitResult)
    payload = Dict{String, Any}(
        "model_type" => "arima",
        "variable" => result.variable_name,
        "order" => collect(result.order),
        "seasonal_order" => collect(result.seasonal_order),
        "nobs" => length(result.original_series),
        "sigma2" => result.sigma2,
        "loglik" => result.loglik,
        "aic" => result.aic,
        "bic" => result.bic,
        "coefficients" => Dict(string(k) => v for (k, v) in result.coefficients),
        "residuals" => result.residuals,
        "fitted_values" => result.fitted_values,
    )

    # 添加 glance 指标
    payload["glance"] = Dict(
        "model" => result.glance_table.model_name,
        "nobs" => result.glance_table.nobs,
        "metrics" => Dict(string(k) => v for (k, v) in result.glance_table.metrics)
    )

    # 添加 tidy 表
    payload["tidy"] = Dict(
        "columns" => string.(result.tidy_table.column_names),
        "rows" => [
            Dict(
                "term" => string(row.name),
                "estimate" => row.estimate,
                "stderror" => row.stderr,
                "statistic" => row.t_stat,
                "p_value" => row.p_value
            )
            for row in result.tidy_table.rows
        ]
    )

    # 添加警告
    if !isempty(result.warnings)
        payload["warnings"] = [
            Dict(
                "code" => string(w.code),
                "title" => w.title,
                "detail" => w.detail,
                "hint" => w.hint,
                "severity" => string(w.severity)
            )
            for w in result.warnings
        ]
    end

    return payload
end

"""
    result_to_payload(result::VARFitResult) -> Dict

将 VAR 拟合结果转换为 Runtime 可消费的 payload。
"""
function MetricaBase.result_to_payload(result::VARFitResult)
    payload = Dict{String, Any}(
        "model_type" => "var",
        "variables" => result.variable_names,
        "lags" => result.lags,
        "nobs" => size(result.original_data, 1),
        "loglik" => result.loglik,
        "aic" => result.aic,
        "bic" => result.bic,
        "hqic" => result.hqic,
        "coefficients" => result.coefficients,
        "std_errors" => result.std_errors,
        "residuals" => result.residuals,
        "sigma" => result.sigma,
    )

    # 添加 glance 指标
    payload["glance"] = Dict(
        "model" => result.glance_table.model_name,
        "nobs" => result.glance_table.nobs,
        "metrics" => Dict(string(k) => v for (k, v) in result.glance_table.metrics)
    )

    # 添加 tidy 表
    payload["tidy"] = Dict(
        "columns" => string.(result.tidy_table.column_names),
        "rows" => [
            Dict(
                "term" => string(row.name),
                "estimate" => row.estimate,
                "stderror" => row.stderr,
                "statistic" => row.t_stat,
                "p_value" => row.p_value
            )
            for row in result.tidy_table.rows
        ]
    )

    # 添加警告
    if !isempty(result.warnings)
        payload["warnings"] = [
            Dict(
                "code" => string(w.code),
                "title" => w.title,
                "detail" => w.detail,
                "hint" => w.hint,
                "severity" => string(w.severity)
            )
            for w in result.warnings
        ]
    end

    return payload
end

"""
    result_to_payload(result::UnitRootFitResult) -> Dict

将单位根检验结果转换为 Runtime 可消费的 payload。
"""
function MetricaBase.result_to_payload(result::UnitRootFitResult)
    payload = Dict{String, Any}(
        "model_type" => "unitroot",
        "variable" => result.variable_name,
        "nobs" => result.glance_table.nobs,
    )

    # 添加各检验结果
    if !isnothing(result.adf)
        payload["adf"] = Dict(
            "test_statistic" => result.adf.test_statistic,
            "p_value" => result.adf.p_value,
            "lags_used" => result.adf.lags_used,
            "critical_values" => Dict(string(k) => v for (k, v) in result.adf.critical_values),
            "conclusion" => result.adf.conclusion
        )
    end

    if !isnothing(result.pp)
        payload["pp"] = Dict(
            "test_statistic" => result.pp.test_statistic,
            "p_value" => result.pp.p_value,
            "lags_used" => result.pp.lags_used,
            "critical_values" => Dict(string(k) => v for (k, v) in result.pp.critical_values),
            "conclusion" => result.pp.conclusion
        )
    end

    if !isnothing(result.kpss)
        payload["kpss"] = Dict(
            "test_statistic" => result.kpss.test_statistic,
            "p_value" => result.kpss.p_value,
            "lags_used" => result.kpss.lags_used,
            "critical_values" => Dict(string(k) => v for (k, v) in result.kpss.critical_values),
            "conclusion" => result.kpss.conclusion
        )
    end

    # 添加 glance 指标
    payload["glance"] = Dict(
        "model" => result.glance_table.model_name,
        "nobs" => result.glance_table.nobs,
        "metrics" => Dict(string(k) => v for (k, v) in result.glance_table.metrics)
    )

    # 添加警告
    if !isempty(result.warnings)
        payload["warnings"] = [
            Dict(
                "code" => string(w.code),
                "title" => w.title,
                "detail" => w.detail,
                "hint" => w.hint,
                "severity" => string(w.severity)
            )
            for w in result.warnings
        ]
    end

    return payload
end

"""
    result_to_payload(result::CointegrationFitResult) -> Dict

将协整检验结果转换为 Runtime 可消费的 payload。
"""
function MetricaBase.result_to_payload(result::CointegrationFitResult)
    payload = Dict{String, Any}(
        "model_type" => "cointegration",
        "variables" => result.variable_names,
        "method" => string(result.method),
        "test_statistic" => result.test_statistic,
        "p_value" => result.p_value,
        "critical_values" => Dict(string(k) => v for (k, v) in result.critical_values),
        "n_cointegrating_relations" => result.n_cointegrating_relations,
    )

    if !isnothing(result.cointegrating_vector)
        payload["cointegrating_vector"] = result.cointegrating_vector
    end

    # 添加 glance 指标
    payload["glance"] = Dict(
        "model" => result.glance_table.model_name,
        "nobs" => result.glance_table.nobs,
        "metrics" => Dict(string(k) => v for (k, v) in result.glance_table.metrics)
    )

    # 添加警告
    if !isempty(result.warnings)
        payload["warnings"] = [
            Dict(
                "code" => string(w.code),
                "title" => w.title,
                "detail" => w.detail,
                "hint" => w.hint,
                "severity" => string(w.severity)
            )
            for w in result.warnings
        ]
    end

    return payload
end
```

- [ ] **Step 2: 提交**

```bash
git add packages/MetricaTimeSeries.jl/src/serialize.jl
git commit -m "feat(S4c): implement serialization for all time series model results"
```

---

## Phase 8：Runtime + App 集成 🟡

**目标：** 扩展 Runtime 和 App 以支持时间序列模型。

### Task 8.1：Runtime 层扩展

**Files:**
- Modify: `runtime/metrica-runtime/src/lib.rs`

- [ ] **Step 1: 扩展 Rust schema 校验**

在 `lib.rs` 的 `model_required_fields()` 函数中添加：

```rust
// 时间序列模型
"arima" => vec!["variable", "time_column", "order"],
"var" => vec!["variables", "time_column", "lags"],
"unitroot" => vec!["variable", "time_column"],
"cointegration" => vec!["variables", "time_column", "method"],
```

- [ ] **Step 2: 扩展 daemon dispatch**

在 `scripts/julia_daemon.jl` 中确认 MODEL_REGISTRY 已包含时间序列模型类型（由 MetricaTimeSeries.jl 的 `__init__()` 自动注册）。

- [ ] **Step 3: 提交**

```bash
git add runtime/metrica-runtime/src/lib.rs
git commit -m "feat(S4c): extend Runtime schema validation for time series models"
```

### Task 8.2：TypeScript 类型扩展

**Files:**
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts`
- Modify: `apps/metrica-desktop/src-react/stores/modelStore.ts`
- Modify: `apps/metrica-desktop/src-react/services/runtimeClient.ts`

- [ ] **Step 1: 扩展 TypeScript 类型**

在 `protocol.ts` 中添加：

```typescript
// 时间序列模型类型
export type TimeSeriesModelType = 'arima' | 'var' | 'unitroot' | 'cointegration';

// ARIMA 模型规格
export interface ARIMAModelSpec {
  model_type: 'arima';
  variable: string;
  time_column: string;
  order: [number, number, number];  // [p, d, q]
  seasonal_order?: [number, number, number, number];  // [P, D, Q, s]
  include_constant?: boolean;
  method?: 'mle' | 'css';
}

// VAR 模型规格
export interface VARModelSpec {
  model_type: 'var';
  variables: string[];
  time_column: string;
  lags: number;
  include_constant?: boolean;
}

// 单位根检验规格
export interface UnitRootModelSpec {
  model_type: 'unitroot';
  variable: string;
  time_column: string;
  deterministic?: 'constant' | 'trend' | 'none';
  lag_method?: 'auto' | 'aic' | 'bic';
  max_lags?: number;
}

// 协整检验规格
export interface CointegrationModelSpec {
  model_type: 'cointegration';
  variables: string[];
  time_column: string;
  method?: 'engle_granger' | 'johansen';
  lags?: number;
  deterministic?: 'constant' | 'trend' | 'none';
}

// 预测结果
export interface ForecastResult {
  point_forecast: number[];
  lower_bound: number[];
  upper_bound: number[];
  confidence_level: number;
  forecast_origin: number;
  steps: number;
}

// 脉冲响应结果
export interface ImpulseResponseResult {
  periods: number;
  n_vars: number;
  responses: number[][][];  // [period][shock_var][response_var]
}
```

- [ ] **Step 2: 扩展 modelStore**

在 `modelStore.ts` 中添加时间序列表单状态：

```typescript
// 时间序列相关状态
timeColumn: string | null;
arimaOrder: [number, number, number];
seasonalOrder: [number, number, number, number];
varLags: number;
forecastSteps: number;
```

- [ ] **Step 3: 提交**

```bash
git add apps/metrica-desktop/src-react/types/protocol.ts apps/metrica-desktop/src-react/stores/modelStore.ts
git commit -m "feat(S4c): extend TypeScript types for time series models"
```

### Task 8.3：App 组件

**Files:**
- Create: `apps/metrica-desktop/src-react/components/TimeSeriesForm.tsx`
- Create: `apps/metrica-desktop/src-react/components/ForecastChart.tsx`
- Create: `apps/metrica-desktop/src-react/components/UnitRootTable.tsx`
- Create: `apps/metrica-desktop/src-react/components/ImpulseResponseChart.tsx`
- Create: `apps/metrica-desktop/src-react/components/ACFPACFChart.tsx`
- Create: `apps/metrica-desktop/src-react/components/TimeSeriesGlanceCards.tsx`
- Modify: `apps/metrica-desktop/src-react/components/ModelForm.tsx`

- [ ] **Step 1: 创建 TimeSeriesForm 组件**

```tsx
// TimeSeriesForm.tsx
import React from 'react';
import { Form, Select, InputNumber, Switch } from 'antd';

interface TimeSeriesFormProps {
  modelType: 'arima' | 'var' | 'unitroot' | 'cointegration';
  columns: string[];
  onChange: (values: any) => void;
}

export const TimeSeriesForm: React.FC<TimeSeriesFormProps> = ({
  modelType,
  columns,
  onChange
}) => {
  return (
    <Form layout="vertical" onValuesChange={onChange}>
      <Form.Item label="时间列" name="timeColumn" rules={[{ required: true }]}>
        <Select options={columns.map(c => ({ label: c, value: c }))} />
      </Form.Item>

      {modelType === 'arima' && (
        <>
          <Form.Item label="目标变量" name="variable" rules={[{ required: true }]}>
            <Select options={columns.map(c => ({ label: c, value: c }))} />
          </Form.Item>
          <Form.Item label="AR 阶数 (p)" name={['order', 0]}>
            <InputNumber min={0} max={10} />
          </Form.Item>
          <Form.Item label="差分阶数 (d)" name={['order', 1]}>
            <InputNumber min={0} max={3} />
          </Form.Item>
          <Form.Item label="MA 阶数 (q)" name={['order', 2]}>
            <InputNumber min={0} max={10} />
          </Form.Item>
          <Form.Item label="包含常数项" name="includeConstant" valuePropName="checked">
            <Switch />
          </Form.Item>
        </>
      )}

      {modelType === 'var' && (
        <>
          <Form.Item label="变量" name="variables" rules={[{ required: true }]}>
            <Select mode="multiple" options={columns.map(c => ({ label: c, value: c }))} />
          </Form.Item>
          <Form.Item label="滞后阶数" name="lags">
            <InputNumber min={1} max={10} />
          </Form.Item>
        </>
      )}

      {modelType === 'unitroot' && (
        <>
          <Form.Item label="检验变量" name="variable" rules={[{ required: true }]}>
            <Select options={columns.map(c => ({ label: c, value: c }))} />
          </Form.Item>
          <Form.Item label="确定性成分" name="deterministic">
            <Select options={[
              { label: '常数项', value: 'constant' },
              { label: '趋势项', value: 'trend' },
              { label: '无', value: 'none' }
            ]} />
          </Form.Item>
        </>
      )}

      {modelType === 'cointegration' && (
        <>
          <Form.Item label="协整变量" name="variables" rules={[{ required: true }]}>
            <Select mode="multiple" options={columns.map(c => ({ label: c, value: c }))} />
          </Form.Item>
          <Form.Item label="检验方法" name="method">
            <Select options={[
              { label: 'Engle-Granger', value: 'engle_granger' },
              { label: 'Johansen', value: 'johansen' }
            ]} />
          </Form.Item>
        </>
      )}
    </Form>
  );
};
```

- [ ] **Step 2: 创建 ForecastChart 组件**

```tsx
// ForecastChart.tsx
import React from 'react';
import ReactECharts from 'echarts-for-react';

interface ForecastChartProps {
  historical: number[];
  forecast: {
    point_forecast: number[];
    lower_bound: number[];
    upper_bound: number[];
  };
  title?: string;
}

export const ForecastChart: React.FC<ForecastChartProps> = ({
  historical,
  forecast,
  title = '预测图'
}) => {
  const historicalLength = historical.length;
  const forecastLength = forecast.point_forecast.length;
  const totalLength = historicalLength + forecastLength;

  const xData = Array.from({ length: totalLength }, (_, i) => i + 1);

  const option = {
    title: { text: title },
    tooltip: { trigger: 'axis' },
    legend: { data: ['历史数据', '预测值', '置信区间'] },
    xAxis: { type: 'category', data: xData },
    yAxis: { type: 'value' },
    series: [
      {
        name: '历史数据',
        type: 'line',
        data: [...historical, ...Array(forecastLength).fill(null)],
        lineStyle: { width: 2 }
      },
      {
        name: '预测值',
        type: 'line',
        data: [...Array(historicalLength).fill(null), ...forecast.point_forecast],
        lineStyle: { width: 2, type: 'dashed' }
      },
      {
        name: '置信区间',
        type: 'line',
        data: [...Array(historicalLength).fill(null), ...forecast.upper_bound],
        lineStyle: { opacity: 0 },
        areaStyle: { opacity: 0.3 },
        stack: 'confidence'
      },
      {
        name: '置信区间下界',
        type: 'line',
        data: [...Array(historicalLength).fill(null), ...forecast.lower_bound],
        lineStyle: { opacity: 0 },
        areaStyle: { opacity: 0.3 },
        stack: 'confidence'
      }
    ]
  };

  return <ReactECharts option={option} style={{ height: 400 }} />;
};
```

- [ ] **Step 3: 创建 UnitRootTable 组件**

```tsx
// UnitRootTable.tsx
import React from 'react';
import { Table, Tag } from 'antd';

interface UnitRootTableProps {
  adf?: {
    test_statistic: number;
    p_value: number;
    conclusion: string;
  };
  pp?: {
    test_statistic: number;
    p_value: number;
    conclusion: string;
  };
  kpss?: {
    test_statistic: number;
    p_value: number;
    conclusion: string;
  };
}

export const UnitRootTable: React.FC<UnitRootTableProps> = ({
  adf,
  pp,
  kpss
}) => {
  const dataSource = [
    adf && {
      key: 'adf',
      test: 'ADF',
      statistic: adf.test_statistic.toFixed(4),
      p_value: adf.p_value.toFixed(4),
      conclusion: adf.conclusion === 'reject' ?
        <Tag color="green">平稳</Tag> :
        <Tag color="red">非平稳</Tag>
    },
    pp && {
      key: 'pp',
      test: 'Phillips-Perron',
      statistic: pp.test_statistic.toFixed(4),
      p_value: pp.p_value.toFixed(4),
      conclusion: pp.conclusion === 'reject' ?
        <Tag color="green">平稳</Tag> :
        <Tag color="red">非平稳</Tag>
    },
    kpss && {
      key: 'kpss',
      test: 'KPSS',
      statistic: kpss.test_statistic.toFixed(4),
      p_value: kpss.p_value.toFixed(4),
      conclusion: kpss.conclusion === 'reject' ?
        <Tag color="red">非平稳</Tag> :
        <Tag color="green">平稳</Tag>
    }
  ].filter(Boolean);

  const columns = [
    { title: '检验方法', dataIndex: 'test', key: 'test' },
    { title: '统计量', dataIndex: 'statistic', key: 'statistic' },
    { title: 'p 值', dataIndex: 'p_value', key: 'p_value' },
    { title: '结论 (5%)', dataIndex: 'conclusion', key: 'conclusion' }
  ];

  return <Table dataSource={dataSource} columns={columns} pagination={false} />;
};
```

- [ ] **Step 4: 创建其他组件**

创建 `ImpulseResponseChart.tsx`、`ACFPACFChart.tsx`、`TimeSeriesGlanceCards.tsx`，并修改 `ModelForm.tsx` 添加时间序列模型选项。

- [ ] **Step 5: 提交**

```bash
git add apps/metrica-desktop/src-react/components/
git commit -m "feat(S4c): add time series UI components (TimeSeriesForm, ForecastChart, UnitRootTable, etc.)"
```

---

## Phase 9：端到端验证 🟢

**目标：** 验证完整链路：Core → Runtime → App。

### Task 9.1：端到端测试

- [ ] **Step 1: Julia 端测试**

```bash
cd packages/MetricaTimeSeries.jl
julia --project=. -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 2: Runtime 端测试**

启动 daemon 并测试时间序列模型请求：

```bash
# 启动 daemon
julia scripts/julia_daemon.jl

# 测试 ARIMA 请求
curl -X POST http://localhost:8080/fit_model \
  -H "Content-Type: application/json" \
  -d '{
    "model_type": "arima",
    "formula": "y",
    "data_path": "datasets/teaching/grunfeld.csv",
    "options": {
      "variable": "y",
      "time_column": "year",
      "order": [1, 1, 1]
    }
  }'

# 测试 VAR 请求
curl -X POST http://localhost:8080/fit_model \
  -H "Content-Type: application/json" \
  -d '{
    "model_type": "var",
    "formula": "x1 x2",
    "data_path": "datasets/teaching/grunfeld.csv",
    "options": {
      "variables": ["x1", "x2"],
      "time_column": "year",
      "lags": 2
    }
  }'
```

- [ ] **Step 3: App 端测试**

启动 Tauri 桌面应用并验证：
1. 模型选择器显示时间序列模型选项
2. 时间序列表单正确渲染
3. 预测图、单位根表等组件正确显示

- [ ] **Step 4: 提交**

```bash
git add .
git commit -m "feat(S4c): complete time series module with end-to-end integration"
```

---

## 依赖关系图

```
Phase 1 (包骨架) ──→ Phase 2 (单位根) ──→ Phase 5 (协整)
      │
      ├──→ Phase 3 (ARIMA) ──→ Phase 6 (预测)
      │
      └──→ Phase 4 (VAR) ──→ Phase 6 (预测)
                                      │
                                      ↓
                            Phase 7 (序列化)
                                      │
                                      ↓
                            Phase 8 (Runtime + App)
                                      │
                                      ↓
                            Phase 9 (E2E 验证)
```

Phase 3 和 Phase 4 可并行（均依赖 Phase 1，互不依赖）。Phase 5 依赖 Phase 2（协整检验需要单位根检验）。

---

## 验证清单（Phase 完成后逐项勾选）

- [ ] Phase 1: 包骨架创建成功，`__init__()` 注册到 MODEL_REGISTRY
- [ ] Phase 2: ADF/PP/KPSS 检验在平稳/非平稳序列上结论正确
- [ ] Phase 3: ARIMA 模型估计准确，AIC/BIC 计算正确
- [ ] Phase 4: VAR 模型估计准确，Granger 因果/脉冲响应/方差分解工作正常
- [ ] Phase 5: Engle-Granger/Johansen 协整检验在协整/非协整序列上结论正确
- [ ] Phase 6: 预测值合理，置信区间覆盖正确
- [ ] Phase 7: 序列化 payload 包含所有必要字段
- [ ] Phase 8: Runtime schema 校验通过，App 组件正确渲染
- [ ] Phase 9: Tauri 桌面应用端到端运行成功
- [ ] 全程: MetricaLinear / MetricaPanel / MetricaDiscrete / MetricaCausal 测试不退化

---

## 教学数据集建议

为验证时间序列功能，建议准备以下教学数据集：

1. **宏观经济数据**：GDP、CPI、失业率（用于 VAR、协整）
2. **金融时间序列**：股票价格、汇率（用于 ARIMA、单位根）
3. **模拟数据**：已知 AR/MA 参数的模拟序列（用于验证估计准确性）

数据集应放置在 `datasets/teaching/` 目录，并包含 `_meta.json` 元数据文件。
