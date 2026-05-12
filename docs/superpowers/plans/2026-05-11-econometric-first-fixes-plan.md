# Econometric First Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复第一批会导致明显错误结果或静默跑错模型的计量与命令链路问题。

**Architecture:** 保持 Core、Runtime、App 分层：Julia 包只修估计器数学行为；React 命令层只负责生成结构化 `ModelSpec`；Runtime/Julia bridge 只做协议归一化和模型分发。每个修复先写失败测试，再做最小实现。

**Tech Stack:** Julia `Test`、Vitest、Rust integration tests、现有 Metrica model registry 与 Runtime schema。

---

## 文件结构

- Modify: `packages/MetricaDiscrete.jl/src/irls.jl`，按 link 类型区分二元响应与计数响应的均值截断。
- Modify: `packages/MetricaDiscrete.jl/src/ologit.jl`，移除 Ordered Logit 截距识别冲突，并用有序阈值参数化。
- Modify: `packages/MetricaDiscrete.jl/test/runtests.jl`，新增 Poisson 与 Ordered Logit 回归测试。
- Modify: `apps/metrica-desktop/src-react/services/commandParser.ts`，输出规范 `HC1`，并将 `xtivreg` 映射为 `panel_iv`。
- Modify: `apps/metrica-desktop/src-react/services/runtimeClient.ts`，让 `panel_iv` 传递 panel、endog、instrument 字段。
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts`，允许 `panel_iv` 作为一等模型类型。
- Modify: `apps/metrica-desktop/src-react/__tests__/commandParser.test.ts`，覆盖 `HC1` 与 `xtivreg`。
- Modify: `apps/metrica-desktop/src-react/__tests__/runtimeClient.test.ts`，覆盖 `panel_iv` 请求体。
- Modify: `scripts/julia_daemon.jl` 与 `scripts/julia_bridge_entry.jl`，归一化 `vcov.type`，避免大小写导致静默 classical。
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`，覆盖 lowercase `hc1` 仍转发为 HC1 结果。

## Task 1: Poisson IRLS 均值截断

- [x] 写失败测试：Poisson 拟合后 `maximum(fitted_values) > 1.0`，且 `loglikelihood > -10`。
- [x] 运行 `julia --project=/Users/skahanium/Metrica/packages/MetricaDiscrete.jl packages/MetricaDiscrete.jl/test/runtests.jl`，确认新增测试失败。
- [x] 修改 `irls.jl`，计数 link 只截断下界，二元 link 保留上下界。
- [x] 重跑 MetricaDiscrete 测试，确认通过。

## Task 2: Ordered Logit 识别与阈值顺序

- [x] 写失败测试：Ordered Logit 的 `coefficient_names` 不包含 `"(Intercept)"`，阈值严格递增，标准误为有限正数。
- [x] 运行 MetricaDiscrete 测试，确认新增测试失败。
- [x] 修改 `ologit.jl`，从设计矩阵剔除截距列，并用 `tau = [gamma1, gamma1 + exp(gamma2), ...]` 的方式保证阈值有序。
- [x] 重跑 MetricaDiscrete 测试，确认通过。

## Task 3: App 命令协议修复

- [x] 写失败测试：`regress ..., robust` 生成 `{ type: "HC1" }`；`xtivreg` 生成 `model_type: "panel_iv"` 且保留 `endog_columns`、`instruments`。
- [x] 写失败测试：`buildFitModelRequest` 对 `panel_iv` 同时传递 panel 与 IV 字段。
- [x] 运行 `npm test -- --run src-react/__tests__/commandParser.test.ts src-react/__tests__/runtimeClient.test.ts`，确认新增测试失败。
- [x] 修改 `commandParser.ts`、`runtimeClient.ts`、`protocol.ts`。
- [x] 重跑上述 Vitest，确认通过。

## Task 4: Runtime/Julia bridge 方差协议归一化

- [x] 写失败测试：Rust vertical slice 使用 lowercase `hc1` 仍得到 `vcov_label = "HC1"`。
- [x] 运行 `cargo test fit_model_forwards_lowercase_hc1_vcov_to_julia`，确认测试失败。
- [x] 修改 `scripts/julia_daemon.jl` 与 `scripts/julia_bridge_entry.jl`，把 `vcov.type` 归一化后映射到 Julia `Symbol`。
- [x] 重跑目标 Rust 测试，确认通过。

## Task 5: Panel IV 组内变换

- [x] 写失败测试：当个体固定效应同时进入内生变量与因变量时，`fit_panel_iv` 必须在组内空间恢复真实斜率，并且不报告被吸收的截距。
- [x] 运行窄测试，确认旧实现返回多列系数或偏离真实 FE-IV 斜率。
- [x] 修改 `packages/MetricaPanel.jl/src/panel_iv.jl`，对 `y`、外生变量、内生变量和工具变量按 `panel_id` 去均值，去掉全零截距列后再做 2SLS。
- [x] 重跑窄测试，确认通过。

## Task 6: Panel FE 自由度

- [x] 写失败测试：FE 的 `glance.dof` 必须等于 `nobs - k - (n_ids - 1)`。
- [x] 运行窄测试，确认旧实现返回 `nobs - k`。
- [x] 修改 `packages/MetricaPanel.jl/src/MetricaPanel.jl`，让 `ols_statistics` 接受可选 `residual_dof`。
- [x] 修改 `packages/MetricaPanel.jl/src/fe.jl`，传入扣减固定效应后的 FE 自由度。
- [x] 重跑 FE 自由度窄测试，确认通过。

## 验证

- [x] `julia --project=/Users/skahanium/Metrica/packages/MetricaDiscrete.jl packages/MetricaDiscrete.jl/test/runtests.jl`
- [x] `npm test -- --run src-react/__tests__/commandParser.test.ts src-react/__tests__/runtimeClient.test.ts`
- [x] `cargo test fit_model_forwards_lowercase_hc1_vcov_to_julia`
- [x] `julia --project=/Users/skahanium/Metrica/packages/MetricaPanel.jl -e '<Panel IV FE-IV regression test>'`
- [x] `julia --project=/Users/skahanium/Metrica/packages/MetricaPanel.jl -e '<Panel FE residual dof test>'`
- [ ] `julia --project=/Users/skahanium/Metrica/packages/MetricaPanel.jl packages/MetricaPanel.jl/test/runtests.jl` 当前被缺失文件 `datasets/teaching/pwt_productivity_panel.csv` 阻塞；阻塞前 88 个断言通过。
