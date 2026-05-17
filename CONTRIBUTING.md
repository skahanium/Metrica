# 贡献指南

感谢你对 Metrica 的关注。本项目目前处于回顾完善阶段，欢迎参与测试、文档、Bug 修复和开源基础设施建设。

## 行为准则

参与本项目即表示同意遵守 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

## 如何贡献

### 当前优先级

Metrica 处于回顾完善阶段。优先接受：

- 测试补充：确定性测试、边界条件、结构化 warning、golden-value 对齐
- Bug 修复：数值精度、缺失值处理、错误处理、协议字段一致性
- 文档改进：README、教程、架构文档、贡献者说明
- 开源基础设施：CI、开发脚本、发布检查清单

暂不接受：

- 新模型族
- 新 `model_type`
- 大范围架构重构
- UI 中新增计量逻辑，或 Runtime 中重复 Julia Core 业务逻辑

### 第一次贡献

1. 阅读 [README.md](README.md)、[AGENTS.md](AGENTS.md) 和 [docs/quality/package-status.md](docs/quality/package-status.md)
2. 从 `good first issue`、`docs`、`tests` 或 `quality` 标签开始
3. 运行环境检查：
   ```bash
   bash scripts/dev/doctor.sh
   ```
4. 修改前先确认影响范围，只改必要文件
5. 提交前运行与改动相关的最小验证

### 报告 Bug

使用 [Bug Report](https://github.com/skahanium/Metrica/issues/new?template=bug_report.yml) 模板。
请提供：受影响包、model_type、Julia 版本、复现步骤、期望行为、实际行为和已运行的验证命令。

### 提议功能

使用 [Feature Request](https://github.com/skahanium/Metrica/issues/new?template=feature_request.yml) 模板。
注意：当前处于完善阶段，不接受新模型族或新 model_type 的功能请求。

### 提交代码

1. Fork 本仓库
2. 从 `main` 分支创建你的特性分支
3. 编写代码和测试
4. 确保全部测试通过：
   ```bash
   bash scripts/dev/test-core.sh
   ```
5. 提交 PR（使用 PR 模板）
6. 等待 review

## 开发环境

参见 [SETUP.md](SETUP.md)。

常用脚本：

```bash
bash scripts/dev/doctor.sh
bash scripts/dev/test-core.sh
bash scripts/dev/test-package.sh MetricaLinear.jl
```

## 代码风格

- Julia：遵循 `packages/` 下现有包的命名和结构模式
- Rust：`cargo fmt` + `cargo clippy`
- TypeScript：遵循 `apps/metrica-desktop/` 下的 ESLint 配置
- 核心文档使用简体中文；代码注释中英文均可
- Commit 消息格式：`feat(scope): description` 或 `fix(scope): description`

## 测试要求

- 新 Bug 修复必须附带回归测试
- 测试覆盖不得降低
- 数值结果变更应补充或更新 golden-value fixture，格式见 [docs/quality/golden-values.md](docs/quality/golden-values.md)
- 发布前质量门禁见 [docs/quality/release-checklist.md](docs/quality/release-checklist.md)
- 所有 Julia 包：`julia --project=<pkg> -e 'using Pkg; Pkg.test()'`
- PR 阻塞 Julia 核心链路：`make test-julia-core`
- Runtime：`cargo test --lib`
- App：`cd apps/metrica-desktop && npm test`

## Review 规则

- Review 关注点见 [docs/contributing/review-guide.md](docs/contributing/review-guide.md)
- Issue 分流与标签规则见 [docs/contributing/triage-guide.md](docs/contributing/triage-guide.md)

## AI 协作

本项目深度使用 AI 编程助手。如果你也使用 AI 工具参与贡献，请阅读 [AGENTS.md](AGENTS.md) 了解项目级的 AI 协作规则。
