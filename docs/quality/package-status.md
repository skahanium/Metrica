# 包级质量状态矩阵

> 最后更新：2026-05-18。当前矩阵以仓库中实际存在的 `packages/*.jl` 为准，共 18 个包。

## 状态口径

- `blocking`：PR CI 阻塞项，失败会阻止合并。
- `nightly-observed`：nightly/full quality workflow 覆盖，失败必须进入修复队列，但不阻塞普通 PR。
- `not-yet-covered`：尚未建立对应 golden 或 benchmark 覆盖。
- `needs-fix`：已知失败或缺口，需要后续 issue/PR 收口。

## 当前矩阵

| Package | Test status | CI mode | Golden coverage | Benchmark coverage | Known gaps |
|---|---|---|---|---|---|
| MetricaBase.jl | required in PR | blocking | not-yet-covered | not-yet-covered | 协议层需继续补结构化 warning/generic contract golden |
| MetricaLinear.jl | required in PR | blocking | OLS, IV, GLS internal deterministic fixtures covered | OLS and IV harness covered | IV/GLS 尚未对齐外部参考软件 |
| MetricaBayes.jl | required in PR | blocking | not-yet-covered | not-yet-covered | MCMC 结果需固定 seed 或摘要容差 |
| MetricaCausal.jl | required in PR | blocking | not-yet-covered | not-yet-covered | DID/IPW/AIPW 需公共参考案例 |
| MetricaData.jl | required in PR | blocking | not-yet-covered | not-yet-covered | 数据操作需补协议形状测试 |
| MetricaDiagnostics.jl | required in PR | blocking | not-yet-covered | not-yet-covered | 诊断输出需补跨模型一致性测试 |
| MetricaDiscrete.jl | required in PR | blocking | logit/probit/poisson planned | logit harness covered | GLM 对齐用例待补 |
| MetricaDuration.jl | required in PR | blocking | not-yet-covered | not-yet-covered | Cox/AFT 需对齐 R survival |
| MetricaGMM.jl | required in PR | blocking | planned | GMM harness covered | Hansen J / C-stat 外部参考待补 |
| MetricaNonlinear.jl | required in PR | blocking | not-yet-covered | not-yet-covered | 多起点/门限结果需稳定 fixture |
| MetricaOutput.jl | required in PR | blocking | not-yet-covered | not-yet-covered | 展示层需保证不驱动下游协议 |
| MetricaPanel.jl | required in PR | blocking | planned | not-yet-covered | 动态面板 GMM 外部对齐待补 |
| MetricaQuantile.jl | required in PR | blocking | not-yet-covered | not-yet-covered | bootstrap/IV quantile 容差政策待补 |
| MetricaRuntime.jl | required in PR | blocking | not-yet-covered | not-yet-covered | 聚合环境 contract 测试待补 |
| MetricaSpatial.jl | required in PR | blocking | planned | spatial_lag harness covered | 空间权重与效应分解外部对齐待补 |
| MetricaSurvey.jl | required in PR | blocking | not-yet-covered | not-yet-covered | 复杂抽样需对齐 R survey |
| MetricaSystem.jl | required in PR | blocking | not-yet-covered | not-yet-covered | SUR/3SLS 外部对齐待补 |
| MetricaTimeSeries.jl | required in PR | blocking | ARIMA/VAR/unitroot planned | not-yet-covered | 时序参考结果与容差待补 |

## golden 升级规则

包从内部 deterministic fixture 升级为外部参考 golden 前必须满足：

1. 关键模型路径至少有一个 golden-value fixture。
2. 参考值来自公开可复现的软件或脚本（如 R / Stata / statsmodels）。
3. 失败输出能定位模型族、数据集、字段和容差。
4. 对用户可感知行为的文档口径已经同步。
