# S5 施工指引：高级研究专题

> **文档边界：** 本文件管 **阶段划分、优先级与验收口径**；协议字段与 HTTP 细节见 [`docs/architecture/runtime-protocol.md`](../architecture/runtime-protocol.md)；壳层事实与愿景见 [`docs/architecture/app-shell.md`](../architecture/app-shell.md)；当前全局产品基线见 [`docs/superpowers/specs/2026-04-30-metrica-main-design.md`](../superpowers/specs/2026-04-30-metrica-main-design.md)。  
> **总规：** 分期细节与非目标以仓库根目录 [`S5-高级研究专题总施工规划.md`](../../S5-高级研究专题总施工规划.md) 为准；本文件与之对齐并便于路线图导航。

## 阶段目标

在 `S1–S4` 已建立的结构化协议、Runtime 桥接、**CLI-first** 桌面消息流与输出系统之上，按克制节奏扩展高级研究专题；每个专题进入代码前须先更新总规、对应分期实施要点与结构化结果边界（见总规 §2）。

## 分期与优先级

| 分期 | 主题 | 优先级 |
|------|------|--------|
| **S5.0** | 文档治理与阶段基线 | 必须先完成 |
| **S5.1** | 一般 GMM 与过识别检验 | 高 |
| **S5.2** | 动态面板 GMM | 高 |
| **S5.3** | SUR / 联立方程 | 高 |
| **S5.4** | 分位数回归 | 高 |
| **S5.5** | 非线性、门限；非参数/半参数预研 | 中（预研项见总规） |
| **S5.6** | ARCH / GARCH | 中 |
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
- **S5.5–S5.9：** 见总规 §8–§12。

## 活跃实施计划

- [`docs/superpowers/plans/2026-05-16-s5-execution-plan.md`](../superpowers/plans/2026-05-16-s5-execution-plan.md)

## 历史映射

- 旧路线中未正式编排的高复杂空白区曾记为 `M14+`；现由 `S5` 分期承接。
