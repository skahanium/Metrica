# Metrica

<div align="center">
  <img src="assets/icons/metrica-icon-128x128.png" alt="Metrica Icon" width="128" height="128">
</div>

Metrica 是一个基于 Julia 的联邦式计量经济学框架，目标是在教学体验、工程一致性、性能与可扩展性上，逐步超越 Python `statsmodels`，并最终发展为可视化、原生化的计量经济学应用生态。

**当前阶段：S1–S5 全部完成 ✅，下一阶段 S6（安装包与产品化收口）。**

当前仓库包含：

- `packages/`：20 个 Julia Core 包（含全部 S4/S5 模型族）
- `runtime/metrica-runtime/`：Rust 运行时桥接层（axum + Julia 持久化进程）
- `apps/metrica-desktop/`：桌面工作台（**CLI-first** 消息流 + 结构化结果消费 + 20 个专用诊断面板）
- `datasets/demo/`：全部模型族教学 demo 数据
- `tutorials/`：全部 S5 模型族 CLI 教程

关键文档：

- `Metrica.jl-计量经济学框架-完善版.md`：项目总体蓝图
- `docs/roadmap/s5-advanced-research-topics.md`：S5 完成记录
- `docs/architecture/runtime-protocol.md`：Runtime 协议（全部 model_type 白名单）
- `docs/roadmap/`：阶段施工指引（S1–S4 ✅，S5 ✅，S6–S7 待推进）

核心原则：

- `Core` 负责计量协议与结果语义
- `Runtime` 负责执行桥接与协议搬运
- `App` 负责工作台体验与结构化结果展示

长期目标已收敛为：先完成教学友好和常见应用研究所需的现代桌面工作台，再在结构化协议稳定后为 AI 原生计量助手保留未来开发空间；不追求复刻完整 Stata 命令生态、开放脚本平台或插件市场。
