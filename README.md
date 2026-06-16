# Metrica

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Version](https://img.shields.io/badge/version-0.1.1-6A5ACD)](CITATION.cff)
[![CI](https://github.com/skahanium/Metrica/actions/workflows/ci.yml/badge.svg)](https://github.com/skahanium/Metrica/actions)
[![Julia](https://img.shields.io/badge/Julia-1.12-purple)](https://julialang.org/)

Metrica 是一个开源计量经济学框架，为学术研究和数据分析提供高性能、结构化、可扩展的现代工具链。当前仓库包含 18 个 Julia 包，覆盖从经典线性回归到贝叶斯方法的主流模型族，配合 CLI-first 桌面工作台和统一的模型能力协议。

## 为什么选择 Metrica

**AI 协作构建。** 项目由人类与 AI（Claude Code）在结构化协议驱动下协作完成。`AGENTS.md` 是 AI 助手的项目指令中枢，定义了架构规则、工作流程和代码标准。这不是 AI 辅助写了几行代码，而是整个项目架构、协议设计、实现验证的深度协作产物。

**CLI-First。** 类 Stata 命令行交互模型。输入 `regress y x1 x2` 得到结构化结果，不必在 notebook 里摸索 API，不必在 GUI 里点选菜单。所有模型通过统一的 `fit_model` 协议信封通信。

**结构化结果。** 所有模型输出 `glance`（摘要）、`tidy`（系数表）、`diagnostics`（诊断）、`warnings`（警告）四层机器可读协议。桌面 App 只消费结构化数据，不解析终端文本。这意味着任何前端、任何导出格式、任何自动化流程都可以零成本对接。

**Julia 性能。** 原生 Julia 实现。性能验证正在收口中，当前不宣称未复现的跨软件倍数；可复现脚本和覆盖状态见 [benchmarks/](benchmarks/) 与 [docs/quality/package-status.md](docs/quality/package-status.md)。

**全栈贯通。** Core（Julia 计量引擎）→ Runtime（Rust HTTP/进程桥接）→ App（React + tao/wry 桌面工作台），一条链路无缝合、无拼接、无临时脚本。

**开放透明。** GPL v3 许可。全部代码、全部协议、全部设计文档公开。零黑箱算法、零隐藏参数、零专有格式。

**联邦式架构。** 18 个 Julia 包按模型族松耦合。研究空间计量只需 `MetricaSpatial.jl`，做贝叶斯只需 `MetricaBayes.jl`。每个包独立测试、独立版本、独立引用。

## 当前阶段

前期建设（S1–S5 全部模型族）已基本完成，当前处于回顾完善阶段。

项目目前**不可用于生产或未经审阅的正式研究**：API 可能变动、桌面 App 尚未打包分发、多数模型族尚无外部（L3）数值互验。

部分高频路径已通过 **golden-value** 回归（OLS/IV/GLS、Logit/Probit/Poisson、分位数中位数、空间 SAR、动态面板 GMM、Cox、DID、IPW、SUR、ARIMA、单位根检验、贝叶斯共轭线性等，共 17 个标准用例），详见 [docs/quality/package-status.md](docs/quality/package-status.md) 与 [docs/quality/credibility-tiers.md](docs/quality/credibility-tiers.md)。

欢迎参与共建。当前最适合的贡献方向是测试、golden-value 对齐、Bug 修复、文档和开源基础设施。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 版本与引用

- **当前仓库整体发布线：** `0.1.1`（与 [CHANGELOG.md](CHANGELOG.md) 最新条目、[CITATION.cff](CITATION.cff) 中的 `version` 一致）。
- **论文与软件引用：** 以根目录 [CITATION.cff](CITATION.cff) 为准（含 `date-released`）；GitHub 仓库页的「Cite this repository」也由此生成。
- **各组件版本字段：** Julia Core 为各 `packages/*/Project.toml` 的 `version`（另有 `scripts/daemon/Project.toml`）；Runtime 为 `runtime/metrica-runtime/Cargo.toml`；桌面原生壳（wry + tao，目录名 `src-tauri` 为历史路径，非 [Tauri](https://tauri.app/) 框架）为 `apps/metrica-desktop/src-tauri/Cargo.toml`。正式发布时应与上述发布线一致，清单见 [docs/governance/versioning.md](docs/governance/versioning.md#仓库内须同步的版本字段)。
- **前端 npm 包：** `apps/metrica-desktop/package.json` 未维护 `version` 字段；若需对外报桌面版本，以 **桌面壳工程** `Cargo.toml` 为准。

发版步骤与质量门禁见 [docs/governance/release-process.md](docs/governance/release-process.md) 与 [docs/quality/release-checklist.md](docs/quality/release-checklist.md)。

## 模型族

| 模型族 | model_type | 包 |
|--------|-----------|-----|
| 线性 | `ols`, `iv`, `gls`, `gmm_linear` | MetricaLinear, MetricaGMM |
| 面板 | `panel`, `panel_iv`, `dynamic_panel_gmm` | MetricaPanel |
| 离散 | `logit`, `probit`, `poisson`, `ordered_logit`, `multinomial_logit`, `negbin` | MetricaDiscrete |
| 因果 | `did`, `event_study`, `ipw`, `psm`, `aipw` | MetricaCausal |
| 时间序列 | `arima`, `var`, `unitroot`, `cointegration` | MetricaTimeSeries |
| 波动率 | `arch`, `garch`, `gjr_garch`, `egarch` | MetricaTimeSeries |
| 复杂抽样 | `survey_ols`, `survey_logit`, `survey_probit`, `survey_poisson` | MetricaSurvey |
| 系统方程 | `sur`, `system_2sls`, `system_3sls` | MetricaSystem |
| 分位数 | `quantile` | MetricaQuantile |
| 非线性/门限 | `nls`, `threshold` | MetricaNonlinear |
| 空间 | `spatial_lag`, `spatial_error`, `spatial_slx`, `spatial_sdm`, `spatial_sdem`, `spatial_sac`, `spatial_gwr`, `spatial_gtwr`, `spatial_probit` | MetricaSpatial |
| 久期 | `duration_cox`, `aft_weibull`, `aft_exponential`, `aft_lognormal`, `aft_loglogistic` | MetricaDuration |
| 贝叶斯 | `bayes_linear`, `bayes_logistic`, `bayes_probit`, `bayes_hierarchical` | MetricaBayes |

## 快速安装

```bash
# Julia Core 包（从本地源码安装）
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Runtime（需要 Rust）
cd runtime/metrica-runtime && cargo build --release

# 桌面 App（需要 Node.js + Rust；`src-tauri` 为原生壳工程目录，非 Tauri 框架）
cd apps/metrica-desktop && npm ci && cargo run --manifest-path src-tauri/Cargo.toml
```

参见 [SETUP.md](SETUP.md) 获取详细开发环境配置。

## 架构

```
packages/          Julia 包（当前 18 个包 + 协议层）
runtime/           Rust axum HTTP + Julia 进程管理
apps/              React + tao/wry 桌面工作台（CLI-first）
docs/              架构文档 + 协议规范
tutorials/         模型族 CLI 教程（13 篇）
datasets/demo/     教学演示数据（16 个）
```

## 文档

- [Metrica.jl-计量经济学框架-完善版.md](Metrica.jl-计量经济学框架-完善版.md) — 项目蓝图
- [AGENTS.md](AGENTS.md) — AI 协作协议
- [docs/architecture/runtime-protocol.md](docs/architecture/runtime-protocol.md) — Runtime 协议与 model_type 白名单
- [docs/architecture/app-shell.md](docs/architecture/app-shell.md) — App 工作台结构
- [docs/quality/package-status.md](docs/quality/package-status.md) — 包级 CI / golden / benchmark 状态矩阵
- [docs/quality/golden-values.md](docs/quality/golden-values.md) — golden-value 验证政策
- [docs/quality/release-checklist.md](docs/quality/release-checklist.md) — 发布前质量门禁
- [docs/governance/versioning.md](docs/governance/versioning.md) — SemVer 与破坏性变更规则
- [docs/governance/release-process.md](docs/governance/release-process.md) — 手动发布流程
- [docs/governance/support-policy.md](docs/governance/support-policy.md) — 个人维护者支持边界
- [docs/governance/maintainers.md](docs/governance/maintainers.md) — 维护者职责与决策权限
- [docs/governance/decision-records.md](docs/governance/decision-records.md) — ADR/RFC 决策记录流程
- [tutorials/](tutorials/) — 全部模型族 CLI 教程

## 许可证

GNU General Public License v3.0。详见 [LICENSE](LICENSE)。
