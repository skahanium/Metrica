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
| 标准 JSON 用例 | 10+（见 `datasets/golden/*.json`） |
| 共享辅助 | `GoldenTestHelpers`（MetricaBase 测试层） |
| 快路径 | `make test-golden` / CI `golden-test` |
| MetricaData 测试 | 多文件（query/inspect/operate/transform 等），非 2025 初评「21 行」口径 |
| MetricaLinear | golden OLS/IV/GLS + 大量 DGP 测试 |

## 后续（非本分支阻塞）

- 离散/面板等族的 L3 R 抽检（`golden-r-smoke.yml`）
- MetricaData 与 `ModelGlance` 信封统一
- TimeSeries / Bayes 摘要 golden

历史详评见仓库根目录 `PROJECT_REVIEW.md`（2026-05-24 快照，可能滞后于本文件）。
