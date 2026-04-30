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

项目处于里程碑 2 收口阶段。当前活跃计划：
- `docs/superpowers/plans/2026-04-30-metrica-current-plan.md`

架构设计：
- `docs/superpowers/specs/2026-04-30-metrica-main-design.md`

App 层技术栈：Tauri 2 + React 19 + TypeScript 5 + Zustand + Ant Design + AG Grid + ECharts
Runtime 层技术栈：Rust + axum + tokio + 持久化 Julia 进程（stdin/stdout JSON lines）
详细架构：`docs/architecture/app-shell.md`、`docs/architecture/runtime-protocol.md`
