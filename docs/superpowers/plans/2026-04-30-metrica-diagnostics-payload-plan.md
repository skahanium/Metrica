# Metrica 诊断载荷实施计划

> **状态：已完成。** Runtime 已返回结构化 diagnostics，App 已展示 VIF 与 Breusch-Pagan 结果，完整验证矩阵已通过。

> **给代理式执行者：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务推进。步骤使用 checkbox（`- [ ]`）语法跟踪。

**目标：** 将 `MetricaTests.jl` 中已有的 VIF 与 Breusch-Pagan 诊断结果贯通到 Runtime 响应和 App 诊断区。

**架构：** 避免让 `MetricaLinear.jl` 反向依赖 `MetricaTests.jl`。Runtime 继续以 `packages/MetricaLinear.jl` 作为 Julia project，确保拟合依赖仍由线性包环境管理；桥接脚本显式加载本仓库的 `MetricaTests.jl` 模块，在拟合后调用诊断函数，并把 diagnostics 注入结构化 `result_payload`。

**技术栈：** Julia, MetricaLinear.jl, MetricaTests.jl, Rust, JSON, HTML, CSS, JavaScript

---

## 任务 1：让 Runtime Julia 环境可同时加载 Linear 与 Tests

**文件：**

- 修改：`runtime/metrica-runtime/src/julia_bridge.rs`
- 修改：`runtime/metrica-runtime/tests/vertical_slice.rs`

- [x] **步骤 1：写 Runtime diagnostics 失败测试**

在 `runtime/metrica-runtime/tests/vertical_slice.rs` 中断言 `fit_model` 成功响应包含 `result_payload.diagnostics.vif` 与 `result_payload.diagnostics.breusch_pagan`。

- [x] **步骤 2：保持线性包项目作为 Runtime Julia project**

确认 Runtime 默认 Julia project 继续指向 `packages/MetricaLinear.jl`，避免仓库根环境承担包依赖解析职责。

- [x] **步骤 3：传入仓库根路径给 Julia 脚本**

在 `runtime/metrica-runtime/src/julia_bridge.rs` 中向 Julia 脚本传入仓库根路径，用于定位 `MetricaTests.jl` 源文件。保留 `METRICA_JULIA_PROJECT` 环境变量覆盖能力。

## 任务 2：注入结构化 diagnostics 载荷

**文件：**

- 修改：`runtime/metrica-runtime/src/julia_bridge.rs`
- 修改：`runtime/metrica-runtime/tests/vertical_slice.rs`

- [x] **步骤 1：Julia 脚本加载 `MetricaTests`**

Runtime Julia 脚本 `using MetricaLinear`，并显式 include 本仓库的 `MetricaTests.jl` 后 `using .MetricaTests`。

- [x] **步骤 2：成功拟合后注入 diagnostics**

当 `fit_ols_file` 返回 `OLSFitResult` 时，构造：

```json
{
  "vif": [{"name": "x1", "vif": 1.0}],
  "breusch_pagan": {"statistic": 0.0, "pvalue": 1.0, "dof": 2}
}
```

并写入 `result_payload.diagnostics`。模型错误响应不得包含 diagnostics。

- [x] **步骤 3：验证 Runtime**

运行：`cargo test`

预期：Runtime diagnostics 目标测试通过；完整 Runtime 验证在最终验证阶段执行。

## 任务 3：App 渲染 diagnostics

**文件：**

- 修改：`apps/metrica-desktop/src/result-view.js`
- 修改：`apps/metrica-desktop/src/main.js`
- 修改：`apps/metrica-desktop/tests/result-view.test.js`

- [x] **步骤 1：写诊断渲染失败测试**

新增测试断言 `renderDiagnostics` 能输出 VIF 变量名、VIF 值、Breusch-Pagan 统计量与 p 值。

- [x] **步骤 2：实现 `renderDiagnostics`**

新增 `renderDiagnostics(diagnostics)`，空值时返回当前空状态；有值时分别渲染 VIF 表与 Breusch-Pagan 摘要。

- [x] **步骤 3：接入页面**

`main.js` 在成功响应中调用 `renderDiagnostics(payload.diagnostics)`，重置结果区时恢复空状态。

- [x] **步骤 4：验证 App**

运行：`npm test`

预期：Runtime client 与结果渲染测试全部通过。

## 任务 4：最终验证

**文件：**

- 无额外文件。

- [x] **步骤 1：运行完整验证矩阵**

运行：

```bash
cargo test
julia --project=/Users/skahanium/Metrica/packages/MetricaLinear.jl -e "using Pkg; Pkg.test()"
julia --project=/Users/skahanium/Metrica/packages/MetricaTests.jl -e "using Pkg; Pkg.test()"
npm test
git diff --check
```

预期：全部通过。
