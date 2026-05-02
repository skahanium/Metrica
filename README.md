# Metrica

Metrica 是一个基于 Julia 的联邦式计量经济学框架，目标是在教学体验、工程一致性、性能与可扩展性上，逐步超越 Python `statsmodels`，并最终发展为可视化、原生化的计量经济学应用生态。

当前目录包含：

- `Metrica.jl-计量经济学框架-完善版.md`：项目总体蓝图与架构设计
- `AGENTS.md`：跨 AI 助手统一协作规范
- `docs/superpowers/specs/2026-04-30-metrica-main-design.md`：当前主设计
- `docs/superpowers/plans/2026-05-02-milestone-5-implementation-plan.md`：当前实施计划
- `docs/roadmap/`：新阶段体系施工指引，不替代当前实施计划

建议采用 `monorepo + 多包` 组织方式，以 `MetricaBase.jl` 协议内核为边界，逐步实现数据管理、线性回归、面板模型、诊断检验、输出报告、桌面工作台与教学体系。

当前仓库中已经包含：

- `packages/`：Julia Core 包骨架
- `runtime/metrica-runtime/`：Rust 运行时桥接层骨架
- `apps/metrica-desktop/`：桌面工作台原型壳

当前目标不是一次做完整产品，而是在已验证的真实 OLS 基线上继续保持稳定分层：

- `Core` 负责计量协议与结果语义
- `Runtime` 负责执行桥接与协议搬运
- `App` 负责工作台体验与结构化结果展示

长期目标已收敛为：先完成教学友好和常见应用研究所需的现代桌面工作台，再在结构化协议稳定后为 AI 原生计量助手保留未来开发空间；不追求复刻完整 Stata 命令生态、开放脚本平台或插件市场。
