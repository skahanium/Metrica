# Metrica 项目技术评估（可信度基线）

> **评估日期：** 2026-06-01  
> **分支基准：** `credibility-support` / `main`（含 golden 体系与 P0 门禁）  
> **方法：** 源码与 CI/质量文档对照  

## 总体

三层架构与结构化协议（`glance` / `tidy` / `augment`、结构化警告）已落地。完善阶段 P0（18 包测试 + Runtime 串行集成 + 对齐脚本）已完成。

**评分（2026-06-01）：** 架构 A-；实现 B+；验证与 golden **B**（较 2026-05-24 评估提升）；开源就绪 B+。

README 仍建议「不可用于生产或未经审阅的正式研究」；线性 + 离散 GLM + 面板 GMM + Cox + DID + SUR 已具备 L2 golden，可参见 [credibility-tiers.md](credibility-tiers.md) 阶梯叙述。

## Golden 与测试

| 项目 | 状态 |
|------|------|
| 标准 JSON 用例 | 17（见 `datasets/golden/*.json`） |
| 共享辅助 | `GoldenTestHelpers`（MetricaBase 测试层） |
| 快路径 | `make test-golden` / CI `golden-test` |
| MetricaData 测试 | 多文件（query/inspect/operate/transform 等），非 2025 初评「21 行」口径 |
| MetricaLinear | golden OLS/IV/GLS + 大量 DGP 测试 |

## 下一步 30 天（可信度主线，2026-06-03）

执行锚点：与 [AGENTS.md](../../AGENTS.md)、[CONTRIBUTING.md](../../CONTRIBUTING.md) 一致；任务状态以 [package-status.md](package-status.md) 为准。

- [x] 文档锚点与路线图口径统一（Sprint 0）
- [x] **Quantile / Spatial** 升格 L2：`quantile_median`、`spatial_lag`
- [x] **Causal IPW**、**TimeSeries unitroot**、**Bayes 摘要**：`causal_ipw`、`timeseries_unitroot`、`bayes_linear_conjugate`
- [x] **MetricaData**：`transform` 链错误路径结构测试（`test_glance_protocol.jl`）
- [x] **L3**：`golden-r-smoke.yml` 增加 DID / Cox / panel GMM 脚本
- [x] **发版**：`make test-golden`、golden drift（17 项）、`0.1.1` 已写入 CHANGELOG / CITATION / README；合并前建议再跑 `make test-p0`

## 后续（非阻塞）

- 更多族的 L3 R 抽检（Survey、Panel `plm` 等）
- VAR 等时序 golden（滞后阶选择带来的漂移需单独政策）
- S6 安装包与分发（可信度覆盖面达标后再开主线）

历史详评见仓库根目录 `PROJECT_REVIEW.md`（2026-05-24 快照，**可能滞后**；以本文件与 package-status 为准）。
