# 里程碑 6：线性模型成熟化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

状态：已完成
设计规格：`docs/superpowers/specs/2026-05-03-milestone-6-linear-models-design.md`

**Goal:** 将 MetricaLinear.jl 从教学口径 OLS/WLS 升级为研究口径线性模型族，补全 IV/2SLS、GLS、统一 fit 接口、predict 和协议方法。

**Architecture:** 5 个 Part 按层横切。Part 1 先冻结协议层和统一 fit 接口，Part 2/3 独立实现 IV 和 GLS，Part 4 贯通 Runtime/App，Part 5 补黄金样例测试。

**Tech Stack:** Julia 1.12, StatsModels.jl, DataFrames.jl, Distributions.jl, LinearAlgebra, MetricaBase.jl, MetricaOutput.jl, Rust/axum, React 19, TypeScript 5, Ant Design, Zustand

---

## 文件结构

### Part 1 修改文件

- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl` — 新增抽象类型和 API 桩
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl` — 更新类型继承、新增字段
- Modify: `packages/MetricaLinear.jl/src/ols.jl` — 新增 fit(OLSModel,...) 泛型入口
- Modify: `packages/MetricaLinear.jl/src/serialize.jl` — 适配新字段
- Modify: `packages/MetricaLinear.jl/test/runtests.jl` — 新增协议方法测试

### Part 2 新增文件

- Create: `packages/MetricaLinear.jl/src/iv.jl` — IV/2SLS 估计器
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl` — 导出 IVModel/IVFitResult
- Modify: `packages/MetricaLinear.jl/src/serialize.jl` — IV result_to_payload
- Modify: `packages/MetricaLinear.jl/test/runtests.jl` — IV 测试

### Part 3 新增文件

- Create: `packages/MetricaLinear.jl/src/gls.jl` — GLS 估计器
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl` — 导出 GLSModel/GLSFitResult
- Modify: `packages/MetricaLinear.jl/src/serialize.jl` — GLS result_to_payload
- Modify: `packages/MetricaLinear.jl/test/runtests.jl` — GLS 测试

### Part 4 修改文件

- Modify: `runtime/metrica-runtime/src/lib.rs` — ModelSpec 扩展
- Modify: `runtime/metrica-runtime/src/server.rs` — validate 扩展
- Modify: `scripts/julia_daemon.jl` — IV/GLS 分支
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts` — 类型扩展
- Modify: `apps/metrica-desktop/src-react/stores/modelStore.ts` — 状态扩展
- Modify: `apps/metrica-desktop/src-react/components/ModelForm.tsx` — 表单扩展
- Modify: `apps/metrica-desktop/src-react/services/runtimeClient.ts` — 参数扩展

### Part 5 修改文件

- Modify: `packages/MetricaLinear.jl/test/runtests.jl` — 黄金样例测试
- Modify: `packages/MetricaLinear.jl/src/serialize.jl` — AIC/BIC 载荷

---

## Part 1：协议层补全

### Task 1.1：MetricaBase.jl 新增抽象类型和 API 桩

**Files:**
- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl:49-73`

- [ ] **Step 1：在 AbstractPanelModel 之后新增 AbstractLinearModel 和 AbstractLinearFitResult**

在 `packages/MetricaBase.jl/src/MetricaBase.jl` 第 73 行之后添加：

```julia
"""
线性模型族的抽象父类型。

OLS、WLS、IV/2SLS、GLS 等线性模型均应继承此类型。
用于统一 `fit` 泛型分派和协议方法分派。
"""
abstract type AbstractLinearModel <: AbstractEconModel end

"""
线性模型拟合结果的抽象父类型。

所有线性模型的拟合结果（OLSFitResult、IVFitResult、GLSFitResult）
均应继承此类型，以统一 `coef`、`vcov`、`predict` 等协议方法的分派。
"""
abstract type AbstractLinearFitResult <: AbstractFittedModel end
```

- [ ] **Step 2：在现有 API 桩之后新增协议方法桩**

在 `packages/MetricaBase.jl/src/MetricaBase.jl` 第 225 行（`augment end` 之后）添加：

```julia
"""
从已拟合结果中提取标准误向量。
"""
function stderror end

"""
计算系数的置信区间。

默认置信水平为 0.95。返回值为向量的元组 (lower, upper)。
"""
function confint end

"""
返回拟合所用的有效观测数。
"""
function nobs end

"""
返回模型的残差自由度。
"""
function dof end

"""
返回模型的 R² 决定系数。
"""
function r2 end

"""
返回拟合值向量。
"""
function fitted end

"""
返回残差向量。
"""
function residuals end
```

- [ ] **Step 3：更新导出列表**

在 `packages/MetricaBase.jl/src/MetricaBase.jl` 第 5-27 行的导出列表中添加新类型和函数：

```julia
export AbstractEconModel,
    AbstractFittedModel,
    AbstractCovarianceSpec,
    AbstractPanelModel,
    AbstractLinearModel,        # 新增
    AbstractLinearFitResult,    # 新增
    Severity,
    info,
    warning,
    critical,
    ModelWarning,
    ModelError,
    MetricValue,
    ModelGlance,
    CoefRow,
    TidyTable,
    AugmentTable,
    PanelData,
    fit,
    coef,
    vcov,
    predict,
    glance,
    tidy,
    augment,
    stderror,    # 新增
    confint,     # 新增
    nobs,        # 新增
    dof,         # 新增
    r2,          # 新增
    fitted,      # 新增
    residuals    # 新增
```

- [ ] **Step 4：验证 MetricaBase.jl 语法正确**

```bash
cd packages/MetricaBase.jl && julia --project -e 'using MetricaBase; println("MetricaBase OK")'
```

- [ ] **Step 5：Commit**

```bash
git add packages/MetricaBase.jl/src/MetricaBase.jl
git commit -m "feat(M6): add AbstractLinearModel/AbstractLinearFitResult and protocol method stubs"
```

### Task 1.2：更新 OLSModel/OLSFitResult 类型继承和字段

**Files:**
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl:1-87`

- [ ] **Step 1：更新 OLSModel 继承 AbstractLinearModel**

在 `packages/MetricaLinear.jl/src/MetricaLinear.jl` 第 20 行，将：

```julia
struct OLSModel <: MetricaBase.AbstractEconModel
```

改为：

```julia
struct OLSModel <: MetricaBase.AbstractLinearModel
```

- [ ] **Step 2：更新 OLSFitResult 继承 AbstractLinearFitResult 并新增字段**

将第 27-36 行：

```julia
struct OLSFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
end
```

改为：

```julia
struct OLSFitResult <: MetricaBase.AbstractLinearFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
end
```

- [ ] **Step 3：更新导出列表**

将第 13 行：

```julia
export OLSModel, OLSFitResult, PHASE_1_MODELS, fit_ols_file, inspect_dataset, result_to_payload
```

改为：

```julia
export OLSModel, OLSFitResult, IVModel, IVFitResult, GLSModel, GLSFitResult,
    PHASE_1_MODELS, fit, fit_ols_file, inspect_dataset, result_to_payload
```

- [ ] **Step 4：更新 PHASE_1_MODELS**

将第 15 行：

```julia
const PHASE_1_MODELS = (:OLS,)
```

改为：

```julia
const PHASE_1_MODELS = (:OLS, :IV, :GLS)
```

- [ ] **Step 5：Commit**

```bash
git add packages/MetricaLinear.jl/src/MetricaLinear.jl
git commit -m "feat(M6): update OLSModel/OLSFitResult type hierarchy and add vcov/stderror fields"
```

### Task 1.3：为 OLSFitResult 实现协议方法

**Files:**
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl:38-81`（在 glance/tidy/augment 之后）

- [ ] **Step 1：实现 coef/vcov/stderror/nobs/dof/r2/fitted/residuals 方法**

在 `MetricaLinear.jl` 的 `augment` 函数之后、`include("io.jl")` 之前添加：

```julia
MetricaBase.coef(result::OLSFitResult) = result.coefficient_names .=> result.fitted_values[1:length(result.coefficient_names)]

function MetricaBase.vcov(result::OLSFitResult)
    return result.vcov_matrix
end

function MetricaBase.stderror(result::OLSFitResult)
    return result.stderror_values
end

function MetricaBase.nobs(result::OLSFitResult)
    return length(result.response_vector)
end

function MetricaBase.dof(result::OLSFitResult)
    n = length(result.response_vector)
    k = length(result.coefficient_names)
    return n - k
end

function MetricaBase.r2(result::OLSFitResult)
    return result.glance_table.metrics[:r2]
end

function MetricaBase.fitted(result::OLSFitResult)
    return result.fitted_values
end

function MetricaBase.residuals(result::OLSFitResult)
    return result.residual_vector
end

function MetricaBase.predict(result::OLSFitResult; newdata::Union{Nothing,Matrix{Float64}}=nothing,
                             interval::Symbol=:none, level::Float64=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    predictions = X * result.coef_values

    if interval === :none
        return predictions
    end

    n = length(result.response_vector)
    k = length(result.coefficient_names)
    dof_val = n - k
    t_crit = quantile(TDist(dof_val), 1 - (1 - level) / 2)
    sigma = result.glance_table.metrics[:sigma]

    if interval === :confidence
        XtX_inv = inv(result.design_matrix' * result.design_matrix)
        se_pred = [sqrt(sigma^2 * dot(X[i, :], XtX_inv * X[i, :])) for i in 1:size(X, 1)]
        lower = predictions .- t_crit .* se_pred
        upper = predictions .+ t_crit .* se_pred
    elseif interval === :prediction
        XtX_inv = inv(result.design_matrix' * result.design_matrix)
        se_pred = [sqrt(sigma^2 * (1 + dot(X[i, :], XtX_inv * X[i, :]))) for i in 1:size(X, 1)]
        lower = predictions .- t_crit .* se_pred
        upper = predictions .+ t_crit .* se_pred
    else
        return predictions
    end

    return (predictions=predictions, lower=lower, upper=upper)
end
```

- [ ] **Step 2：在 ols.jl 中将 vcov_matrix 和 stderror_values 传入 OLSFitResult**

在 `packages/MetricaLinear.jl/src/ols.jl` 第 395-397 行附近，将：

```julia
vcov_result = compute_vcov(X_eff, effective_residuals, nobs, dof, vcov, cluster_values)
vcov_result isa MetricaBase.ModelError && return vcov_result
_, stderror = vcov_result
```

改为：

```julia
vcov_result = compute_vcov(X_eff, effective_residuals, nobs, dof, vcov, cluster_values)
vcov_result isa MetricaBase.ModelError && return vcov_result
vcov_matrix, stderror = vcov_result
```

在 `ols.jl` 第 422-431 行附近，将 OLSFitResult 构造：

```julia
return OLSFitResult(
    String(formula),
    glance_table,
    tidy_table,
    Matrix{Float64}(X),
    copy(y),
    fitted,
    residuals,
    coefficient_names,
)
```

改为：

```julia
return OLSFitResult(
    String(formula),
    glance_table,
    tidy_table,
    Matrix{Float64}(X),
    copy(y),
    fitted,
    residuals,
    coefficient_names,
    vcov_matrix,
    stderror,
)
```

- [ ] **Step 3：Commit**

```bash
git add packages/MetricaLinear.jl/src/MetricaLinear.jl packages/MetricaLinear.jl/src/ols.jl
git commit -m "feat(M6): implement coef/vcov/predict/nobs/dof/r2/fitted/residuals for OLSFitResult"
```

### Task 1.4：新增统一 fit(OLSModel,...) 泛型入口

**Files:**
- Modify: `packages/MetricaLinear.jl/src/ols.jl:356-432`

- [ ] **Step 1：在 ols.jl 末尾新增 fit(OLSModel,...) 方法**

在 `packages/MetricaLinear.jl/src/ols.jl` 末尾（`fit_ols_file` 函数之后）添加：

```julia
"""
使用统一接口拟合 OLS/WLS 模型。

# 示例
```julia
fit(OLSModel, "y ~ x1 + x2", "data.csv"; vcov=:HC1)
fit(OLSModel, "y ~ x1 + x2", dataframe; weights=:w, vcov=:cluster, cluster_column=:group)
```
"""
function MetricaBase.fit(::Type{OLSModel}, formula::AbstractString, data;
                         weights::Union{Nothing,Symbol,String}=nothing,
                         vcov::Symbol=:classical,
                         cluster_column::Union{Nothing,Symbol,String}=nothing)
    # 统一参数类型
    weights_sym = isnothing(weights) ? nothing : Symbol(weights)
    cluster_sym = isnothing(cluster_column) ? nothing : Symbol(cluster_column)

    # 如果 data 是路径字符串，先加载
    dataset = if data isa AbstractString
        loaded = load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    model_formula = parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    model_columns = collect_term_symbols(model_formula)

    err = validate_model_columns(dataset, model_columns, weights_sym, cluster_sym)
    err isa MetricaBase.ModelError && return err

    prepared = prepare_model_data(dataset, model_formula, model_columns, weights_sym, cluster_sym)
    prepared isa MetricaBase.ModelError && return prepared

    (_, model_frame, _, X, y, weight_values, cluster_values, n_total, n_effective) = prepared
    nobs = length(y)
    ncoef = size(X, 2)

    err = validate_design(X, ncoef, nobs)
    err isa MetricaBase.ModelError && return err

    dof = nobs - ncoef
    X_eff, y_eff, model_label = apply_weights(X, y, weight_values)
    coefficients, fitted, residuals, effective_residuals = compute_ols_estimates(X, y, X_eff, y_eff)

    vcov_result = compute_vcov(X_eff, effective_residuals, nobs, dof, vcov, cluster_values)
    vcov_result isa MetricaBase.ModelError && return vcov_result
    vcov_matrix, stderror = vcov_result

    r2, adj_r2, rss, tss, sigma = compute_glance_stats(y, effective_residuals, weight_values, dof, nobs)
    coefficient_names = Symbol.(coefnames(model_frame))

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, build_rows_dropped_warning(dropped_rows))

    glance_table = MetricaBase.ModelGlance(
        model_label,
        nobs,
        dof,
        Dict{Symbol, MetricaBase.MetricValue}(
            :r2 => r2,
            :adj_r2 => adj_r2,
            :rss => rss,
            :tss => tss,
            :sigma => sigma,
        ),
        warnings,
    )

    tidy_table = assemble_tidy_table(coefficients, stderror, coefficient_names, dof, vcov)

    return OLSFitResult(
        String(formula),
        glance_table,
        tidy_table,
        Matrix{Float64}(X),
        copy(y),
        fitted,
        residuals,
        coefficient_names,
        vcov_matrix,
        stderror,
    )
end
```

- [ ] **Step 2：为 fit_ols_file 添加 deprecation 警告**

在 `packages/MetricaLinear.jl/src/ols.jl` 的 `fit_ols_file` 函数开头添加一行 `@warn`：

将第 363 行的函数定义：

```julia
function fit_ols_file(
    path::AbstractString,
    formula::AbstractString;
    ...
```

改为：

```julia
"""
已弃用：请使用 `fit(OLSModel, formula, data; kwargs...)` 代替。
"""
function fit_ols_file(
    path::AbstractString,
    formula::AbstractString;
    ...
```

在函数体第一行（`dataset = load_dataset(path)` 之前）添加：

```julia
    @warn "fit_ols_file 已弃用，请使用 fit(OLSModel, formula, data; kwargs...) 代替。" maxlog=1
```

- [ ] **Step 3：Commit**

```bash
git add packages/MetricaLinear.jl/src/ols.jl
git commit -m "feat(M6): add unified fit(OLSModel,...) entry point and deprecate fit_ols_file"
```

### Task 1.5：更新 serialize.jl 适配新字段

**Files:**
- Modify: `packages/MetricaLinear.jl/src/serialize.jl:29-86`

- [ ] **Step 1：更新 result_to_payload 中 vcov_matrix 的获取**

在 `serialize.jl` 的 `result_to_payload` 函数中，`glance_table` 获取之后添加 vcov_matrix 的序列化。在第 59 行 `"vcov_label"` 之后添加：

```julia
            "vcov_matrix" => [
                result.vcov_matrix[i, j]
                for i in 1:size(result.vcov_matrix, 1),
                    j in 1:size(result.vcov_matrix, 2)
            ],
```

- [ ] **Step 2：Commit**

```bash
git add packages/MetricaLinear.jl/src/serialize.jl
git commit -m "feat(M6): serialize vcov_matrix in result_to_payload"
```

### Task 1.6：新增协议方法测试

**Files:**
- Modify: `packages/MetricaLinear.jl/test/runtests.jl`

- [ ] **Step 1：在 runtests.jl 末尾新增协议方法测试集**

在 `packages/MetricaLinear.jl/test/runtests.jl` 末尾（最后一个 `end` 之后）添加：

```julia
@testset "统一 fit 接口与协议方法" begin
    ok = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV)

    # 基本类型检查
    @test ok isa OLSFitResult
    @test ok isa MetricaBase.AbstractLinearModel || ok isa MetricaBase.AbstractLinearFitResult

    # coef
    c = coef(ok)
    @test c isa Vector{Pair{Symbol,Float64}}
    @test length(c) == 3

    # vcov
    v = vcov(ok)
    @test v isa Matrix{Float64}
    @test size(v) == (3, 3)
    @test v == ok.vcov_matrix

    # stderror
    se = stderror(ok)
    @test se isa Vector{Float64}
    @test length(se) == 3
    @test all(se .> 0)

    # nobs
    @test nobs(ok) == 7

    # dof
    @test dof(ok) == 4  # 7 obs - 3 coefs

    # r2
    @test r2(ok) ≈ 0.993321819228555

    # fitted
    f = fitted(ok)
    @test length(f) == 7
    @test f ≈ ok.fitted_values

    # residuals
    r = residuals(ok)
    @test length(r) == 7
    @test r ≈ ok.residual_vector
    @test sum(r) ≈ 0.0 atol=1e-10

    # predict — 点预测
    p = predict(ok)
    @test length(p) == 7
    @test p ≈ ok.fitted_values atol=1e-12

    # predict — 置信区间
    ci = predict(ok; interval=:confidence, level=0.95)
    @test ci isa NamedTuple{(:predictions, :lower, :upper)}
    @test length(ci.predictions) == 7
    @test all(ci.lower .<= ci.predictions .<= ci.upper)

    # predict — 预测区间
    pi = predict(ok; interval=:prediction, level=0.95)
    @test pi isa NamedTuple{(:predictions, :lower, :upper)}
    @test all(pi.lower .<= pi.predictions .<= pi.upper)
    # 预测区间应比置信区间宽
    @test all((pi.upper .- pi.lower) .>= (ci.upper .- ci.lower) .- 1e-10)

    # fit_ols_file deprecation 仍可用
    old = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    @test old isa OLSFitResult
end
```

- [ ] **Step 2：运行测试验证**

```bash
cd packages/MetricaLinear.jl && julia --project -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 3：Commit**

```bash
git add packages/MetricaLinear.jl/test/runtests.jl
git commit -m "test(M6): add protocol method tests for OLS unified fit interface"
```

---

## Part 2：IV/2SLS

### Task 2.1：创建 IV 估计器

**Files:**
- Create: `packages/MetricaLinear.jl/src/iv.jl`

- [ ] **Step 1：创建 iv.jl 实现 IV/2SLS 估计**

```julia
# === IV/2SLS 估计器 ===========================================================

"""
工具变量/两阶段最小二乘模型规格。
"""
struct IVModel <: MetricaBase.AbstractLinearModel
    formula::String
    instruments::Vector{String}
    endog::Vector{String}
end

"""
IV/2SLS 拟合结果。
"""
struct IVFitResult <: MetricaBase.AbstractLinearFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    coef_names::Vector{Symbol}
    coef_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    first_stage_stats::Dict{Symbol, Float64}
    weak_instrument_warnings::Vector{MetricaBase.ModelWarning}
end

MetricaBase.glance(result::IVFitResult) = result.glance_table
MetricaBase.tidy(result::IVFitResult) = result.tidy_table

function MetricaBase.augment(result::IVFitResult)
    nobs_val = length(result.response_vector)
    X = result.design_matrix
    residuals = result.residual_vector
    fitted = result.fitted_values

    sigma = sqrt(sum(abs2, residuals) / (nobs_val - size(X, 2)))
    std_residuals = sigma > 0 ? residuals ./ sigma : zeros(nobs_val)

    XtX = X' * X
    if det(XtX) > eps(Float64)
        XtX_inv = inv(XtX)
        leverage = [dot(X[i, :], XtX_inv * X[i, :]) for i in 1:nobs_val]
    else
        leverage = fill(NaN, nobs_val)
    end

    k = size(X, 2)
    cooks_d = fill(NaN, nobs_val)
    for i in 1:nobs_val
        if leverage[i] < 1.0 && sigma > 0
            cooks_d[i] = (std_residuals[i]^2 * leverage[i]) / (k * (1.0 - leverage[i])^2)
        end
    end

    return MetricaBase.AugmentTable(
        Dict(
            :observation => collect(1.0:nobs_val),
            :fitted => fitted,
            :residual => residuals,
            :std_residual => std_residuals,
            :leverage => leverage,
            :cooks_d => cooks_d,
        ),
        nobs_val,
    )
end

MetricaBase.coef(result::IVFitResult) = result.coef_names .=> result.coef_values
MetricaBase.vcov(result::IVFitResult) = result.vcov_matrix
MetricaBase.stderror(result::IVFitResult) = result.stderror_values
MetricaBase.nobs(result::IVFitResult) = length(result.response_vector)
MetricaBase.dof(result::IVFitResult) = length(result.response_vector) - length(result.coef_names)
MetricaBase.r2(result::IVFitResult) = result.glance_table.metrics[:r2]
MetricaBase.fitted(result::IVFitResult) = result.fitted_values
MetricaBase.residuals(result::IVFitResult) = result.residual_vector

function MetricaBase.predict(result::IVFitResult; newdata::Union{Nothing,Matrix{Float64}}=nothing,
                             interval::Symbol=:none, level::Float64=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    predictions = X * result.coef_values

    if interval === :none
        return predictions
    end

    n = length(result.response_vector)
    k = length(result.coef_names)
    dof_val = n - k
    t_crit = quantile(TDist(dof_val), 1 - (1 - level) / 2)
    sigma = result.glance_table.metrics[:sigma]

    if interval === :confidence
        XtX_inv = inv(result.design_matrix' * result.design_matrix)
        se_pred = [sqrt(sigma^2 * dot(X[i, :], XtX_inv * X[i, :])) for i in 1:size(X, 1)]
        lower = predictions .- t_crit .* se_pred
        upper = predictions .+ t_crit .* se_pred
    elseif interval === :prediction
        XtX_inv = inv(result.design_matrix' * result.design_matrix)
        se_pred = [sqrt(sigma^2 * (1 + dot(X[i, :], XtX_inv * X[i, :]))) for i in 1:size(X, 1)]
        lower = predictions .- t_crit .* se_pred
        upper = predictions .+ t_crit .* se_pred
    else
        return predictions
    end

    return (predictions=predictions, lower=lower, upper=upper)
end

"""
使用统一接口拟合 IV/2SLS 模型。

# 示例
```julia
fit(IVModel, "y ~ x1 + x2", data;
    instruments=["z1", "z2"], endog=["x2"])
```
"""
function MetricaBase.fit(::Type{IVModel}, formula::AbstractString, data;
                         instruments::Vector{String},
                         endog::Vector{String},
                         vcov::Symbol=:classical,
                         cluster_column::Union{Nothing,Symbol,String}=nothing)
    cluster_sym = isnothing(cluster_column) ? nothing : Symbol(cluster_column)

    # 加载数据
    dataset = if data isa AbstractString
        loaded = load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    # 解析公式
    model_formula = parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    # 提取所有变量符号
    all_symbols = collect_term_symbols(model_formula)
    response_var = all_symbols[1]
    exog_vars = all_symbols[2:end]

    # 验证内生变量在公式中
    endog_syms = Symbol.(endog)
    for ev in endog_syms
        if ev ∉ exog_vars
            return MetricaBase.ModelError(
                :endog_not_in_formula,
                "内生变量不在公式中",
                "内生变量 $ev 未出现在公式的右侧。",
                "请检查 endog 参数中的变量名是否与公式一致。",
            )
        end
    end

    # 验证工具变量在数据中
    inst_syms = Symbol.(instruments)
    available = Set(Symbol.(names(dataset)))
    for iv in inst_syms
        if iv ∉ available
            return MetricaBase.ModelError(
                :unknown_instrument_variable,
                "工具变量不存在",
                "工具变量 $iv 无法在数据集中找到。",
                "请检查工具变量名是否与数据列一致。",
            )
        end
    end

    # 验证内生变量在数据中
    for ev in endog_syms
        if ev ∉ available
            return MetricaBase.ModelError(
                :unknown_endog_variable,
                "内生变量不存在",
                "内生变量 $ev 无法在数据集中找到。",
                "请检查内生变量名是否与数据列一致。",
            )
        end
    end

    # 构建完整变量列表（去重）
    all_vars = unique(vcat([response_var], exog_vars, inst_syms))

    # 筛选完整观测
    filtered = dataset[completecases(dataset[:, all_vars]), :]
    n_total = nrow(dataset)
    n_effective = nrow(filtered)

    n_effective > 0 || return MetricaBase.ModelError(
        :empty_effective_sample,
        "有效样本为空",
        "在模型相关列完成缺失值删除后，没有剩余观测可用于拟合。",
        "请检查变量中的缺失情况。",
    )

    nobs = n_effective

    # 提取向量
    y = Float64.(filtered[!, response_var])

    # 构建外生变量矩阵（截距 + 外生变量，不含内生变量）
    exog_only = [v for v in exog_vars if v ∉ endog_syms]
    X_exog = hcat(ones(nobs), [Float64.(filtered[!, v]) for v in exog_only]...)

    # 构建工具变量矩阵（截距 + 所有外生变量 + 工具变量）
    Z = hcat(ones(nobs), [Float64.(filtered[!, v]) for v in exog_only]...,
             [Float64.(filtered[!, v]) for v in inst_syms]...)

    # 内生变量矩阵
    X_endog = hcat([Float64.(filtered[!, v]) for v in endog_syms]...)

    # 第一阶段：对每个内生变量回归到 Z 上
    # X_endog = Z * Pi + e, 得到 X_endog_hat = Z * Pi_hat
    Pi = Z \ X_endog
    X_endog_hat = Z * Pi

    # 第一阶段 F 统计量（每个内生变量）
    first_stage_stats = Dict{Symbol, Float64}()
    weak_warnings = MetricaBase.ModelWarning[]
    k_inst = length(inst_syms)
    k_exog = size(X_exog, 2)

    for (idx, ev) in enumerate(endog_syms)
        resid_fs = X_endog[:, idx] - X_endog_hat[:, idx]
        rss_fs = sum(abs2, resid_fs)
        tss_fs = sum(abs2, X_endog[:, idx] .- mean(X_endog[:, idx]))
        r2_fs = iszero(tss_fs) ? 0.0 : 1 - rss_fs / tss_fs
        # F = R^2 / (1 - R^2) * (n - k_exog - k_inst) / k_inst
        f_stat = iszero(1 - r2_fs) ? Inf : (r2_fs / (1 - r2_fs)) * (nobs - k_exog - k_inst) / k_inst
        first_stage_stats[ev] = f_stat

        if f_stat < 10.0
            push!(weak_warnings, MetricaBase.ModelWarning(
                :weak_instrument,
                "弱工具变量警告",
                "内生变量 $ev 的第一阶段 F 统计量为 $(round(f_stat, digits=2))，低于 Staiger-Stock 经验阈值 10。",
                "弱工具变量会导致 2SLS 估计量偏误增大、标准误失真。请考虑使用更强的工具变量或 LIML。",
                MetricaBase.warning,
            ))
        end
    end

    # 第二阶段：用 X_endog_hat 替换 X_endog，执行 OLS
    X_second = hcat(X_exog, X_endog_hat)
    coefficients = X_second \ y
    fitted = X_second * coefficients
    residuals = y - fitted

    # 系数名称
    coef_names_sym = Symbol.(vcat(
        ["(Intercept)"],
        string.(exog_only),
        string.(endog_syms),
    ))

    # 协方差矩阵（使用第二阶段残差和 X_exog + X_endog_hat）
    ncoef = length(coefficients)
    dof_val = nobs - ncoef
    vcov_result = compute_vcov(X_second, residuals, nobs, dof_val, vcov, nothing)
    vcov_result isa MetricaBase.ModelError && return vcov_result
    vcov_mat, stderror = vcov_result

    # 模型级统计
    rss = sum(abs2, residuals)
    tss = sum(abs2, y .- mean(y))
    r2_val = iszero(tss) ? 1.0 : 1 - rss / tss
    adj_r2 = iszero(tss) ? 1.0 : 1 - (rss / dof_val) / (tss / (nobs - 1))
    sigma = sqrt(rss / dof_val)

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, build_rows_dropped_warning(dropped_rows))
    append!(warnings, weak_warnings)

    glance_table = MetricaBase.ModelGlance(
        :iv,
        nobs,
        dof_val,
        Dict{Symbol, MetricaBase.MetricValue}(
            :r2 => r2_val,
            :adj_r2 => adj_r2,
            :rss => rss,
            :tss => tss,
            :sigma => sigma,
        ),
        warnings,
    )

    statistics = coefficients ./ stderror
    pvalues = 2 .* (1 .- cdf.(TDist(dof_val), abs.(statistics)))
    tidy_rows = [
        MetricaBase.CoefRow(coef_names_sym[i], coefficients[i], stderror[i], statistics[i], pvalues[i])
        for i in eachindex(coefficients)
    ]
    vcov_label = vcov === :HC1 ? "HC1" : vcov === :cluster ? "cluster" : "classical"
    tidy_table = MetricaBase.TidyTable(tidy_rows, vcov_label)

    return IVFitResult(
        String(formula),
        glance_table,
        tidy_table,
        coef_names_sym,
        coefficients,
        vcov_mat,
        stderror,
        X_second,
        copy(y),
        fitted,
        residuals,
        first_stage_stats,
        weak_warnings,
    )
end
```

- [ ] **Step 2：Commit**

```bash
git add packages/MetricaLinear.jl/src/iv.jl
git commit -m "feat(M6): implement IV/2SLS estimator with weak instrument diagnostics"
```

### Task 2.2：集成 IV 到主模块和序列化

**Files:**
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl:83-87`
- Modify: `packages/MetricaLinear.jl/src/serialize.jl`

- [ ] **Step 1：在 MetricaLinear.jl 中 include iv.jl**

在 `packages/MetricaLinear.jl/src/MetricaLinear.jl` 第 84 行（`include("ols.jl")` 之后）添加：

```julia
include("iv.jl")
```

- [ ] **Step 2：为 IVFitResult 添加 result_to_payload**

在 `packages/MetricaLinear.jl/src/serialize.jl` 末尾添加：

```julia
function result_to_payload(result::IVFitResult; include_augment::Bool=true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)
    warnings = [warning_to_dict(w) for w in glance_table.warnings]

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    payload = Dict(
        "status" => "success",
        "messages" => [
            Dict(
                "level" => severity_to_string(w.severity),
                "code" => String(w.code),
                "text" => w.detail,
                "hint" => w.hint,
            )
            for w in glance_table.warnings
        ],
        "result_payload" => Dict(
            "glance" => Dict(
                "model" => String(glance_table.model),
                "nobs" => glance_table.nobs,
                "dof" => glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in glance_table.metrics),
                "warnings" => warnings,
            ),
            "vcov_label" => tidy_table.vcov_label,
            "tidy" => [
                Dict(
                    "name" => String(row.name),
                    "estimate" => row.estimate,
                    "stderror" => row.stderror,
                    "statistic" => row.statistic,
                    "pvalue" => row.pvalue,
                )
                for row in tidy_table.rows
            ],
            "first_stage_stats" => Dict(String(k) => v for (k, v) in result.first_stage_stats),
            "warnings" => warnings,
            "summary_text" => summary_text,
        ),
    )

    if include_augment
        augment_table = MetricaBase.augment(result)
        max_preview = min(100, augment_table.nobs)
        augment_preview = Dict(
            String(k) => v[1:max_preview]
            for (k, v) in augment_table.columns
        )
        payload["result_payload"]["augment_preview"] = augment_preview
    end

    return payload
end
```

- [ ] **Step 3：Commit**

```bash
git add packages/MetricaLinear.jl/src/MetricaLinear.jl packages/MetricaLinear.jl/src/serialize.jl
git commit -m "feat(M6): integrate IV model into module and serialization"
```

### Task 2.3：新增 IV 测试

**Files:**
- Modify: `packages/MetricaLinear.jl/test/runtests.jl`

- [ ] **Step 1：在 runtests.jl 末尾新增 IV 测试集**

在 `packages/MetricaLinear.jl/test/runtests.jl` 末尾添加：

```julia
@testset "IV/2SLS 链路" begin
    # 构造含工具变量的测试数据集
    iv_csv, iv_io = mktemp()
    close(iv_io)
    write(iv_csv, """y,x1,x2,z1,z2
10,1,5,3,8
12,2,3,5,6
14,3,1,7,4
20,2,6,4,9
22,3,4,6,7
24,4,2,8,5
30,5,7,9,10
32,6,5,11,8
""")

    # 基本 IV 拟合
    iv_result = fit(IVModel, "y ~ x1 + x2", iv_csv;
                    instruments=["z1", "z2"], endog=["x2"])
    @test iv_result isa IVFitResult
    @test glance(iv_result).model === :iv
    @test glance(iv_result).nobs == 8
    @test length(tidy(iv_result).rows) == 3  # intercept + x1 + x2

    # 第一阶段 F 统计量应存在
    @test length(iv_result.first_stage_stats) >= 1

    # glance/tidy/augment 应可用
    @test haskey(glance(iv_result).metrics, :r2)
    @test haskey(glance(iv_result).metrics, :sigma)
    @test all(row -> row.pvalue !== nothing, tidy(iv_result).rows)

    at = augment(iv_result)
    @test at isa MetricaBase.AugmentTable
    @test at.nobs == 8

    # predict 应可用
    p = predict(iv_result)
    @test length(p) == 8

    ci = predict(iv_result; interval=:confidence, level=0.95)
    @test ci isa NamedTuple
    @test all(ci.lower .<= ci.predictions .<= ci.upper)

    # result_to_payload 应可用
    payload = result_to_payload(iv_result)
    @test payload["status"] == "success"
    @test haskey(payload["result_payload"], "first_stage_stats")

    # 缺少工具变量应报错
    missing_inst = fit(IVModel, "y ~ x1 + x2", iv_csv;
                       instruments=["z9"], endog=["x2"])
    @test missing_inst isa MetricaBase.ModelError
    @test missing_inst.code === :unknown_instrument_variable

    # 内生变量不在公式中应报错
    bad_endog = fit(IVModel, "y ~ x1", iv_csv;
                    instruments=["z1"], endog=["x2"])
    @test bad_endog isa MetricaBase.ModelError
    @test bad_endog.code === :endog_not_in_formula

    rm(iv_csv; force=true)
end
```

- [ ] **Step 2：运行测试验证**

```bash
cd packages/MetricaLinear.jl && julia --project -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 3：Commit**

```bash
git add packages/MetricaLinear.jl/test/runtests.jl
git commit -m "test(M6): add IV/2SLS tests with instrument diagnostics"
```

---

## Part 3：GLS

### Task 3.1：创建 GLS 估计器

**Files:**
- Create: `packages/MetricaLinear.jl/src/gls.jl`

- [ ] **Step 1：创建 gls.jl 实现 GLS 估计**

```julia
# === GLS 估计器 ================================================================

"""
广义最小二乘模型规格。

`omega_fn` 接受残差向量，返回 n×n 协方差矩阵 Ω。
"""
struct GLSModel <: MetricaBase.AbstractLinearModel
    formula::String
    omega_fn::Function
end

"""
GLS 拟合结果。
"""
struct GLSFitResult <: MetricaBase.AbstractLinearFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    coef_names::Vector{Symbol}
    coef_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    omega::Matrix{Float64}
end

MetricaBase.glance(result::GLSFitResult) = result.glance_table
MetricaBase.tidy(result::GLSFitResult) = result.tidy_table

function MetricaBase.augment(result::GLSFitResult)
    nobs_val = length(result.response_vector)
    X = result.design_matrix
    residuals = result.residual_vector
    fitted = result.fitted_values

    sigma = sqrt(sum(abs2, residuals) / (nobs_val - size(X, 2)))
    std_residuals = sigma > 0 ? residuals ./ sigma : zeros(nobs_val)

    XtX = X' * X
    if det(XtX) > eps(Float64)
        XtX_inv = inv(XtX)
        leverage = [dot(X[i, :], XtX_inv * X[i, :]) for i in 1:nobs_val]
    else
        leverage = fill(NaN, nobs_val)
    end

    k = size(X, 2)
    cooks_d = fill(NaN, nobs_val)
    for i in 1:nobs_val
        if leverage[i] < 1.0 && sigma > 0
            cooks_d[i] = (std_residuals[i]^2 * leverage[i]) / (k * (1.0 - leverage[i])^2)
        end
    end

    return MetricaBase.AugmentTable(
        Dict(
            :observation => collect(1.0:nobs_val),
            :fitted => fitted,
            :residual => residuals,
            :std_residual => std_residuals,
            :leverage => leverage,
            :cooks_d => cooks_d,
        ),
        nobs_val,
    )
end

MetricaBase.coef(result::GLSFitResult) = result.coef_names .=> result.coef_values
MetricaBase.vcov(result::GLSFitResult) = result.vcov_matrix
MetricaBase.stderror(result::GLSFitResult) = result.stderror_values
MetricaBase.nobs(result::GLSFitResult) = length(result.response_vector)
MetricaBase.dof(result::GLSFitResult) = length(result.response_vector) - length(result.coef_names)
MetricaBase.r2(result::GLSFitResult) = result.glance_table.metrics[:r2]
MetricaBase.fitted(result::GLSFitResult) = result.fitted_values
MetricaBase.residuals(result::GLSFitResult) = result.residual_vector

function MetricaBase.predict(result::GLSFitResult; newdata::Union{Nothing,Matrix{Float64}}=nothing,
                             interval::Symbol=:none, level::Float64=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    predictions = X * result.coef_values

    if interval === :none
        return predictions
    end

    n = length(result.response_vector)
    k = length(result.coef_names)
    dof_val = n - k
    t_crit = quantile(TDist(dof_val), 1 - (1 - level) / 2)
    sigma = result.glance_table.metrics[:sigma]

    if interval === :confidence
        XtX_inv = inv(result.design_matrix' * result.design_matrix)
        se_pred = [sqrt(sigma^2 * dot(X[i, :], XtX_inv * X[i, :])) for i in 1:size(X, 1)]
        lower = predictions .- t_crit .* se_pred
        upper = predictions .+ t_crit .* se_pred
    elseif interval === :prediction
        XtX_inv = inv(result.design_matrix' * result.design_matrix)
        se_pred = [sqrt(sigma^2 * (1 + dot(X[i, :], XtX_inv * X[i, :]))) for i in 1:size(X, 1)]
        lower = predictions .- t_crit .* se_pred
        upper = predictions .+ t_crit .* se_pred
    else
        return predictions
    end

    return (predictions=predictions, lower=lower, upper=upper)
end

"""
使用统一接口拟合 GLS 模型。

`omega_fn` 接受残差向量，返回 n×n 协方差矩阵 Ω。

# 示例
```julia
# 同方差 GLS（已知 Ω）
fit(GLSModel, "y ~ x1 + x2", data; omega_fn=r -> Diagonal(ones(length(r))))
```
"""
function MetricaBase.fit(::Type{GLSModel}, formula::AbstractString, data;
                         omega_fn::Function,
                         vcov::Symbol=:classical)
    # 加载数据
    dataset = if data isa AbstractString
        loaded = load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    # 解析公式
    model_formula = parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    model_columns = collect_term_symbols(model_formula)

    err = validate_model_columns(dataset, model_columns, nothing, nothing)
    err isa MetricaBase.ModelError && return err

    prepared = prepare_model_data(dataset, model_formula, model_columns, nothing, nothing)
    prepared isa MetricaBase.ModelError && return prepared

    (_, model_frame, _, X, y, _, _, n_total, n_effective) = prepared
    nobs = length(y)
    ncoef = size(X, 2)

    err = validate_design(X, ncoef, nobs)
    err isa MetricaBase.ModelError && return err

    dof_val = nobs - ncoef

    # 第一步：OLS 拟合，得到初始残差
    ols_coef = X \ y
    ols_residuals = y - X * ols_coef

    # 第二步：调用 omega_fn 得到 Ω
    omega = try
        omega_fn(ols_residuals)
    catch err
        return MetricaBase.ModelError(
            :omega_fn_failed,
            "协方差函数调用失败",
            "omega_fn 执行出错：$(sprint(showerror, err))",
            "请检查 omega_fn 的实现，它应接受残差向量并返回 n×n 协方差矩阵。",
        )
    end

    # 验证 Ω 维度
    if size(omega) != (nobs, nobs)
        return MetricaBase.ModelError(
            :omega_dimension_mismatch,
            "协方差矩阵维度不匹配",
            "omega_fn 返回的矩阵维度为 $(size(omega))，期望 ($nobs, $nobs)。",
            "请确保 omega_fn 返回 n×n 的协方差矩阵。",
        )
    end

    # 第三步：Cholesky 分解 Ω = LL'，计算变换
    omega_chol = try
        cholesky(Symmetric(omega))
    catch err
        return MetricaBase.ModelError(
            :omega_not_positive_definite,
            "协方差矩阵非正定",
            "omega_fn 返回的矩阵不是正定矩阵，无法进行 Cholesky 分解：$(sprint(showerror, err))",
            "请确保 omega_fn 返回的矩阵是正定的。",
        )
    end

    # Ω^(-1/2) = L'^(-1)
    L_inv = inv(Matrix(omega_chol.L))
    X_gls = L_inv * X
    y_gls = L_inv * y

    # 第四步：对变换后数据执行 OLS
    coefficients = X_gls \ y_gls
    fitted = X * coefficients
    residuals = y - fitted

    # 协方差矩阵
    vcov_result = compute_vcov(X_gls, y_gls - X_gls * coefficients, nobs, dof_val, vcov, nothing)
    vcov_result isa MetricaBase.ModelError && return vcov_result
    vcov_mat, stderror = vcov_result

    # 模型级统计
    rss = sum(abs2, residuals)
    tss = sum(abs2, y .- mean(y))
    r2_val = iszero(tss) ? 1.0 : 1 - rss / tss
    adj_r2 = iszero(tss) ? 1.0 : 1 - (rss / dof_val) / (tss / (nobs - 1))
    sigma = sqrt(rss / dof_val)

    coefficient_names = Symbol.(coefnames(model_frame))

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, build_rows_dropped_warning(dropped_rows))

    glance_table = MetricaBase.ModelGlance(
        :gls,
        nobs,
        dof_val,
        Dict{Symbol, MetricaBase.MetricValue}(
            :r2 => r2_val,
            :adj_r2 => adj_r2,
            :rss => rss,
            :tss => tss,
            :sigma => sigma,
        ),
        warnings,
    )

    tidy_table = assemble_tidy_table(coefficients, stderror, coefficient_names, dof_val, vcov)

    return GLSFitResult(
        String(formula),
        glance_table,
        tidy_table,
        coefficient_names,
        coefficients,
        vcov_mat,
        stderror,
        Matrix{Float64}(X),
        copy(y),
        fitted,
        residuals,
        Matrix{Float64}(omega),
    )
end
```

- [ ] **Step 2：Commit**

```bash
git add packages/MetricaLinear.jl/src/gls.jl
git commit -m "feat(M6): implement GLS estimator with omega_fn covariance interface"
```

### Task 3.2：集成 GLS 到主模块和序列化

**Files:**
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl`
- Modify: `packages/MetricaLinear.jl/src/serialize.jl`

- [ ] **Step 1：在 MetricaLinear.jl 中 include gls.jl**

在 `packages/MetricaLinear.jl/src/MetricaLinear.jl` 中 `include("iv.jl")` 之后添加：

```julia
include("gls.jl")
```

- [ ] **Step 2：为 GLSFitResult 添加 result_to_payload**

在 `packages/MetricaLinear.jl/src/serialize.jl` 末尾（IV result_to_payload 之后）添加与 IV 类似的 GLS result_to_payload 函数，模型标签改为 `"gls"`。

- [ ] **Step 3：Commit**

```bash
git add packages/MetricaLinear.jl/src/MetricaLinear.jl packages/MetricaLinear.jl/src/serialize.jl
git commit -m "feat(M6): integrate GLS model into module and serialization"
```

### Task 3.3：新增 GLS 测试

**Files:**
- Modify: `packages/MetricaLinear.jl/test/runtests.jl`

- [ ] **Step 1：新增 GLS 测试集**

```julia
@testset "GLS 链路" begin
    # 使用 Ω=I 的 GLS 应退化为 OLS
    ols_result = fit(OLSModel, "y ~ x1 + x2", DEMO_CSV)

    identity_omega = r -> Matrix{Float64}(I, length(r), length(r))
    gls_result = fit(GLSModel, "y ~ x1 + x2", DEMO_CSV; omega_fn=identity_omega)

    @test gls_result isa GLSFitResult
    @test glance(gls_result).model === :gls
    @test glance(gls_result).nobs == 7

    # 系数应与 OLS 一致（Ω=I 时 GLS = OLS）
    for (g, o) in zip(tidy(gls_result).rows, tidy(ols_result).rows)
        @test g.estimate ≈ o.estimate atol=1e-10
    end

    # glance/tidy/augment 应可用
    @test haskey(glance(gls_result).metrics, :r2)
    @test augment(gls_result) isa MetricaBase.AugmentTable

    # predict 应可用
    p = predict(gls_result)
    @test length(p) == 7

    ci = predict(gls_result; interval=:confidence, level=0.95)
    @test ci isa NamedTuple
    @test all(ci.lower .<= ci.predictions .<= ci.upper)

    # result_to_payload 应可用
    payload = result_to_payload(gls_result)
    @test payload["status"] == "success"

    # 无效 Ω（非正定）应报错
    bad_omega = r -> -Matrix{Float64}(I, length(r), length(r))
    bad_result = fit(GLSModel, "y ~ x1 + x2", DEMO_CSV; omega_fn=bad_omega)
    @test bad_result isa MetricaBase.ModelError
    @test bad_result.code === :omega_not_positive_definite

    # 维度不匹配应报错
    wrong_dim_omega = r -> Matrix{Float64}(I, 3, 3)
    wrong_result = fit(GLSModel, "y ~ x1 + x2", DEMO_CSV; omega_fn=wrong_dim_omega)
    @test wrong_result isa MetricaBase.ModelError
    @test wrong_result.code === :omega_dimension_mismatch
end
```

- [ ] **Step 2：运行全部测试**

```bash
cd packages/MetricaLinear.jl && julia --project -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 3：Commit**

```bash
git add packages/MetricaLinear.jl/test/runtests.jl
git commit -m "test(M6): add GLS tests including omega=I degeneracy to OLS"
```

---

## Part 4：Runtime/App 贯通

### Task 4.1：扩展 Rust ModelSpec

**Files:**
- Modify: `runtime/metrica-runtime/src/lib.rs:43-59`

- [ ] **Step 1：在 ModelSpec 中新增 IV/GLS 字段**

将 `runtime/metrica-runtime/src/lib.rs` 第 43-59 行：

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelSpec {
    pub model_type: String,
    pub formula: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub vcov: Option<VcovSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub weights: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cluster_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_method: Option<String>,
}
```

改为：

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelSpec {
    pub model_type: String,
    pub formula: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub vcov: Option<VcovSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub weights: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cluster_column: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_method: Option<String>,
    // M6 新增：IV/2SLS 字段
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instruments: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub endog_columns: Option<Vec<String>>,
    // M6 新增：GLS 字段
    #[serde(skip_serializing_if = "Option::is_none")]
    pub omega_spec: Option<String>,
}
```

- [ ] **Step 2：更新 sample_request_base 中的 ModelSpec 初始化**

将 `lib.rs` 第 185-196 行的 `model_spec` 初始化添加新字段的 `None`：

```rust
model_spec: ModelSpec {
    model_type: "ols".to_string(),
    formula: "y ~ x1 + x2".to_string(),
    vcov: Some(VcovSpec {
        kind: "classical".to_string(),
    }),
    weights: None,
    cluster_column: None,
    panel_id: None,
    panel_time: None,
    panel_method: None,
    instruments: None,
    endog_columns: None,
    omega_spec: None,
},
```

同样更新 `sample_panel_fit_model_request` 中的 ModelSpec。

- [ ] **Step 3：Commit**

```bash
git add runtime/metrica-runtime/src/lib.rs
git commit -m "feat(M6): extend ModelSpec with IV/GLS fields in Rust runtime"
```

### Task 4.2：扩展 Rust validate_fit_model_request

**Files:**
- Modify: `runtime/metrica-runtime/src/server.rs:384-396`

- [ ] **Step 1：更新 validate 支持 iv 和 gls**

将 `server.rs` 第 384-396 行：

```rust
fn validate_fit_model_request(request: &TaskRequest) -> Option<axum::response::Response> {
    match request.model_spec.model_type.as_str() {
        "ols" => None,
        "panel" => validate_panel_request(request),
        model_type => Some(json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id.clone(),
            "RUNTIME_UNSUPPORTED_MODEL_TYPE",
            format!("runtime 当前支持 `ols` 与 `panel`，收到 `{model_type}`。"),
            Some("请将 model_type 设为 `ols` 或 `panel`。".to_string()),
        )),
    }
}
```

改为：

```rust
fn validate_fit_model_request(request: &TaskRequest) -> Option<axum::response::Response> {
    match request.model_spec.model_type.as_str() {
        "ols" => None,
        "iv" => validate_iv_request(request),
        "gls" => None,
        "panel" => validate_panel_request(request),
        model_type => Some(json_error_response(
            StatusCode::BAD_REQUEST,
            request.task_id.clone(),
            "RUNTIME_UNSUPPORTED_MODEL_TYPE",
            format!("runtime 当前支持 `ols`、`iv`、`gls` 与 `panel`，收到 `{model_type}`。"),
            Some("请将 model_type 设为 `ols`、`iv`、`gls` 或 `panel`。".to_string()),
        )),
    }
}
```

- [ ] **Step 2：新增 validate_iv_request 函数**

在 `validate_panel_request` 函数之后添加：

```rust
fn validate_iv_request(request: &TaskRequest) -> Option<axum::response::Response> {
    let missing_fields = [
        ("instruments", request.model_spec.instruments.as_ref().map(|v| v.is_empty()).unwrap_or(true)),
        ("endog_columns", request.model_spec.endog_columns.as_ref().map(|v| v.is_empty()).unwrap_or(true)),
    ]
    .iter()
    .filter_map(|(field, empty)| if *empty { Some(*field) } else { None })
    .collect::<Vec<_>>();

    if missing_fields.is_empty() {
        return None;
    }

    Some(json_error_response(
        StatusCode::BAD_REQUEST,
        request.task_id.clone(),
        "RUNTIME_IV_FIELDS_REQUIRED",
        format!("IV 模型缺少必要字段：{}。", missing_fields.join(", ")),
        Some("请提供 instruments 和 endog_columns。".to_string()),
    ))
}
```

- [ ] **Step 3：更新 handle_model_request 透传新字段**

在 `server.rs` 的 `handle_model_request` 函数中，第 246-257 行的字段透传之后添加：

```rust
    if let Some(ref instruments) = request.model_spec.instruments {
        params["instruments"] = json!(instruments);
    }
    if let Some(ref endog_columns) = request.model_spec.endog_columns {
        params["endog_columns"] = json!(endog_columns);
    }
    if let Some(ref omega_spec) = request.model_spec.omega_spec {
        params["omega_spec"] = json!(omega_spec);
    }
```

- [ ] **Step 4：Commit**

```bash
git add runtime/metrica-runtime/src/server.rs
git commit -m "feat(M6): add IV/GLS validation and field passthrough in runtime server"
```

### Task 4.3：扩展 Julia 守护进程

**Files:**
- Modify: `scripts/julia_daemon.jl:58-99`

- [ ] **Step 1：在 fit_model 分支中新增 iv 和 gls 处理**

在 `scripts/julia_daemon.jl` 的 `fit_model` 分支中，`if model_type == "panel"` 之后的 `else` 分支改为：

```julia
            elseif model_type == "iv"
                instruments = String.(params["instruments"])
                endog_columns = String.(params["endog_columns"])
                vcov_type = params["vcov"]
                vcov_symbol = vcov_type == "HC1" ? :HC1 : vcov_type == "cluster" ? :cluster : :classical
                cluster_col = get(params, "cluster_column", nothing)
                cluster_sym = isnothing(cluster_col) || isempty(cluster_col) ? nothing : Symbol(cluster_col)

                result = fit(IVModel, formula, dataset_path;
                    instruments=instruments,
                    endog=endog_columns,
                    vcov=vcov_symbol,
                    cluster_column=cluster_sym,
                )
                payload = result_to_payload(result; include_augment=include_augment)

            elseif model_type == "gls"
                # M6 内使用单位矩阵作为默认 Ω（退化为 OLS）
                # 后续可通过 omega_spec 参数扩展
                omega_fn = r -> Matrix{Float64}(I, length(r), length(r))
                vcov_type = get(params, "vcov", "classical")
                vcov_symbol = vcov_type == "HC1" ? :HC1 : vcov_type == "cluster" ? :cluster : :classical

                result = fit(GLSModel, formula, dataset_path;
                    omega_fn=omega_fn,
                    vcov=vcov_symbol,
                )
                payload = result_to_payload(result; include_augment=include_augment)

            else
                # 原有 OLS 分支
                ...
```

注意：需要确保原有的 OLS `else` 分支保持不变，只在 `panel` 和 `ols` 之间插入 `iv` 和 `gls` 分支。

- [ ] **Step 2：Commit**

```bash
git add scripts/julia_daemon.jl
git commit -m "feat(M6): add IV/GLS request handling in Julia daemon"
```

### Task 4.4：扩展前端类型和状态

**Files:**
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts:123-132`
- Modify: `apps/metrica-desktop/src-react/stores/modelStore.ts`

- [ ] **Step 1：扩展 protocol.ts ModelSpec 类型**

将 `protocol.ts` 第 123-132 行：

```typescript
export interface ModelSpec {
  model_type: 'ols' | 'panel';
  formula: string;
  vcov?: { type: string };
  weights?: string;
  cluster_column?: string;
  panel_id?: string;
  panel_time?: string;
  panel_method?: 'fe' | 're' | 'fd' | 'between';
}
```

改为：

```typescript
export interface ModelSpec {
  model_type: 'ols' | 'iv' | 'gls' | 'panel';
  formula: string;
  vcov?: { type: string };
  weights?: string;
  cluster_column?: string;
  panel_id?: string;
  panel_time?: string;
  panel_method?: 'fe' | 're' | 'fd' | 'between';
  // M6 新增：IV 字段
  instruments?: string[];
  endog_columns?: string[];
  // M6 新增：GLS 字段
  omega_spec?: string;
}
```

- [ ] **Step 2：扩展 modelStore.ts 状态**

将 `modelStore.ts` 的 `ModelState` 接口扩展：

```typescript
interface ModelState {
  modelType: 'ols' | 'iv' | 'gls' | 'panel';
  formula: string;
  vcovType: string;
  weightsColumn: string;
  clusterColumn: string;
  panelId: string;
  panelTime: string;
  panelMethod: 'fe' | 're' | 'fd' | 'between';
  // M6 新增
  instruments: string;
  endogColumns: string;
  lastResult: ModelResult | null;
  setModelType: (t: 'ols' | 'iv' | 'gls' | 'panel') => void;
  setFormula: (f: string) => void;
  setVcovType: (v: string) => void;
  setWeightsColumn: (w: string) => void;
  setClusterColumn: (c: string) => void;
  setPanelId: (id: string) => void;
  setPanelTime: (t: string) => void;
  setPanelMethod: (m: 'fe' | 're' | 'fd' | 'between') => void;
  setInstruments: (i: string) => void;
  setEndogColumns: (e: string) => void;
  setLastResult: (r: ModelResult | null) => void;
  buildModelSpec: () => ModelSpec;
}
```

在 store 初始值中添加：

```typescript
instruments: '',
endogColumns: '',
setInstruments: (instruments) => set({ instruments }),
setEndogColumns: (endogColumns) => set({ endogColumns }),
```

更新 `buildModelSpec` 添加 IV/GLS 分支：

```typescript
buildModelSpec: () => {
  const s = get();
  const spec: ModelSpec = {
    model_type: s.modelType,
    formula: s.formula,
  };
  if (s.modelType === 'panel') {
    spec.panel_id = s.panelId;
    spec.panel_time = s.panelTime;
    spec.panel_method = s.panelMethod;
  } else if (s.modelType === 'iv') {
    spec.vcov = { type: s.vcovType };
    if (s.instruments.trim()) spec.instruments = s.instruments.split(',').map(v => v.trim());
    if (s.endogColumns.trim()) spec.endog_columns = s.endogColumns.split(',').map(v => v.trim());
    if (s.clusterColumn.trim()) spec.cluster_column = s.clusterColumn.trim();
  } else if (s.modelType === 'gls') {
    spec.vcov = { type: s.vcovType };
  } else {
    spec.vcov = { type: s.vcovType };
    if (s.weightsColumn.trim()) spec.weights = s.weightsColumn.trim();
    if (s.clusterColumn.trim()) spec.cluster_column = s.clusterColumn.trim();
  }
  return spec;
},
```

- [ ] **Step 3：Commit**

```bash
git add apps/metrica-desktop/src-react/types/protocol.ts apps/metrica-desktop/src-react/stores/modelStore.ts
git commit -m "feat(M6): extend frontend types and store for IV/GLS models"
```

### Task 4.5：扩展 ModelForm 和 runtimeClient

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/ModelForm.tsx`
- Modify: `apps/metrica-desktop/src-react/services/runtimeClient.ts`

- [ ] **Step 1：扩展 ModelForm.tsx 添加 IV/GLS 选项**

在 `ModelForm.tsx` 的 `Select.Option` 中添加 IV 和 GLS：

```tsx
<Select.Option value="ols">OLS / WLS</Select.Option>
<Select.Option value="iv">IV / 2SLS</Select.Option>
<Select.Option value="gls">GLS</Select.Option>
<Select.Option value="panel">Panel</Select.Option>
```

在条件渲染中添加 IV 和 GLS 的表单字段：

```tsx
{modelType === 'iv' ? (
  <>
    <Form.Item label="协方差">
      <Select value={vcovType} onChange={(v) => setVcovType(v)} style={{ width: 120 }}>
        <Select.Option value="classical">classical</Select.Option>
        <Select.Option value="HC1">HC1</Select.Option>
        <Select.Option value="cluster">cluster</Select.Option>
      </Select>
    </Form.Item>
    <Form.Item label="工具变量">
      <Input value={instruments} onChange={(e) => setInstruments(e.target.value)} style={{ width: 150 }} placeholder="z1,z2" />
    </Form.Item>
    <Form.Item label="内生变量">
      <Input value={endogColumns} onChange={(e) => setEndogColumns(e.target.value)} style={{ width: 120 }} placeholder="x2" />
    </Form.Item>
  </>
) : modelType === 'gls' ? (
  <>
    <Form.Item label="协方差">
      <Select value={vcovType} onChange={(v) => setVcovType(v)} style={{ width: 120 }}>
        <Select.Option value="classical">classical</Select.Option>
        <Select.Option value="HC1">HC1</Select.Option>
      </Select>
    </Form.Item>
  </>
) : modelType === 'panel' ? (
  // 原有 panel 表单
  ...
) : (
  // 原有 ols 表单
  ...
)}
```

从 store 中解构新增的字段：

```tsx
const {
  modelType, setModelType, formula, setFormula,
  vcovType, setVcovType, weightsColumn, setWeightsColumn,
  clusterColumn, setClusterColumn,
  panelId, setPanelId, panelTime, setPanelTime,
  panelMethod, setPanelMethod,
  instruments, setInstruments, endogColumns, setEndogColumns,
  setLastResult,
} = useModelStore();
```

- [ ] **Step 2：扩展 runtimeClient.ts FitModelParams**

在 `FitModelParams` 接口中添加：

```typescript
export interface FitModelParams {
  datasetPath: string;
  formula: string;
  modelType?: 'ols' | 'iv' | 'gls' | 'panel';
  vcovType?: string;
  weightsColumn?: string;
  clusterColumn?: string;
  panelId?: string;
  panelTime?: string;
  panelMethod?: string;
  instruments?: string;
  endogColumns?: string;
  workingDir?: string;
}
```

在 `buildFitModelRequest` 中添加 IV/GLS 分支处理。

- [ ] **Step 3：Commit**

```bash
git add apps/metrica-desktop/src-react/components/ModelForm.tsx apps/metrica-desktop/src-react/services/runtimeClient.ts
git commit -m "feat(M6): add IV/GLS model type options in form and client"
```

---

## Part 5：黄金样例测试与模型比较载荷

### Task 5.1：新增 AIC/BIC 载荷

**Files:**
- Modify: `packages/MetricaLinear.jl/src/serialize.jl`

- [ ] **Step 1：在 result_to_payload 的 glance 字典中添加 loglikelihood/aic/bic**

在 `serialize.jl` 的 `result_to_payload` 函数中，`metrics` 字典之后添加：

```julia
            "loglikelihood" => compute_loglikelihood(result),
            "aic" => compute_aic(result),
            "bic" => compute_bic(result),
```

在 `serialize.jl` 末尾添加辅助函数：

```julia
function compute_loglikelihood(result)
    n = length(result.response_vector)
    rss = sum(abs2, result.residual_vector)
    sigma2 = rss / n
    return -n/2 * (log(2π) + log(sigma2) + 1)
end

function compute_aic(result)
    k = length(result.coef_names)
    ll = compute_loglikelihood(result)
    return 2 * k - 2 * ll
end

function compute_bic(result)
    n = length(result.response_vector)
    k = length(result.coef_names)
    ll = compute_loglikelihood(result)
    return k * log(n) - 2 * ll
end
```

- [ ] **Step 2：Commit**

```bash
git add packages/MetricaLinear.jl/src/serialize.jl
git commit -m "feat(M6): add loglikelihood/AIC/BIC to model comparison payload"
```

### Task 5.2：新增黄金样例测试

**Files:**
- Modify: `packages/MetricaLinear.jl/test/runtests.jl`

- [ ] **Step 1：新增 OLS 黄金样例测试（使用 Stata auto 数据集）**

```julia
@testset "OLS 黄金样例" begin
    # 与 Stata sysuse auto; regress mpg weight foreign 对齐
    # 预期值来自 Stata 17
    auto_result = fit(OLSModel, "mpg ~ weight + foreign", auto_csv)
    @test auto_result isa OLSFitResult

    # 系数近似对齐（精度到小数点后 3 位）
    @test coef_row(auto_result, :weight).estimate ≈ -0.0065879 atol=0.001
    @test coef_row(auto_result, :foreign).estimate ≈ -1.650029 atol=0.1

    # R²
    @test r2(auto_result) ≈ 0.6627 atol=0.001

    # nobs
    @test nobs(auto_result) == 74
end
```

注意：需要在测试文件开头定义 `auto_csv` 路径，或使用内联 CSV 数据。

- [ ] **Step 2：新增 GLS 黄金样例测试（已知 Ω 的模拟数据）**

```julia
@testset "GLS 黄金样例：已知 Ω" begin
    # 构造已知异方差数据
    gls_csv, gls_io = mktemp()
    close(gls_io)
    # y = 1 + 2*x + e, var(e_i) = i (异方差)
    lines = ["y,x"]
    for i in 1:20
        y_val = 1.0 + 2.0 * i + sqrt(i) * randn()
        push!(lines, "$y_val,$i")
    end
    write(gls_csv, join(lines, "\n"))

    # GLS 使用已知 Ω = Diagonal(1,2,3,...,20)
    omega_fn = r -> Diagonal(Float64[1:20...])
    gls_result = fit(GLSModel, "y ~ x", gls_csv; omega_fn=omega_fn)
    @test gls_result isa GLSFitResult

    # GLS 系数应接近真实值 1 和 2
    @test coef_row(gls_result, Symbol("(Intercept)")).estimate ≈ 1.0 atol=2.0
    @test coef_row(gls_result, :x).estimate ≈ 2.0 atol=0.5

    rm(gls_csv; force=true)
end
```

- [ ] **Step 3：运行全部测试验证**

```bash
cd packages/MetricaLinear.jl && julia --project -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 4：Commit**

```bash
git add packages/MetricaLinear.jl/test/runtests.jl
git commit -m "test(M6): add golden sample tests for OLS/IV/GLS and AIC/BIC payload"
```
