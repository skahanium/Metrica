# CLAUDE.md

本文件是 Claude Code 的项目级指令源。所有规则以 `AGENTS.md` 为权威来源，本文件仅作简洁引用。

## 核心规则

严格遵循 `AGENTS.md` 中定义的所有规则，特别是：

- Core / Runtime / App 三层架构边界，不得混淆
- 结构化结果优先于展示文本
- 教学体验是核心要求，非可选润色
- 禁止静默捏造 API、文件或测试结果

## 当前阶段

前期建设已基本完成。当前处于**完善阶段**：修复缺陷、补充测试、打磨文档、建设开源基础设施。无活跃路线图。

明确禁止：新增模型族或 model_type、新增包或子系统、大范围重构。

## 项目定位

Metrica 是一个开源计量经济学框架。20 个 Julia Core 包 + CLI-first 桌面工作台 + GPL v3 许可。AI 协作构建（AGENTS.md 为 AI 助手的项目指令中枢）。

总体蓝图：`Metrica.jl-计量经济学框架-完善版.md`
架构文档：`docs/architecture/`

## 技术栈

- Core 层 Julia 包（20 个）：`packages/`
- Runtime 层：Rust + axum + tokio + 持久化 Julia 进程（stdin/stdout JSON lines）
- App 层：React 19 + TypeScript 5 + Ant Design + Tauri（CLI-first 命令消息流）
