# 贡献指南

感谢你对 Metrica 的关注。本项目目前处于回顾完善阶段，欢迎参与测试、文档、Bug 修复和开源基础设施建设。

## 行为准则

参与本项目即表示同意遵守 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

## 如何贡献

### 报告 Bug

使用 [Bug Report](https://github.com/skahanium/Metrica/issues/new?template=bug_report.yml) 模板。
请提供：model_type、Julia 版本、复现步骤、期望行为与实际行为。

### 提议功能

使用 [Feature Request](https://github.com/skahanium/Metrica/issues/new?template=feature_request.yml) 模板。
注意：当前处于完善阶段，不接受新模型族或新 model_type 的功能请求。

### 提交代码

1. Fork 本仓库
2. 从 `main` 分支创建你的特性分支
3. 编写代码和测试
4. 确保全部测试通过：
   ```bash
   make test          # Julia + Rust + App 全栈测试
   ```
5. 提交 PR（使用 PR 模板）
6. 等待 review

## 开发环境

参见 [SETUP.md](SETUP.md)。

## 代码风格

- Julia：遵循 `packages/` 下现有包的命名和结构模式
- Rust：`cargo fmt` + `cargo clippy`
- TypeScript：遵循 `apps/metrica-desktop/` 下的 ESLint 配置
- 核心文档使用简体中文；代码注释中英文均可
- Commit 消息格式：`feat(scope): description` 或 `fix(scope): description`

## 测试要求

- 新 Bug 修复必须附带回归测试
- 测试覆盖不得降低
- 所有 Julia 包：`julia --project=<pkg> -e 'using Pkg; Pkg.test()'`
- Runtime：`cargo test --lib`
- App：`cd apps/metrica-desktop && npm test`

## AI 协作

本项目深度使用 AI 编程助手。如果你也使用 AI 工具参与贡献，请阅读 [AGENTS.md](AGENTS.md) 了解项目级的 AI 协作规则。
