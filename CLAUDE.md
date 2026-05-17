# CLAUDE.md

本文件是 Claude Code 的项目级指令源。所有规则以 `AGENTS.md` 为权威来源，本文件仅作简洁引用。

## 核心规则

请严格遵循 `AGENTS.md` 中定义的所有规则，特别是：

- 尊重 Core / Runtime / App 三层架构边界，不得混淆
- 结构化结果优先于展示文本
- 教学体验是核心要求，非可选润色
- 禁止静默捏造 API、文件或测试结果
- 注释与文档正文使用简体中文

## 当前阶段

前期建设（里程碑 1–5 + S5 全部模型族）已基本完成。当前处于回顾完善阶段：修复缺陷、打磨数值精度、补充测试覆盖、清理文档债务。无活跃路线图。

总体蓝图：`Metrica.jl-计量经济学框架-完善版.md`
架构文档：`docs/architecture/`

Core 层 Julia 包（20 个）：MetricaBase / MetricaData / MetricaDiagnostics / MetricaLinear / MetricaPanel / MetricaOutput / MetricaDiscrete / MetricaCausal / MetricaTimeSeries / MetricaSurvey / MetricaGMM / MetricaQuantile / MetricaNonlinear / MetricaSystem / MetricaSpatial / MetricaDuration / MetricaBayes / MetricaRuntime（以 `packages/` 为准）  
App 层：桌面宿主 **tao + wry** + React 19 + TypeScript 5 + Ant Design；**CLI-first 命令消息流**  
Runtime 层：Rust + axum + tokio + 持久化 Julia 进程（stdin/stdout JSON lines）
