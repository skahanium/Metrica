# S4 模型族：常见误用与 warning / error 覆盖

> 本文档与 `docs/superpowers/plans/2026-05-16-s3-s4-all-in-cli-completion-plan.md` Task 9 对齐，用于教学与验收对照。**验收状态**指：是否能在代码中定位到**结构化** `ModelWarning` / `ModelError`（或 Runtime 校验码），且测试或 CLI 路径可复现；不等同于「已穷尽所有边界」。

## 使用约定

- **code**：Julia 侧 `ModelWarning` / `ModelError` 的 `code` 符号，或 Runtime 层 `messages[].code`（如 `RUNTIME_PANEL_INDEX_REQUIRED`）。
- **测试位置**：优先指向 Julia 包 `test/runtests.jl` 中的 `@testset`；App 层见 Vitest 路径。

---

## Discrete（`MetricaDiscrete.jl`）

| 场景 | 期望 code / 行为 | 测试位置 | 验收状态 |
|------|------------------|----------|----------|
| Logit 正常拟合，系数与 glance 指标可序列化 | 无 error；`glance.model == :logit` | `packages/MetricaDiscrete.jl/test/runtests.jl` → `@testset "Logit"` | 已满足 |
| Probit / Poisson 等离散族与 Logit 对称的 glance、tidy 形状 | 无 error | 同文件 `@testset "Probit"`、`@testset "Poisson"` 等 | 已满足 |
| 公式引用不存在的列 | `ModelError`（缺失列等语义） | 包内相关负例（若仅有正例则见 backlog） | 部分满足（以正例为主） |
| 完全分离或近似分离导致数值不稳定 | `ModelWarning` 或迭代不收敛标志 | 依赖具体实现；见包内 `converged` / `warnings` 断言 | 部分满足 |
| 计数数据过度离散（NegBin / Poisson 对比教学） | 诊断或指标在 `glance.metrics` | `packages/MetricaDiscrete.jl/test/runtests.jl` 中 NegBin / Poisson 相关用例 | 已满足 |

---

## Causal（`MetricaCausal.jl`）

| 场景 | 期望 code / 行为 | 测试位置 | 验收状态 |
|------|------------------|----------|----------|
| IPW / AIPW 注册与基本拟合 | 无 error；`MODEL_REGISTRY` 含 `ipw`/`aipw` | `packages/MetricaCausal.jl/test/runtests.jl` | 已满足 |
| DID 与事件研究结构化结果 | `glance.model` 等为结构化字段 | 同文件相关 `@testset` | 已满足 |
| 倾向得分极端值（裁剪区间） | 数值稳定（如 `clamp` 倾向得分） | `packages/MetricaCausal.jl/src/ipw.jl` 实现层；测试以主路径为主 | 部分满足 |
| 处理列 / 面板索引缺失 | `ModelError` 或 Runtime `RUNTIME_MISSING_FIELD` / `RUNTIME_PANEL_INDEX_REQUIRED` | Runtime：`runtime/metrica-runtime/tests/vertical_slice.rs`；Core 见因果包负例 | 部分满足 |
| 数据集路径不存在 | `ModelError(:dataset_not_found, ...)` | `packages/MetricaLinear.jl/src/io.jl` + 因果 `fit` 路径 | 已满足 |

---

## TimeSeries（`MetricaTimeSeries.jl`）

| 场景 | 期望 code / 行为 | 测试位置 | 验收状态 |
|------|------------------|----------|----------|
| ARIMA / VAR / 单位根主路径 | `result_to_payload` 含 `glance` / `tidy` | `packages/MetricaTimeSeries.jl/test/runtests.jl` | 已满足 |
| 单位根检验滞后与确定性项组合 | 结构化检验统计量与 p 值 | 同文件 ADF 相关用例 | 已满足 |
| 样本过短或阶数与数据不匹配 | `ModelError` 或 warnings | 以包内断言为准；见 backlog 增补负例 | 部分满足 |
| Runtime 桥接非有限浮点 | JSON 输出 `null`（sanitize） | `scripts/julia_bridge_entry.jl`；`runtime/.../vertical_slice.rs` | 已满足 |
| 未知 `ts_method` / 变量缺失 | `ModelError` 或桥接错误消息 | 桥接脚本分支；建议增补单测 | 待增强 |

---

## Survey（`MetricaSurvey.jl`）

| 场景 | 期望 code / 行为 | 测试位置 | 验收状态 |
|------|------------------|----------|----------|
| Survey OLS / Logit 主路径与 glance.model 标签 | `survey_ols` 等 wire 名 | `packages/MetricaSurvey.jl/test/runtests.jl` | 已满足 |
| 权重 / strata / psu 列绑定 | 缺失时拟合失败或结构化错误 | 包内对应选项用例 | 部分满足 |
| 与 Runtime `fit_model` 垂直切片 | HTTP / 子进程成功路径 | `runtime/metrica-runtime/tests/vertical_slice.rs` | 已满足 |
| 复杂抽样设计误指定 | `ModelWarning` / `ModelError` | backlog：增补负例 | 待增强 |
| 结果序列化与 `glance["model"]` 一致性 | 与协议一致 | `packages/MetricaSurvey.jl/src/serialize.jl` + 包测试 | 已满足 |

---

## App（CLI + 结果流）

| 场景 | 期望 code / 行为 | 测试位置 | 验收状态 |
|------|------------------|----------|----------|
| `load` / `runs` / `rerun` / `export` / `compare` 不落入模型 fallthrough | 显式路由 | `apps/metrica-desktop/src-react/components/App.tsx`；`__tests__/commandExecutor.test.ts` | 已满足 |
| 模型对比族不兼容 | CLI `warning` 文案 | `modelComparison.ts`；`commandExecutor.test.ts` | 已满足 |
| 导出取消 picker | 不调用 `exportReport` | `commandExecutor.ts`；Vitest | 已满足 |

---

## Backlog（本迭代未强制落地的 Julia 负例）

下列项在计划中列为「优先覆盖」，当前以**正例 + Runtime 垂直切片**为主；若需「不能用存在 warning 替代 code 断言」的严格口径，建议在各包 `test/runtests.jl` 增加独立 `@testset` 并在此表追加一行。

- 离散：缺失删样后 `nobs` 变化的可断言 warning。
- 因果：未收敛或平行趋势失败时的结构化 warning。
- 时间序列：样本不足、滞后大于样本、协整阶数非法。
- Survey：权重非正、PSU 层级错误。

---

## 维护说明

更新 Julia 或 Runtime 行为导致 `code` 变化时，应同步更新本表「期望 code」列，并运行：

`rg -n "datasets/(teaching|demo)/" tutorials docs/architecture/s4-warning-coverage.md`
