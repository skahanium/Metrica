# 包级质量状态矩阵

> 最后更新：2026-06-03。当前矩阵以仓库中实际存在的 `packages/*.jl` 为准，共 18 个包。可信度分级见 [credibility-tiers.md](credibility-tiers.md)。

## 状态口径

- `blocking`：PR CI 阻塞项，失败会阻止合并。
- `nightly-observed`：nightly/full quality workflow 覆盖，失败必须进入修复队列，但不阻塞普通 PR。
- `covered`：`datasets/golden/<id>.json` 标准用例 + 再生脚本 + 包内 golden 测试。
- `internal-fixture`：包内确定性 fixture，尚未升格为标准 JSON golden。
- `planned`：尚未建立对应 golden 或 benchmark 覆盖。
- `needs-fix`：已知失败或缺口，需要后续 issue/PR 收口。

## 可信度分级（摘要）

| 级别 | 含义 |
|------|------|
| L1 | 协议形状、Runtime 校验、App 消费一致 |
| L2 | 至少 1 个标准 JSON golden + 独立再生脚本 + 明示容差 |
| L3 | L2 + 文档化外部参考（如 R）可复现 |

## 当前矩阵

| Package | Test status | CI mode | Golden coverage | Credibility | Benchmark | Known gaps |
|---|---|---|---|---|---|---|
| MetricaBase.jl | required in PR | blocking | contract tests | L1 | not-yet-covered | 协议 warning 契约 golden 在 Base 测试层 |
| MetricaLinear.jl | required in PR | blocking | OLS, IV, GLS (`datasets/golden/linear_*.json`) | L2 | OLS and IV harness | L3 R 抽检为可选 nightly（见 scripts/golden/README.md） |
| MetricaBayes.jl | required in PR | blocking | `bayes_linear_conjugate`（摘要级） | L2 | not-yet-covered | MCMC 全路径 golden 待补；共轭路径已锁 posterior mean |
| MetricaCausal.jl | required in PR | blocking | DID, IPW (`causal_did.json`, `causal_ipw.json`) | L2 | not-yet-covered | AIPW 公共参考待补；DID L3 smoke 见 `verify_causal_did.R` |
| MetricaData.jl | required in PR | blocking | query glance 协议测试 | L1 | not-yet-covered | `inspect`/`describe`/`summarize`/`tabulate`/`browse` 已返回 `ModelGlance` 形 glance；transform 错误路径有结构测试 |
| MetricaDiagnostics.jl | required in PR | blocking | not-yet-covered | L1 | not-yet-covered | 跨模型诊断一致性待补 |
| MetricaDiscrete.jl | required in PR | blocking | logit, probit, poisson | L2 | logit harness | L3 R `glm` 对齐为后续抽检 |
| MetricaDuration.jl | required in PR | blocking | Cox PH (`duration_cox.json`) | L2 | not-yet-covered | AFT 与 R survival 全面对齐待补 |
| MetricaGMM.jl | required in PR | blocking | `gmm_linear` golden | L2 | GMM harness | Hansen J 外部参考待补 |
| MetricaNonlinear.jl | required in PR | blocking | not-yet-covered | L1 | not-yet-covered | 多起点/门限稳定 fixture 待补 |
| MetricaOutput.jl | required in PR | blocking | not-yet-covered | L1 | not-yet-covered | 展示层不驱动下游协议 |
| MetricaPanel.jl | required in PR | blocking | dynamic_panel_gmm | L2 | not-yet-covered | L3 宽松 smoke：`verify_panel_gmm.R` |
| MetricaQuantile.jl | required in PR | blocking | `quantile_median` | L2 | not-yet-covered | bootstrap/IV quantile 容差政策待补 |
| MetricaRuntime.jl | required in PR | blocking | not-yet-covered | L1 | not-yet-covered | 聚合环境 contract 测试待补 |
| MetricaSpatial.jl | required in PR | blocking | `spatial_lag` | L2 | spatial_lag harness | GWR 仍为 internal-fixture；SAR L3 R 待补 |
| MetricaSurvey.jl | required in PR | blocking | not-yet-covered | L1 | not-yet-covered | 复杂抽样 R survey 对齐待补 |
| MetricaSystem.jl | required in PR | blocking | SUR (`system_sur.json`) | L2 | not-yet-covered | 3SLS 外部参考待补 |
| MetricaTimeSeries.jl | required in PR | blocking | ARIMA, unitroot (`timeseries_*.json`) | L2 | not-yet-covered | VAR 扩展 golden 待补 |

## golden 升级规则

包从 `internal-fixture` 升级为 `covered`（L2）前必须满足：

1. 关键模型路径至少有一个 `datasets/golden/<id>.json` 用例。
2. 配有 `scripts/golden/compute_<id>_reference.jl` 或等价公开再生步骤。
3. 失败输出能定位模型族、数据集、字段和容差（使用 `GoldenTestHelpers`）。
4. [package-status.md](package-status.md) 与 [golden-values.md](golden-values.md) 已同步。

升级为 L3  additionally 需要：

1. `reference.source` 标明外部软件与版本。
2. [scripts/golden/README.md](../../scripts/golden/README.md) 中有一条命令可复现对比。
