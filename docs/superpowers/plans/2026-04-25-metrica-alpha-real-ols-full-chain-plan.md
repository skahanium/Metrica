# Metrica Alpha 真实 OLS 全链路 Implementation Plan

> **状态：当前活跃主计划。** Julia 端最小可用 OLS 已先行收口；当前直接目标是继续完成“最小真实全链路前端”，即 `App -> Runtime -> Julia -> 结构化结果 -> App` 的真实打通。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 Metrica 当前阶段最核心的真实主链路：本地 CSV 导入、真实数据检查、真实 OLS 拟合、结构化结果、通过 Runtime 触发的桌面渲染与教学友好警告。

**Architecture:** 以 `MetricaBase.jl` 作为结构化协议边界，以 `MetricaLinear.jl` 实现真实数据检查与 OLS 流水线，以 Rust Runtime 通过 Julia CLI 子进程桥接真实执行，并由桌面端消费结构化 JSON 渲染最小用户流。先统一文档锚点，再按 TDD 从 Core 到 Runtime 到 App 逐层打通，避免 mock 路线与真实路线混用。

**Tech Stack:** Julia, CSV.jl, DataFrames.jl, StatsModels.jl, LinearAlgebra, Statistics, Rust, serde, Tauri shell scaffold, HTML, CSS, JavaScript

---

## 文件结构

当前执行说明：

- `packages/MetricaLinear.jl` 的最小可用 OLS 已先完成
- `scripts/run_minimal_ols.jl` 仅作为包层手工验证入口，不得升级为前端正式调用路径
- 当前实施重点转向 Runtime 真实桥接与 App 最小真实结果页

- Modify: `docs/superpowers/plans/2026-04-24-metrica-alpha-vertical-slice-plan.md`
- Create: `docs/superpowers/plans/2026-04-25-metrica-alpha-real-ols-full-chain-plan.md`
- Modify: `docs/architecture/runtime-protocol.md`
- Modify: `packages/MetricaBase.jl/Project.toml`
- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl`
- Modify: `packages/MetricaBase.jl/test/runtests.jl`
- Modify: `packages/MetricaLinear.jl/Project.toml`
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl`
- Modify: `packages/MetricaLinear.jl/test/runtests.jl`
- Create: `packages/MetricaLinear.jl/src/io.jl`
- Create: `packages/MetricaLinear.jl/src/ols.jl`
- Create: `packages/MetricaLinear.jl/src/serialize.jl`
- Create: `runtime/metrica-runtime/src/julia_bridge.rs`
- Modify: `runtime/metrica-runtime/src/lib.rs`
- Modify: `runtime/metrica-runtime/src/main.rs`
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`
- Modify: `apps/metrica-desktop/index.html`
- Modify: `apps/metrica-desktop/src/main.js`
- Modify: `apps/metrica-desktop/src/runtime-client.js`
- Modify: `apps/metrica-desktop/src/result-view.js`
- Modify: `apps/metrica-desktop/src/styles.css`
- Modify: `apps/metrica-desktop/data/demo.csv`

## Task 1: 统一文档锚点，停止旧 mock 计划继续扩散

**Files:**
- Modify: `docs/superpowers/plans/2026-04-24-metrica-alpha-vertical-slice-plan.md`
- Modify: `docs/architecture/runtime-protocol.md`

- [ ] **Step 1: 写会先失败的文档一致性检查清单**

在工作记录中建立本任务检查表，要求最终同时满足：

```text
1. 旧 alpha plan 明确标注为已被真实 OLS 全链路 plan 取代
2. runtime-protocol 明确当前 alpha 为真实 Julia 子进程链路
3. 不再出现 fit_ols_demo 作为当前推荐路径
```

- [ ] **Step 2: 更新旧 alpha plan 的状态说明**

将 `docs/superpowers/plans/2026-04-24-metrica-alpha-vertical-slice-plan.md` 开头说明替换为：

```md
> **状态：已被后续真实实现计划细化。** 本文件保留为早期 alpha 垂直切片实施草案，其中 `fit_ols_demo` 与示例载荷路线不再作为当前实施依据。当前活跃实施计划为 `docs/superpowers/plans/2026-04-25-metrica-alpha-real-ols-full-chain-plan.md`。
```

- [ ] **Step 3: 在 Runtime 协议文档中固定当前执行路线**

在 `docs/architecture/runtime-protocol.md` 的 “Alpha 垂直切片” 段落后追加：

```md
当前活跃实现路线补充约束：

- `fit_model` 必须通过 Runtime 调用 Julia 子进程真实执行
- 成功响应中的 `glance` 与 `tidy` 来自真实 OLS 拟合结果
- `fit_ols_demo` 或纯示例载荷不得作为当前 alpha 完成标准
```

- [ ] **Step 4: 目视检查文档是否仍出现旧路线作为当前依据**

Run: `rg -n "fit_ols_demo|示例载荷路线不再作为当前实施依据|当前活跃实施计划" docs/superpowers/plans docs/architecture/runtime-protocol.md`

Expected:

```text
命中旧 plan 的历史说明，以及新的活跃计划说明；不再出现把 fit_ols_demo 当作当前目标的上下文。
```

- [ ] **Step 5: 提交文档锚点修正**

```bash
git add docs/superpowers/plans/2026-04-24-metrica-alpha-vertical-slice-plan.md docs/architecture/runtime-protocol.md
git commit -m "docs: align alpha plan with real ols chain"
```

## Task 2: 固化 Base 协议，让真实链路有稳定结构化边界

**Files:**
- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl`
- Modify: `packages/MetricaBase.jl/test/runtests.jl`

- [ ] **Step 1: 写 Base 协议失败测试，覆盖错误与警告载荷**

将以下测试加入 `packages/MetricaBase.jl/test/runtests.jl`：

```julia
using Test
using MetricaBase

@testset "结构化错误与警告契约" begin
    dropped = ModelWarning(
        :rows_dropped,
        "缺失值删样",
        "因模型相关列存在缺失值，已删除 2 行。",
        "请检查变量中的缺失模式。",
        info,
    )

    singular = ModelError(
        :singular_design,
        "设计矩阵奇异",
        "预测变量之间存在完全线性相关，模型无法估计。",
        "请移除冗余变量后重试。",
    )

    glance = ModelGlance(
        :ols,
        8,
        5,
        Dict(:r2 => 0.84, :adj_r2 => 0.79, :rss => 1.2, :tss => 7.5, :sigma => 0.49),
        [dropped],
    )

    tidy = TidyTable(
        [
            CoefRow(:Intercept, 1.0, 0.1, 10.0, 0.001),
            CoefRow(:x1, 2.0, 0.2, 10.0, 0.001),
        ],
        "classical",
    )

    @test dropped.severity === info
    @test singular.code === :singular_design
    @test haskey(glance.metrics, :adj_r2)
    @test tidy.rows[1].name === :Intercept
end
```

- [ ] **Step 2: 运行 Base 测试看失败形态**

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaBase.jl -e "using Pkg; Pkg.test()"`

Expected:

```text
若当前协议未完整暴露 error/severity/metrics 语义，则测试失败并指出缺失点。
```

- [ ] **Step 3: 最小修正 Base 导出与类型说明**

确保 `packages/MetricaBase.jl/src/MetricaBase.jl` 至少稳定导出以下名称：

```julia
export AbstractEconModel,
    AbstractFittedModel,
    AbstractCovarianceSpec,
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
    fit,
    coef,
    vcov,
    predict,
    glance,
    tidy,
    augment
```

- [ ] **Step 4: 重新运行 Base 测试**

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaBase.jl -e "using Pkg; Pkg.test()"`

Expected:

```text
Base 协议测试通过，说明后续 Runtime 与 App 可依赖这些结构化类型。
```

- [ ] **Step 5: 提交 Base 协议稳定化**

```bash
git add packages/MetricaBase.jl/src/MetricaBase.jl packages/MetricaBase.jl/test/runtests.jl
git commit -m "feat: stabilize base result protocol"
```

## Task 3: 接入 Julia 依赖并写出真实 OLS 流水线的失败测试

**Files:**
- Modify: `packages/MetricaLinear.jl/Project.toml`
- Modify: `packages/MetricaLinear.jl/test/runtests.jl`
- Modify: `apps/metrica-desktop/data/demo.csv`

- [ ] **Step 1: 准备稳定 demo 数据集**

将 `apps/metrica-desktop/data/demo.csv` 调整为一个能覆盖正常拟合与缺失值删样的最小数据集，例如：

```csv
y,x1,x2
10,1,5
12,2,4
13,3,3
15,4,2
18,5,1
20,6,
22,7,0
24,8,-1
```

- [ ] **Step 2: 在 Linear 包测试中写真实链路失败测试**

将以下测试加入 `packages/MetricaLinear.jl/test/runtests.jl`：

```julia
using Test
using MetricaBase
using MetricaLinear

const DEMO_CSV = joinpath(dirname(dirname(dirname(@__DIR__))), "apps", "metrica-desktop", "data", "demo.csv")

@testset "真实 OLS 链路" begin
    ok = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    @test ok isa OLSFitResult
    @test glance(ok).model === :ols
    @test glance(ok).nobs == 7
    @test haskey(glance(ok).metrics, :r2)
    @test length(tidy(ok).rows) == 3
    @test any(w -> w.code === :rows_dropped, glance(ok).warnings)

    missing_col = fit_ols_file(DEMO_CSV, "y ~ x9")
    @test missing_col isa ModelError
    @test missing_col.code === :unknown_variable
end
```

- [ ] **Step 3: 添加奇异矩阵失败测试**

继续在 `packages/MetricaLinear.jl/test/runtests.jl` 追加：

```julia
@testset "奇异矩阵与空样本" begin
    singular_csv = mktemp()[1]
    write(singular_csv, "y,x1,x2\n1,1,2\n2,2,4\n3,3,6\n")

    singular = fit_ols_file(singular_csv, "y ~ x1 + x2")
    @test singular isa ModelError
    @test singular.code === :singular_design

    empty_csv = mktemp()[1]
    write(empty_csv, "y,x1\n,\n,\n")

    empty_result = fit_ols_file(empty_csv, "y ~ x1")
    @test empty_result isa ModelError
    @test empty_result.code === :empty_effective_sample
end
```

- [ ] **Step 4: 添加 Project 依赖**

在 `packages/MetricaLinear.jl/Project.toml` 中加入：

```toml
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57a-5684-b7b6-d8193f3e46c0"
Distributions = "31c24e10-a181-5473-b8eb-7969acd0382f"
JSON3 = "0f8b85d8-7281-11e9-16c4-1f6f6cea4b9e"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
StatsModels = "3eaba693-59b7-5ba5-a881-562e759f1c8d"
Statistics = "10745b16-91a9-54dd-bb5e-69e4d38afc55"
MetricaBase = "9f6ff2ae-77f1-47e1-8d02-c1542b05cf6b"
```

- [ ] **Step 5: 运行 Linear 测试并确认失败在缺失实现处**

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaLinear.jl -e "using Pkg; Pkg.test()"`

Expected:

```text
失败，提示 fit_ols_file 或相关方法未定义。
```

- [ ] **Step 6: 提交测试与依赖脚手架**

```bash
git add packages/MetricaLinear.jl/Project.toml packages/MetricaLinear.jl/test/runtests.jl apps/metrica-desktop/data/demo.csv
git commit -m "test: define real ols slice expectations"
```

## Task 4: 实现 MetricaLinear 的数据加载、公式矩阵与 OLS 求解

**Files:**
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl`
- Create: `packages/MetricaLinear.jl/src/io.jl`
- Create: `packages/MetricaLinear.jl/src/ols.jl`
- Create: `packages/MetricaLinear.jl/src/serialize.jl`

- [ ] **Step 1: 在主模块声明拆分文件与公开入口**

将 `packages/MetricaLinear.jl/src/MetricaLinear.jl` 调整为：

```julia
module MetricaLinear

using CSV
using DataFrames
using LinearAlgebra
using Statistics
using StatsModels
using MetricaBase

export OLSModel, OLSFitResult, PHASE_1_MODELS, fit_ols_file

const PHASE_1_MODELS = (:OLS,)

struct OLSModel <: MetricaBase.AbstractEconModel
    formula::String
end

struct OLSFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
end

MetricaBase.glance(result::OLSFitResult) = result.glance_table
MetricaBase.tidy(result::OLSFitResult) = result.tidy_table

include("io.jl")
include("ols.jl")
include("serialize.jl")

end
```

- [ ] **Step 2: 实现数据加载与缺失值筛除**

在 `packages/MetricaLinear.jl/src/io.jl` 中写入：

```julia
function load_dataset(path::AbstractString)
    isfile(path) || return MetricaBase.ModelError(
        :dataset_not_found,
        "数据文件不存在",
        "指定的 CSV 文件不存在，无法读取数据。",
        "请确认文件路径后重试。",
    )

    try
        return CSV.read(path, DataFrame)
    catch err
        return MetricaBase.ModelError(
            :csv_parse_failed,
            "CSV 解析失败",
            "CSV 文件无法被正确解析：$(sprint(showerror, err))",
            "请检查分隔符、表头与编码是否正确。",
        )
    end
end
```

- [ ] **Step 3: 实现 OLS 求解与错误分层**

在 `packages/MetricaLinear.jl/src/ols.jl` 中写入最小真实实现：

```julia
function fit_ols_file(path::AbstractString, formula::AbstractString)
    dataset = load_dataset(path)
    dataset isa MetricaBase.ModelError && return dataset

    f = try
        StatsModels.Term(:y) # 占位，下一步替换为真实 parse
    catch
        nothing
    end

    schema_formula = try
        Meta.parse("@formula($(formula))")
    catch err
        return MetricaBase.ModelError(
            :formula_parse_failed,
            "公式解析失败",
            "无法解析公式字符串：$(sprint(showerror, err))",
            "请使用如 y ~ x1 + x2 的公式格式。",
        )
    end

    model_formula = eval(schema_formula)

    try
        mf = ModelFrame(model_formula, dataset, model=StatisticalModel)
        mm = ModelMatrix(mf)
        y = response(mf)
        X = mm.m

        keep = .!(ismissing.(y))
        if !all(keep)
            y = y[keep]
            X = X[keep, :]
        end

        nobs = length(y)
        nobs > 0 || return MetricaBase.ModelError(
            :empty_effective_sample,
            "有效样本为空",
            "在缺失值处理后，没有可用于拟合模型的观测。",
            "请检查模型变量中的缺失情况。",
        )

        rank(X) == size(X, 2) || return MetricaBase.ModelError(
            :singular_design,
            "设计矩阵奇异",
            "预测变量之间存在完全线性相关，模型无法估计。",
            "请移除冗余变量后重试。",
        )

        β = X \ y
        residuals = y - X * β
        dof = nobs - size(X, 2)
        dof > 0 || return MetricaBase.ModelError(
            :insufficient_degrees_of_freedom,
            "自由度不足",
            "有效样本量不足以支撑当前模型参数个数。",
            "请减少参数数量或增加样本。",
        )

        rss = sum(abs2, residuals)
        ybar = mean(y)
        tss = sum(abs2, y .- ybar)
        sigma2 = rss / dof
        vcov = sigma2 * inv(transpose(X) * X)
        stderror = sqrt.(diag(vcov))
        stats = β ./ stderror

        glance_metrics = Dict(
            :r2 => 1 - rss / tss,
            :adj_r2 => 1 - (rss / dof) / (tss / (nobs - 1)),
            :rss => rss,
            :tss => tss,
            :sigma => sqrt(sigma2),
        )

        warning_rows = MetricaBase.ModelWarning[]
        if nrow(dataset) != nobs
            push!(warning_rows, MetricaBase.ModelWarning(
                :rows_dropped,
                "缺失值删样",
                "因模型相关列存在缺失值，已删除 $(nrow(dataset) - nobs) 行。",
                "请检查模型变量中的缺失模式。",
                MetricaBase.info,
            ))
        end

        coef_names = Symbol.(coefnames(mf))
        tidy_rows = [
            MetricaBase.CoefRow(coef_names[i], β[i], stderror[i], stats[i], nothing)
            for i in eachindex(β)
        ]

        return OLSFitResult(
            String(formula),
            MetricaBase.ModelGlance(:ols, nobs, dof, glance_metrics, warning_rows),
            MetricaBase.TidyTable(tidy_rows, "classical"),
        )
    catch err
        return MetricaBase.ModelError(
            :unknown_variable,
            "模型变量不存在",
            "公式中的变量无法在数据集中解析：$(sprint(showerror, err))",
            "请检查公式中的变量名是否与数据列一致。",
        )
    end
end
```

- [ ] **Step 4: 运行 Linear 测试并修正最小失败**

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaLinear.jl -e "using Pkg; Pkg.test()"`

Expected:

```text
大部分测试开始通过；若 StatsModels 公式构造或 p 值缺失引起失败，报错将定位到单一实现点。
```

- [ ] **Step 5: 将 p 值计算补齐并避免把所有异常都误标为 unknown_variable**

在 `packages/MetricaLinear.jl/src/ols.jl` 中收紧异常分支：

```julia
using Distributions

pvalues = 2 .* (1 .- cdf.(TDist(dof), abs.(stats)))

tidy_rows = [
    MetricaBase.CoefRow(coef_names[i], β[i], stderror[i], stats[i], pvalues[i])
    for i in eachindex(β)
]
```

并将异常捕获拆分为“公式/列不存在”和“其他拟合失败”两个分支。

- [ ] **Step 6: 重新运行 Linear 测试直至通过**

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaLinear.jl -e "using Pkg; Pkg.test()"`

Expected:

```text
真实 OLS、删样 warning、未知变量、奇异矩阵、空样本测试全部通过。
```

- [ ] **Step 7: 提交真实 OLS 内核**

```bash
git add packages/MetricaLinear.jl/src/MetricaLinear.jl packages/MetricaLinear.jl/src/io.jl packages/MetricaLinear.jl/src/ols.jl packages/MetricaLinear.jl/src/serialize.jl packages/MetricaLinear.jl/test/runtests.jl packages/MetricaLinear.jl/Project.toml
git commit -m "feat: implement real ols pipeline"
```

## Task 5: 为 Julia 结果提供稳定 JSON 输出入口

**Files:**
- Create: `packages/MetricaLinear.jl/src/serialize.jl`
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl`

- [ ] **Step 1: 写序列化失败测试**

在 `packages/MetricaLinear.jl/test/runtests.jl` 中追加：

```julia
@testset "序列化输出" begin
    result = fit_ols_file(DEMO_CSV, "y ~ x1 + x2")
    payload = result_to_payload(result)
    @test payload["status"] == "success"
    @test haskey(payload["result_payload"], "glance")
    @test haskey(payload["result_payload"], "tidy")
    @test length(payload["messages"]) >= 1
end
```

- [ ] **Step 2: 运行测试确认缺少 result_to_payload**

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaLinear.jl -e "using Pkg; Pkg.test()"`

Expected:

```text
失败，提示 result_to_payload 未定义。
```

- [ ] **Step 3: 实现成功/错误结果到 JSON 友好字典的转换**

在 `packages/MetricaLinear.jl/src/serialize.jl` 中写入：

```julia
function warning_to_dict(w::MetricaBase.ModelWarning)
    Dict(
        "code" => String(w.code),
        "title" => w.title,
        "detail" => w.detail,
        "hint" => something(w.hint, ""),
        "severity" => String(Symbol(w.severity)),
    )
end

function error_to_payload(err::MetricaBase.ModelError)
    Dict(
        "status" => "error",
        "messages" => [
            Dict(
                "level" => "error",
                "code" => String(err.code),
                "text" => err.detail,
                "hint" => something(err.hint, ""),
            ),
        ],
    )
end

function result_to_payload(result::OLSFitResult)
    gl = MetricaBase.glance(result)
    td = MetricaBase.tidy(result)

    Dict(
        "status" => "success",
        "messages" => [
            Dict(
                "level" => "info",
                "code" => String(w.code),
                "text" => w.detail,
                "hint" => something(w.hint, ""),
            ) for w in gl.warnings
        ],
        "result_payload" => Dict(
            "glance" => Dict(
                "model" => String(gl.model),
                "nobs" => gl.nobs,
                "dof" => gl.dof,
                "metrics" => Dict(String(k) => v for (k, v) in gl.metrics),
                "warnings" => [warning_to_dict(w) for w in gl.warnings],
            ),
            "tidy" => [
                Dict(
                    "name" => String(row.name),
                    "estimate" => row.estimate,
                    "stderror" => row.stderror,
                    "statistic" => row.statistic,
                    "pvalue" => row.pvalue,
                ) for row in td.rows
            ],
            "warnings" => [warning_to_dict(w) for w in gl.warnings],
        ),
    )
end

result_to_payload(err::MetricaBase.ModelError) = error_to_payload(err)
```

- [ ] **Step 4: 运行 Linear 测试验证序列化通过**

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaLinear.jl -e "using Pkg; Pkg.test()"`

Expected:

```text
序列化测试通过，成功与错误结果都可转为 Runtime 可消费的字典结构。
```

- [ ] **Step 5: 提交序列化层**

```bash
git add packages/MetricaLinear.jl/src/serialize.jl packages/MetricaLinear.jl/test/runtests.jl packages/MetricaLinear.jl/src/MetricaLinear.jl
git commit -m "feat: serialize ols results for runtime"
```

## Task 6: 让 Runtime 真实调用 Julia 子进程而不是返回样例

**Files:**
- Create: `runtime/metrica-runtime/src/julia_bridge.rs`
- Modify: `runtime/metrica-runtime/src/lib.rs`
- Modify: `runtime/metrica-runtime/src/main.rs`
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`

- [ ] **Step 1: 写 Runtime 集成失败测试**

将以下测试加入 `runtime/metrica-runtime/tests/vertical_slice.rs`：

```rust
use metrica_runtime::{execute_fit_model, sample_fit_model_request};

#[test]
fn fit_model_returns_real_payload_shape() {
    let request = sample_fit_model_request();
    let response = execute_fit_model(&request).expect("runtime response");

    assert_eq!(response.status, "success");
    let payload = response.result_payload.expect("payload");
    assert!(payload.get("glance").is_some());
    assert!(payload.get("tidy").is_some());
}
```

- [ ] **Step 2: 运行 Runtime 测试确认缺少执行桥**

Run: `cargo test --manifest-path /Users/skahanium/Metrica/runtime/metrica-runtime/Cargo.toml`

Expected:

```text
失败，提示 execute_fit_model 未定义或仍返回样例响应。
```

- [ ] **Step 3: 提取 Julia 子进程桥**

在 `runtime/metrica-runtime/src/julia_bridge.rs` 中写入：

```rust
use std::process::{Command, Stdio};

use serde_json::Value;

use crate::{Message, TaskRequest, TaskResponse};

pub fn execute_fit_model(request: &TaskRequest) -> Result<TaskResponse, String> {
    let request_json = serde_json::to_string(request).map_err(|err| err.to_string())?;
    let output = Command::new("julia")
        .arg("--project=/Users/skahanium/Metrica/packages/MetricaLinear.jl")
        .arg("-e")
        .arg("using JSON3, MetricaLinear; println(\"not-implemented\")")
        .stdin(Stdio::null())
        .output()
        .map_err(|err| format!("failed to launch julia: {err}"))?;

    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).to_string());
    }

    let parsed: Value =
        serde_json::from_slice(&output.stdout).map_err(|err| format!("invalid json: {err}"))?;

    Ok(TaskResponse {
        task_id: request.task_id.clone(),
        status: parsed["status"].as_str().unwrap_or("error").to_string(),
        messages: vec![Message {
            level: "info".to_string(),
            code: "RUNTIME_FORWARDED".to_string(),
            text: request_json,
            hint: None,
        }],
        artifacts: Some(vec![]),
        result_payload: parsed.get("result_payload").cloned(),
    })
}
```

- [ ] **Step 4: 用真实 Julia 调用替换占位命令**

把 `-e` 脚本替换为真正读取请求并调用 `fit_ols_file/result_to_payload` 的版本，并让 `messages` 保留 Julia 返回的消息而不是 `RUNTIME_FORWARDED` 占位。

- [ ] **Step 5: 在 `lib.rs` 中导出执行入口并收紧错误分层**

确保 `runtime/metrica-runtime/src/lib.rs` 提供：

```rust
pub mod julia_bridge;

pub use julia_bridge::execute_fit_model;
```

并在执行失败时返回：

```rust
TaskResponse {
    task_id: request.task_id.clone(),
    status: "error".to_string(),
    messages: vec![Message {
        level: "error".to_string(),
        code: "RUNTIME_JULIA_EXECUTION_FAILED".to_string(),
        text: err,
        hint: Some("请检查 Julia 环境、依赖安装与请求参数。".to_string()),
    }],
    artifacts: None,
    result_payload: None,
}
```

- [ ] **Step 6: 运行 Runtime 测试直至通过**

Run: `cargo test --manifest-path /Users/skahanium/Metrica/runtime/metrica-runtime/Cargo.toml`

Expected:

```text
Runtime 测试通过，说明 fit_model 已通过 Julia 子进程返回真实结构化结果。
```

- [ ] **Step 7: 提交 Runtime 真实桥接**

```bash
git add runtime/metrica-runtime/src/julia_bridge.rs runtime/metrica-runtime/src/lib.rs runtime/metrica-runtime/src/main.rs runtime/metrica-runtime/tests/vertical_slice.rs
git commit -m "feat: bridge runtime to julia ols execution"
```

## Task 7: 让桌面端真正发起运行并渲染结构化结果

**Files:**
- Modify: `apps/metrica-desktop/index.html`
- Modify: `apps/metrica-desktop/src/main.js`
- Modify: `apps/metrica-desktop/src/styles.css`

- [ ] **Step 1: 写前端最小 DOM 验收清单**

建立以下验收清单并据此实现页面：

```text
1. 能选择或显示 demo CSV 路径
2. 能输入公式
3. 点击运行后有 loading 状态
4. 成功后渲染 glance 和 tidy
5. 有 warnings 时单独渲染提示区
6. 失败时渲染错误区与 hint
```

- [ ] **Step 2: 更新 `index.html` 提供最小结构**

将主体结构调整为：

```html
<main class="app-shell">
  <section class="panel controls">
    <h1>Metrica Alpha OLS</h1>
    <label>CSV 文件</label>
    <input id="dataset-path" type="text" />
    <label>公式</label>
    <input id="formula" type="text" value="y ~ x1 + x2" />
    <button id="run-model">运行模型</button>
    <p id="status-text"></p>
  </section>
  <section class="panel results">
    <div id="error-box"></div>
    <div id="warning-box"></div>
    <div id="glance-box"></div>
    <table id="tidy-table"></table>
  </section>
</main>
```

- [ ] **Step 3: 写最小交互与渲染逻辑**

将 `apps/metrica-desktop/src/main.js` 实现为：

```javascript
const datasetInput = document.getElementById("dataset-path");
const formulaInput = document.getElementById("formula");
const runButton = document.getElementById("run-model");
const statusText = document.getElementById("status-text");
const errorBox = document.getElementById("error-box");
const warningBox = document.getElementById("warning-box");
const glanceBox = document.getElementById("glance-box");
const tidyTable = document.getElementById("tidy-table");

datasetInput.value = "/Users/skahanium/Metrica/apps/metrica-desktop/data/demo.csv";

function renderError(message) {
    errorBox.textContent = message ? `${message.text} ${message.hint || ""}` : "";
}

function renderWarnings(warnings) {
    warningBox.innerHTML = warnings.map((warning) => `<article>${warning.title}: ${warning.detail}</article>`).join("");
}

function renderGlance(glance) {
    glanceBox.innerHTML = `
        <div>模型：${glance.model}</div>
        <div>样本量：${glance.nobs}</div>
        <div>自由度：${glance.dof}</div>
        <div>R²：${glance.metrics.r2}</div>
        <div>调整 R²：${glance.metrics.adj_r2}</div>
    `;
}

function renderTidy(rows) {
    tidyTable.innerHTML = `
        <thead><tr><th>参数</th><th>估计值</th><th>标准误</th><th>统计量</th><th>p 值</th></tr></thead>
        <tbody>${rows.map((row) => `<tr><td>${row.name}</td><td>${row.estimate}</td><td>${row.stderror}</td><td>${row.statistic}</td><td>${row.pvalue}</td></tr>`).join("")}</tbody>
    `;
}

runButton.addEventListener("click", async () => {
    statusText.textContent = "运行中...";
    renderError(null);
    renderWarnings([]);
    glanceBox.innerHTML = "";
    tidyTable.innerHTML = "";

    const request = {
        task_id: crypto.randomUUID(),
        action: "fit_model",
        project_context: {
            project_id: "alpha-demo",
            working_dir: "/Users/skahanium/Metrica/apps/metrica-desktop",
        },
        dataset_ref: {
            source: "file",
            path: datasetInput.value,
            format: "csv",
        },
        model_spec: {
            model_type: "ols",
            formula: formulaInput.value,
            vcov: { type: "classical" },
        },
        options: {
            drop_missing: true,
            return_augment: false,
        },
    };

    const response = await window.metricaRuntime.fitModel(request);
    statusText.textContent = response.status === "success" ? "运行完成" : "运行失败";

    if (response.status !== "success") {
        renderError(response.messages[0]);
        return;
    }

    renderWarnings(response.result_payload.warnings || []);
    renderGlance(response.result_payload.glance);
    renderTidy(response.result_payload.tidy);
});
```

- [ ] **Step 4: 更新样式让成功/警告/错误状态可读**

在 `apps/metrica-desktop/src/styles.css` 至少加入：

```css
.app-shell { display: grid; grid-template-columns: 320px 1fr; gap: 24px; padding: 24px; }
.panel { background: #f5f1e8; border: 1px solid #d8cdb8; border-radius: 16px; padding: 20px; }
#error-box { color: #8a1c1c; margin-bottom: 12px; }
#warning-box article { background: #fff4d6; border-left: 4px solid #c58b00; padding: 10px 12px; margin-bottom: 10px; }
#tidy-table { width: 100%; border-collapse: collapse; }
#tidy-table th, #tidy-table td { padding: 8px 10px; border-bottom: 1px solid #d8cdb8; text-align: left; }
```

- [ ] **Step 5: 以 demo/runtime stub 验证前端渲染逻辑**

Run: 在本地开发模式打开页面并手工点击运行按钮。

Expected:

```text
页面可显示运行中状态，并根据返回的 success/error 结构化响应切换渲染区域。
```

- [ ] **Step 6: 提交桌面端真实结果页**

```bash
git add apps/metrica-desktop/index.html apps/metrica-desktop/src/main.js apps/metrica-desktop/src/styles.css
git commit -m "feat: render structured ols results in desktop app"
```

## Task 8: 端到端联调与验收

**Files:**
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`
- Modify: `packages/MetricaLinear.jl/test/runtests.jl`

- [ ] **Step 1: 运行 Julia 包测试**

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaLinear.jl -e "using Pkg; Pkg.test()"`

Expected:

```text
所有真实 OLS、警告、错误、序列化测试通过。
```

- [ ] **Step 2: 运行 Runtime 测试**

Run: `cargo test --manifest-path /Users/skahanium/Metrica/runtime/metrica-runtime/Cargo.toml`

Expected:

```text
Runtime 测试通过，真实 fit_model 已桥接 Julia。
```

- [ ] **Step 3: 执行一次真实手工验收**

验收场景：

```text
数据集：apps/metrica-desktop/data/demo.csv
成功公式：y ~ x1 + x2
失败公式：y ~ x9
```

Expected:

```text
成功公式时显示 glance/tidy 与删样 warning；失败公式时显示可读错误与 hint。
```

- [ ] **Step 4: 复核 Alpha 六条验收标准**

逐条复核以下标准并在工作记录中标记：

```text
1. 桌面端可选择本地 CSV 并发起真实 fit_model
2. Runtime 实际调用 Julia 子进程
3. Julia 真实完成 OLS 拟合并返回 glance/tidy
4. 缺失值删样端到端显示为 warning
5. 至少两类失败可读显示
6. demo 数据集可稳定重复验证
```

- [ ] **Step 5: 提交验收收口**

```bash
git add packages/MetricaLinear.jl/test/runtests.jl runtime/metrica-runtime/tests/vertical_slice.rs
git commit -m "test: verify alpha real ols full chain"
```
