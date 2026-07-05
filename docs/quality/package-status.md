# 包级质量状态矩阵

> 最后更新：2026-06-16。当前矩阵以仓库中实际存在的 `packages/*.jl` 为准，共 18 个包。可信度分级见 [credibility-tiers.md](credibility-tiers.md)。

## 状态口径

- `blocking`：PR 前必须完成的本地质量项，失败需先修复。
- `periodic-review`：周期性人工或本地全量检查覆盖，失败必须进入修复队列，但不阻塞普通 PR。
- `manual-input`：已有待外部验证 CSV 输入数据，但尚无经交叉验证的标准答案。
- `not-yet-covered`：尚未建立对应外部验证输入、golden 或 benchmark 覆盖。
- `needs-fix`：已知失败或缺口，需要后续 issue/PR 收口。

## 可信度分级（摘要）

| 级别 | 含义 |
|------|------|
| L1 | 协议形状、Runtime 校验、App 消费一致 |
| L2 | 至少 1 条模型路径完成外部参考验证，并有审计记录与明确容差 |
| L3 | L2 + 可复现外部软件环境，发布前可重复验证 |

## 当前矩阵

| Package | Test status | Quality mode | External validation inputs | Credibility | Benchmark | Known gaps |
|---|---|---|---|---|---|---|
| MetricaBase.jl | required in PR | blocking | contract tests | L1 | not-yet-covered | 协议层不做数值 golden |
| MetricaLinear.jl | required in PR | blocking | OLS / IV / GLS CSV | L1 | OLS and IV harness | 待 Stata / statsmodels 交叉验证 |
| MetricaBayes.jl | required in PR | blocking | conjugate linear CSV | L1 | not-yet-covered | 待闭式公式审计；MCMC 全路径待补 |
| MetricaCausal.jl | required in PR | blocking | DID / IPW / PSM / AIPW / event study CSV | L1 | not-yet-covered | 待 Stata `teffects` 与 Python 复核 |
| MetricaData.jl | required in PR | blocking | data command contract tests | L1 | not-yet-covered | 数据命令做契约验证，不做模型 golden |
| MetricaDiagnostics.jl | required in PR | blocking | not-yet-covered | L1 | not-yet-covered | 待 Stata / statsmodels 诊断统计量复核 |
| MetricaDiscrete.jl | required in PR | blocking | logit / probit / poisson / ordered / multinomial / negbin CSV | L1 | logit harness | 待 Stata / statsmodels 交叉验证 |
| MetricaDuration.jl | required in PR | blocking | Cox CSV | L1 | not-yet-covered | 待 Stata `stcox` 与 statsmodels `PHReg` 复核 |
| MetricaGMM.jl | required in PR | blocking | linear GMM CSV | L1 | GMM harness | 待权重矩阵口径对齐后外部复核 |
| MetricaNonlinear.jl | required in PR | blocking | NLS / threshold demo CSV | L1 | not-yet-covered | 待 Stata `nl` 与 Python grid/curve fit 复核 |
| MetricaOutput.jl | required in PR | blocking | not applicable | L1 | not-yet-covered | 展示层不驱动下游协议 |
| MetricaPanel.jl | required in PR | blocking | panel FE / panel IV / dynamic GMM CSV | L1 | not-yet-covered | 待 Stata 面板命令复核 |
| MetricaQuantile.jl | required in PR | blocking | quantile median CSV | L1 | not-yet-covered | 待 Stata `qreg` 与 statsmodels `QuantReg` 复核 |
| MetricaRuntime.jl | required in PR | blocking | runtime contract tests | L1 | not-yet-covered | 聚合环境 contract 测试待补 |
| MetricaSpatial.jl | required in PR | blocking | spatial lag CSV + W | L1 | spatial_lag harness | 待 Stata spatial 命令复核；statsmodels 核心不覆盖 |
| MetricaSurvey.jl | required in PR | blocking | survey CSV | L1 | not-yet-covered | 待 Stata `svy:` 复核 |
| MetricaSystem.jl | required in PR | blocking | SUR / system equations CSV | L1 | not-yet-covered | 待 Stata `sureg` / `reg3` 复核 |
| MetricaTimeSeries.jl | required in PR | blocking | ARIMA / unitroot / VAR / coint / ARCH / GARCH CSV | L1 | not-yet-covered | 待 Stata / statsmodels 方法口径对齐 |

## 升级规则

包从 L1 升级为 L2 前必须满足：

1. 至少一条关键模型路径完成外部参考验证。
2. 审计记录包含命令、软件版本、样本处理、比较字段和容差。
3. 失败输出能定位模型族、数据集、字段和容差。
4. [golden-values.md](golden-values.md) 与 [manual-golden-command-coverage.md](manual-golden-command-coverage.md) 已同步。

升级为 L3 还需要固定或记录外部验证环境，并能在发布前复跑。
