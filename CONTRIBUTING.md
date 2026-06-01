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

### 版本与发版

普通功能或修复 PR **不必**改版本号。仓库整体版本、引用与须同步的文件清单见 [README.md](README.md) 中「版本与引用」及 [docs/governance/versioning.md](docs/governance/versioning.md)。准备发版时按 [docs/governance/release-process.md](docs/governance/release-process.md) 执行。

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
4. 确保测试通过（按改动范围选择）：
   ```bash
   # 快速：核心 Julia + Runtime 单测 + App
   bash scripts/dev/test-core.sh
   # 合并前建议：与 CI 对齐的完整 P0 门禁
   bash scripts/dev/test-p0.sh
   # 或：make test-p0
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
- TypeScript：`npm run build`（类型检查）；仓库当前无 ESLint 配置
- 核心文档使用简体中文；代码注释中英文均可
- Commit 消息格式：`feat(scope): description` 或 `fix(scope): description`

## Golden-value 贡献

1. 阅读 [docs/quality/golden-values.md](docs/quality/golden-values.md) 与 [scripts/golden/README.md](scripts/golden/README.md)。
2. 添加 `datasets/golden/<id>.{csv,json}` 与 `scripts/golden/compute_<id>_reference.jl`。
3. 在对应包增加 `test/test_golden.jl`（使用 `MetricaBase.jl/test/golden_test_helpers.jl`）。
4. 更新 [docs/quality/package-status.md](docs/quality/package-status.md)。
5. 本地运行 `make test-golden`；改动 golden 路径时 CI `golden-test` 会自动运行。

## 测试要求

- 新 Bug 修复必须附带回归测试
- 测试覆盖不得降低
- 数值结果变更应补充或更新 golden-value fixture，格式见 [docs/quality/golden-values.md](docs/quality/golden-values.md)
- 改动 `datasets/golden/**` 或含 golden 测试的包时：`make test-golden`
- 发布前质量门禁见 [docs/quality/release-checklist.md](docs/quality/release-checklist.md)
- 版本和破坏性变更规则见 [docs/governance/versioning.md](docs/governance/versioning.md)
- 完整 P0 门禁（18 个 Julia 包 + 对齐脚本 + Runtime 串行集成 + App）：`bash scripts/dev/test-p0.sh` 或 `make test-p0`
- 快速 PR 检查：`bash scripts/dev/test-core.sh`（核心 Julia + Runtime 单测 + App）
- 所有 Julia 包：`julia --project=packages/<Pkg>.jl -e 'using Pkg; Pkg.instantiate(); Pkg.test()'`
- Runtime 集成测试须串行：`cargo test --test vertical_slice --manifest-path runtime/metrica-runtime/Cargo.toml -- --test-threads=1`

## Review 规则

- Review 关注点见 [docs/contributing/review-guide.md](docs/contributing/review-guide.md)
- Issue 分流与标签规则见 [docs/contributing/triage-guide.md](docs/contributing/triage-guide.md)
- 维护者职责见 [docs/governance/maintainers.md](docs/governance/maintainers.md)
- 涉及架构边界、协议字段、`model_type` 语义、版本策略或破坏性变更时，请先按 [docs/governance/decision-records.md](docs/governance/decision-records.md) 写 Issue 或决策记录。

## AI 协作

本项目深度使用 AI 编程助手。如果你也使用 AI 工具参与贡献，请阅读 [AGENTS.md](AGENTS.md) 了解项目级的 AI 协作规则。
