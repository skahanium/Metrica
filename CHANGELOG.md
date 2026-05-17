# Changelog

格式基于 [Keep a Changelog](https://keepachangelog.com/)。

## [0.1.0] - 2026-05-17

### Added

- **S5.1** GMM：一步/两步/Iterated/CUE、Hansen J、C-stat、Diff-Hansen、Cragg-Donald F
- **S5.2** 动态面板 GMM：Difference + System GMM（Blundell-Bond）、collapsed instruments
- **S5.3** 系统方程：SUR(FGLS)、system 2SLS/3SLS、跨方程 Wald/LR/LM、robust sandwich cov
- **S5.4** 分位数回归：多 tau、bootstrap SE、rank score、sparsity、IV quantile
- **S5.5** 非线性/门限：exp_growth/logistic/power/gompertz、数值 Jacobian/CI、多起点、多门限、bootstrap CI、sup-Wald
- **S5.6** ARCH/GARCH/GJR/EGARCH：Gaussian/Student-t/skewed-t 分布、forecast、VaR、ES、Kupiec backtest
- **S5.7** 空间计量：SAR/SEM/SDM/SDEM/SAC/SLX/GWR/GTWR/Probit、Moran I、LM tests、kNN/distance-band 权重、效应分解
- **S5.8** 久期模型：Cox PH（Efron/strata/cluster/weights/counting-process）、Schoenfeld 残差、PH 检验、AFT（Weibull/Exponential/Log-normal/Log-logistic）
- **S5.9** 贝叶斯：NIG 共轭、MCMC（R-hat/ESS/trace）、logistic/probit、层级线性模型
- **统一协议**：全部 S5 包实现 model_capabilities + augment_status + WARNING_CODE 注册表
- 开源基础设施：LICENSE（GPL v3）、CONTRIBUTING.md、分层 CI、Issue/PR 模板、CODE_OF_CONDUCT、SECURITY、SUPPORT、CITATION.cff
- 信任底座：包级质量状态矩阵、golden-value 验证政策、OLS golden fixture、benchmark harness、发布前质量门禁
- 外部贡献入口：增强 CONTRIBUTING/SETUP、Issue/PR 模板、轻量标签规范、开发环境脚本、review/triage 规则
- 发布与治理底座：轻量 SemVer、手动 release 流程、支持策略、维护者职责、ADR/RFC 决策记录流程
- 13 篇模型族 CLI 教程、16 个教学 demo 数据集
- CLI-first 桌面工作台（React + Tauri），20+ 专用诊断面板
