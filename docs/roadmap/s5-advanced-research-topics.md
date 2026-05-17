# S5 施工指引：高级研究专题（✅ 全量完成）

> **状态：S5 全部 10 个分期已于 2026-05-17 完成。** 本文件保留为完成记录与导航索引。
> 协议细节见 [`docs/architecture/runtime-protocol.md`](../architecture/runtime-protocol.md)。
> 下一阶段：`S6` 安装包与产品化收口。

## 分期完成状态

| 分期 | 主题 | 状态 |
|------|------|------|
| **S5.0** | 文档治理与阶段基线 | ✅ 完成 |
| **S5.1** | GMM（iterated/CUE/C-stat/Cragg-Donald） | ✅ 完成 |
| **S5.2** | 动态面板 GMM（Difference/System/Collapsed/Diff-Hansen） | ✅ 完成 |
| **S5.3** | SUR / 联立方程（Wald/LR/LM/robust cov） | ✅ 完成 |
| **S5.4** | 分位数回归（多 τ/bootstrap/rank/IV） | ✅ 完成 |
| **S5.5** | 非线性/门限（4 族/多起点/多门限/sup-Wald） | ✅ 完成 |
| **S5.6** | ARCH/GARCH/GJR/EGARCH（3 分布/forecast/VaR/ES） | ✅ 完成 |
| **S5.7** | 空间计量 | 中 |
| **S5.8** | 久期模型 | 中 |
| **S5.9** | 贝叶斯能力预研与最小闭环 | 低（预研） |

## 明确非目标（阶段级）

- 不把高级专题前移为「基础工作台门禁」；`MetricaBase.jl` 不承载估计量实现，仅扩共享协议与抽象（总规 §2）。
- Runtime 只做 schema、路径与调用搬运；App 只消费结构化结果，不解析 `summary()` 文本（总规 §2）。
- 不开放任意 Julia 代码、任意 shell、任意用户自定义 moment DSL，除非后续单独设计受控模板（总规 §2、总规 §13）。

## 统一公开接口与测试规则

- 新模型走 `fit_model` 信封；`model_spec.model_type` 为明确枚举；结果须含 `glance`、`tidy`、`diagnostics`、`warnings`（及总规约定的扩展字段）（总规 §13–§14）。
- 每专题最小闭环：`Core -> Runtime -> App -> Output -> docs/tests`，含教学数据、CLI 主路径、结构化 warning/error 清单（总规 §2、§14）。

## 分期验收要点（摘要）

- **S5.0：** `docs/superpowers/specs/` 与 `plans/` 仅保留当前活跃锚点与 S5 执行计划；全仓无误导性过期主路径叙述；architecture 与 Runtime 端点、`model_type` 族与代码一致（总规 §3）。
- **S5.1–S5.4：** 见总规 §4–§7 各节「验收标准」；**S5.2** 实施任务清单见 [`2026-05-16-s5-execution-plan.md`](../superpowers/plans/2026-05-16-s5-execution-plan.md) 中「S5.2 动态面板 GMM」专节；教程见 [`tutorials/s5-dynamic-panel-gmm.md`](../../tutorials/s5-dynamic-panel-gmm.md)。**S5.3**（SUR / 联立方程）专节与 Task 表见同文件「S5.3 SUR 与联立方程」；教程见 [`tutorials/s5-sur-system.md`](../../tutorials/s5-sur-system.md)。**S5.4**（分位数回归）专节与 Task 表见同文件「S5.4 分位数回归」；教程见 [`tutorials/s5-quantile-regression.md`](../../tutorials/s5-quantile-regression.md)。
- **S5.5**（非线性、门限；非参数/半参数预留）：专节与 Task 表见 [`2026-05-16-s5-execution-plan.md`](../superpowers/plans/2026-05-16-s5-execution-plan.md)「S5.5」；教程见 [`tutorials/s5-nonlinear-threshold.md`](../../tutorials/s5-nonlinear-threshold.md)。
- **S5.6**（ARCH / GARCH）：专节与 Task 表见 [`2026-05-16-s5-execution-plan.md`](../superpowers/plans/2026-05-16-s5-execution-plan.md)「S5.6 ARCH / GARCH」；教程见 [`tutorials/s5-arch-garch.md`](../../tutorials/s5-arch-garch.md)。
- **S5.7**（空间计量）：专节与 Task 表见 [`2026-05-16-s5-execution-plan.md`](../superpowers/plans/2026-05-16-s5-execution-plan.md)「S5.7 空间计量」；教程见 [`tutorials/s5-spatial.md`](../../tutorials/s5-spatial.md)。
- **S5.8**（久期模型 / Cox）：专节与 Task 表见 [`2026-05-16-s5-execution-plan.md`](../superpowers/plans/2026-05-16-s5-execution-plan.md)「S5.8 久期模型」；教程见 [`tutorials/s5-duration.md`](../../tutorials/s5-duration.md)。
- **S5.9**（贝叶斯）：NIG 共轭 + MCMC + logistic/probit + 层级模型 ✅ 完成

## 历史映射

- 旧路线中未正式编排的高复杂空白区曾记为 `M14+`；已由 `S5` 分期全部承接完成。

## 历史映射

- 旧路线中未正式编排的高复杂空白区曾记为 `M14+`；现由 `S5` 分期承接。
