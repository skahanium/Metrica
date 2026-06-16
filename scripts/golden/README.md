# Golden-value 再生与外部参考

标准布局见 [docs/quality/golden-values.md](../../docs/quality/golden-values.md)。

## 目录

| 路径 | 说明 |
|------|------|
| `datasets/golden/<id>.csv` | 用例数据 |
| `datasets/golden/<id>.json` | 期望值与容差 |
| `scripts/golden/compute_<id>_reference.jl` | 独立参考实现或 Metrica 导出 |
| `packages/*/test/test_golden.jl` | 包内对齐测试 |

## 再生（Julia）

在仓库根目录执行（推荐统一环境 `scripts/golden/Project.toml`）：

```bash
julia --project=scripts/golden -e 'using Pkg; Pkg.instantiate()'
julia --project=scripts/golden scripts/golden/compute_ols_reference.jl
julia --project=scripts/golden scripts/golden/compute_iv_reference.jl
julia --project=scripts/golden scripts/golden/compute_gls_reference.jl
```

独立参考（OLS/IV/GLS）在 drift 检查中比对 `expected` 段，不依赖 Metrica 拟合；Metrica 全量再生脚本见：

```bash
julia --project=scripts/golden scripts/golden/compute_discrete_logit_reference.jl
julia --project=scripts/golden scripts/golden/compute_discrete_probit_reference.jl
julia --project=scripts/golden scripts/golden/compute_discrete_poisson_reference.jl
julia --project=scripts/golden scripts/golden/compute_panel_dynamic_gmm_reference.jl
julia --project=scripts/golden scripts/golden/compute_duration_cox_reference.jl
julia --project=scripts/golden scripts/golden/compute_causal_did_reference.jl
julia --project=scripts/golden scripts/golden/compute_system_sur_reference.jl
julia --project=scripts/golden scripts/golden/compute_gmm_linear_reference.jl
julia --project=scripts/golden scripts/golden/compute_timeseries_arima_reference.jl
julia --project=scripts/golden scripts/golden/compute_quantile_median_reference.jl
julia --project=scripts/golden scripts/golden/compute_spatial_lag_reference.jl
julia --project=scripts/golden scripts/golden/compute_causal_ipw_reference.jl
julia --project=scripts/golden scripts/golden/compute_timeseries_unitroot_reference.jl
julia --project=scripts/golden scripts/golden/compute_bayes_linear_conjugate_reference.jl
```

维护者更新 JSON 后运行：

```bash
bash scripts/dev/test-golden.sh
julia scripts/golden/check_golden_json.jl
REGENERATE_GOLDEN=check julia --project=scripts/golden scripts/golden/check_golden_drift.jl
```

## 本地 golden 快路径

```bash
make test-golden
```

## R 外部参考（L3，可选）

PR **不**要求安装 R。夜间或手动 smoke 使用：

- **R** ≥ 4.2
- 包：`stats`、`lmtest`、`ivreg`（IV）、`survival`（Cox）、`glm`（离散 logit/probit/poisson）

离散 glm 一键 smoke：`Rscript scripts/golden/r_smoke/verify_discrete_glm.R`

示例（OLS，与 `linear_ols.csv` 同设计）：

```r
df <- read.csv("datasets/golden/linear_ols.csv")
fit <- lm(y ~ x1 + x2, data = df)
coef(fit)
```

IV（与 `linear_iv.csv`）：

```r
library(ivreg)
df <- read.csv("datasets/golden/linear_iv.csv")
fit <- ivreg(y ~ x1 + x2 | x1 + z1 + z2, data = df)
coef(fit)
```

Workflow：`.github/workflows/golden-r-smoke.yml`（`workflow_dispatch` + 每周 schedule，失败不阻塞 PR）。另含 DID / Cox / panel GMM 宽松 smoke（`verify_causal_did.R`、`verify_duration_cox.R`、`verify_panel_gmm.R`）。

## 当前标准用例 id

见 `datasets/golden/*.json`；包级映射见 [docs/quality/package-status.md](../../docs/quality/package-status.md)。
