# Golden-Value 验证政策

Golden-value 测试用于证明 Metrica 的结构化结果与确定性参考值一致。标准用例存放在 `datasets/golden/`，共享测试辅助见 `packages/MetricaBase.jl/test/golden_test_helpers.jl`。

## 文件布局

- 数据：`datasets/golden/<case>.csv`（或 `datasets/demo/` 等，`dataset` 字段相对 `datasets/`）
- 参考值：`datasets/golden/<case>.json`
- 再生脚本：`scripts/golden/compute_<case>_reference.jl`（统一环境 `scripts/golden/Project.toml`）
- 测试入口：各包 `test/test_golden.jl`

## JSON 字段

每个 golden JSON 必须包含：

- `id`：稳定用例名。
- `dataset`：相对 `datasets/` 的路径。
- `model_type`：协议中的模型类型。
- `formula` 或等价模型配置（如 `equations`、`panel_id`）。
- `reference`：参考来源、生成日期、注意事项、`regenerate` 命令。
- `tolerances`：按字段类别声明绝对容差。
- `expected`：结构化期望值，至少覆盖 `glance`、核心 `metrics` 和核心 `tidy` 字段。

## 容差规则

- 协议字段、模型标签、样本量、自由度必须精确匹配。
- 系数、标准误、统计量、拟合指标使用显式 `atol`，不得隐藏在测试代码中。
- 随机或 MCMC 路径必须固定 seed，或只验证 R-hat、ESS、均值区间等稳定摘要。
- 如果参考值来自 Metrica 自身，必须在 `reference.notes` 中说明，后续再替换或补充外部软件对齐。

## 当前覆盖

| Area | Status | Reference target |
|---|---|---|
| OLS | covered (L2) | `scripts/golden/compute_ols_reference.jl` — 独立 complete-case OLS；纳入 `check_golden_drift.jl` 独立 expected 比对 |
| IV / GLS | covered (L2) | `compute_iv_reference.jl` / `compute_gls_reference.jl` — 同上 |
| Logit / Probit / Poisson | covered (L2) | `compute_discrete_*_reference.jl`；R `glm()` L3 见 `scripts/golden/r_smoke/verify_discrete_glm.R` |
| dynamic_panel_gmm | covered (L2) | `compute_panel_dynamic_gmm_reference.jl` |
| Cox PH | covered (L2) | `compute_duration_cox_reference.jl` |
| DID | covered (L2) | `compute_causal_did_reference.jl` |
| SUR | covered (L2) | `compute_system_sur_reference.jl` |
| GMM linear | covered (L2) | `compute_gmm_linear_reference.jl` |
| ARIMA(1,0,0) | covered (L2) | `compute_timeseries_arima_reference.jl` |
| Unitroot (ADF/PP/KPSS) | covered (L2) | `compute_timeseries_unitroot_reference.jl` |
| Quantile τ=0.5 | covered (L2) | `compute_quantile_median_reference.jl` |
| Spatial SAR (spatial_lag) | covered (L2) | `compute_spatial_lag_reference.jl` |
| IPW | covered (L2) | `compute_causal_ipw_reference.jl` |
| Bayes linear (conjugate) | covered (L2) | `compute_bayes_linear_conjugate_reference.jl` — 摘要级，非 MCMC 轨迹 |
| VAR | planned | 滞后阶选择需单独漂移政策 |
| Bayes MCMC | planned | R-hat/ESS 摘要 golden |

Credibility 分级见 [credibility-tiers.md](credibility-tiers.md)。包级矩阵见 [package-status.md](package-status.md)。

## 本地与 CI

```bash
make test-golden          # schema + 含 golden 的包测试
julia --project=scripts/golden scripts/golden/check_golden_json.jl
REGENERATE_GOLDEN=check julia --project=scripts/golden scripts/golden/check_golden_drift.jl
```

Drift 含 **17 项**：3 个独立线性参考（OLS/IV/GLS 的 `expected` 段）+ 14 个 Metrica 全量 JSON 再生器。

PR 在改动 `datasets/golden/**` 或相关包时触发 CI `golden-test` job（见 `.github/workflows/ci.yml`）。

## 未来事项

### Rust params 强类型 wire 格式

当前 `ModelSpec.params` 在 Rust 侧为 `serde_json::Value`，校验后收敛为 `ValidatedModelParams` 枚举。未来可将 `Value` 替换为 serde 标签枚举。延后至下一开发阶段考虑。
