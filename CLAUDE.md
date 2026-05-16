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

里程碑 1/2/3/4/5 已全部完成；**`S5` 高级研究专题** 已启动，当前进行 **`S5.0` 文档治理与阶段基线**（详见根目录 `S5-高级研究专题总施工规划.md` 与 `docs/roadmap/s5-advanced-research-topics.md`）。

- 里程碑 1：Base Alpha ✅
- 里程碑 2：教学向 OLS ✅
- 里程碑 3：面板基础 ✅
- 里程碑 4：离散 / 因果 / 时间序列 / 复杂抽样等 `S4` 模型族 ✅
- 里程碑 5：地基升级与数据能力 ✅

总体蓝图：`Metrica.jl-计量经济学框架-完善版.md`  
主设计文档：`docs/superpowers/specs/2026-04-30-metrica-main-design.md`  
当前活跃实施计划：`docs/superpowers/plans/2026-05-16-s5-execution-plan.md`

Core 层 Julia 包：MetricaBase.jl / MetricaData.jl / MetricaDiagnostics.jl / MetricaLinear.jl / MetricaPanel.jl / MetricaOutput.jl，以及 `S4` 相关包（如 MetricaDiscrete.jl、MetricaCausal.jl、MetricaTimeSeries.jl、MetricaSurvey.jl 等，以 `packages/` 为准）  
App 层技术栈：桌面宿主 **tao + wry**（`apps/metrica-desktop/src-tauri`）+ React 19 + TypeScript 5 + Zustand + Ant Design + AG Grid + ECharts；**主交互为 CLI-first 命令消息流**（前端源码在 `apps/metrica-desktop/src-react`）  
Runtime 层技术栈：Rust + axum + tokio + 持久化 Julia 进程（stdin/stdout JSON lines）  
详细架构：`docs/architecture/app-shell.md`、`docs/architecture/runtime-protocol.md`、`docs/architecture/s4-warning-coverage.md`；`S4` CLI 教程见 `tutorials/s4-*.md`。
