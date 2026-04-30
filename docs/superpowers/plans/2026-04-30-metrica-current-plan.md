# Metrica 当前实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已验证的真实 OLS 基线上，完成里程碑 2 的协议贯通与数值可信度加固。

**Architecture:** 当前仓库以 `docs/superpowers/specs/2026-04-30-metrica-main-design.md` 为唯一主设计。`MetricaLinear.jl` 已具备包层 OLS、WLS、HC1；下一步不新增平行路线，而是把这些能力通过 Runtime 与 App 的结构化协议真实暴露出来，并用确定性测试固定数值语义。

**Tech Stack:** Julia, DataFrames.jl, StatsModels.jl, LinearAlgebra, Statistics, Distributions.jl, Rust, JSON, HTML, CSS, JavaScript

---

## 当前事实

已验证成立的基线：

- `MetricaLinear.jl`：真实 OLS、WLS、HC1、结构化 `glance` / `tidy` / warning / error、数据检查载荷。
- `MetricaOutput.jl`：教学向摘要与 Markdown 回归表。
- `MetricaTests.jl`：VIF 与 Breusch-Pagan 最小接口。
- `runtime/metrica-runtime`：`/inspect_dataset` 与 `/fit_model` 真实调用 Julia 子进程。
- `apps/metrica-desktop`：通过 Runtime HTTP 端点消费结构化数据检查与模型结果。

当前不再保留独立历史计划。早期 foundation、vertical slice、dual-track 与 visualization 草案已被主设计和子系统架构文档吸收。

## Task 1: 贯通 Runtime 的 `vcov` 参数

**Files:**

- Modify: `runtime/metrica-runtime/src/julia_bridge.rs`
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`
- Modify: `packages/MetricaLinear.jl/src/serialize.jl`

- [ ] **Step 1: 为 Runtime 写 HC1 请求测试**

在 `runtime/metrica-runtime/tests/vertical_slice.rs` 中新增测试，构造 `model_spec.vcov.type = "HC1"` 的 `fit_model` 请求，断言返回成功且 `result_payload.tidy` 对应载荷能体现 HC1 协方差标签。

- [ ] **Step 2: 转发 `model_spec.vcov.type` 到 Julia**

在 `runtime/metrica-runtime/src/julia_bridge.rs` 的 Julia 脚本中读取 `request.model_spec.vcov.type`，将 `classical` 映射为 `:classical`，将 `HC1` 映射为 `:HC1`，并调用 `fit_ols_file(dataset_path, formula; vcov=vcov_symbol)`。

- [ ] **Step 3: 稳定序列化字段**

确认 `packages/MetricaLinear.jl/src/serialize.jl` 的 `tidy` 载荷暴露 `vcov_label` 或等价结构化字段，供 Runtime/App 断言与展示，不依赖文本摘要。

- [ ] **Step 4: 验证 Runtime 链路**

Run: `cargo test`

Expected: Runtime 单元测试与 `vertical_slice` 测试全部通过。

## Task 2: 设计并贯通 WLS 权重字段

**Files:**

- Modify: `docs/architecture/runtime-protocol.md`
- Modify: `runtime/metrica-runtime/src/lib.rs`
- Modify: `runtime/metrica-runtime/src/julia_bridge.rs`
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`

- [ ] **Step 1: 在协议中固定权重字段归属**

在 `docs/architecture/runtime-protocol.md` 中明确 WLS 权重变量使用 `model_spec.weights`，其值为数据集列名；缺省时保持 OLS。

- [ ] **Step 2: 扩展 Runtime 请求结构**

在 `runtime/metrica-runtime/src/lib.rs` 的 `ModelSpec` 中新增可选字段 `weights: Option<String>`，保持现有 OLS 请求兼容。

- [ ] **Step 3: 转发权重列到 Julia**

在 `runtime/metrica-runtime/src/julia_bridge.rs` 中读取 `model_spec.weights`。存在时转换为 Julia `Symbol` 并调用 `fit_ols_file(dataset_path, formula; weights=weight_symbol, vcov=vcov_symbol)`。

- [ ] **Step 4: 验证 WLS 链路**

Run: `cargo test`

Expected: 新增 WLS 请求测试通过，既有 OLS 与 inspect 测试保持通过。

## Task 3: 补强数值可信度测试

**Files:**

- Modify: `packages/MetricaLinear.jl/test/runtests.jl`
- Modify: `packages/MetricaTests.jl/test/runtests.jl`

- [ ] **Step 1: 为 OLS/WLS/HC1 增加确定性数值断言**

使用仓库内稳定 demo 数据或专门构造的小型 CSV，断言关键系数、标准误、`r2`、`vcov_label` 的数值或标签，而不只断言字段存在。

- [ ] **Step 2: 为诊断接口增加形状与边界断言**

补充 VIF 与 Breusch-Pagan 的确定性测试，覆盖无截距、单解释变量与近共线场景。

- [ ] **Step 3: 运行 Julia 包测试**

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaLinear.jl -e "using Pkg; Pkg.test()"`

Run: `julia --project=/Users/skahanium/Metrica/packages/MetricaTests.jl -e "using Pkg; Pkg.test()"`

Expected: 两个包测试全部通过。

## Task 4: App 暴露结构化选项

**Files:**

- Modify: `apps/metrica-desktop/src/runtime-client.js`
- Modify: `apps/metrica-desktop/src/main.js`
- Modify: `apps/metrica-desktop/src/result-view.js`
- Modify: `apps/metrica-desktop/tests/runtime-client.test.js`
- Modify: `apps/metrica-desktop/tests/result-view.test.js`

- [ ] **Step 1: 在请求构造中支持 `vcov` 与 `weights`**

扩展 `buildFitModelRequest`，允许调用方传入 `vcovType` 与 `weightsColumn`，并保持缺省请求仍为 `ols + classical`。

- [ ] **Step 2: 在页面上提供最小控件**

添加协方差类型选择与可选权重列输入。控件只生成结构化字段，不拼接公式、不生成自由脚本。

- [ ] **Step 3: 渲染协方差标签与诊断结果入口**

在结果区展示 `tidy.vcov_label` 或等价字段，并为后续诊断结果预留结构化区域。

- [ ] **Step 4: 运行前端测试**

Run: `npm test`

Expected: Runtime client 与结果渲染测试全部通过。
