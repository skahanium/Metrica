# S5.9 贝叶斯线性回归（规划与协议对齐）

本教程对应规划中的 `model_type: "bayes_linear"` 与 App / CLI 动词 **`bayesreg`**。**代码实现尚未合入主线时**，以下命令与 JSON 字段以 [`docs/architecture/runtime-protocol.md`](../docs/architecture/runtime-protocol.md) **`bayes_linear`** 专节与 [`docs/superpowers/plans/2026-05-16-s5-execution-plan.md`](../docs/superpowers/plans/2026-05-16-s5-execution-plan.md) **「S5.9」** 为准；实施完成后将在此补充演示数据路径与可复制命令块。

## 1. 命令形态（规划）

```text
bayesreg y x1 x2
```

- 与 `reg` 类似：左侧为因变量，其余为协变量，解析为公式 **`y ~ x1 + x2`**（含截距规则与线性族一致）。
- 若 App 引入 `seed(...)`、`chains(...)` 等选项，须一一映射到 `model_spec` 的 **`bayes_seed`、`bayes_chains`** 等键（见协议专节）。

## 2. Credible interval 与 frequentist CI

- **`tidy` 中的 `ci_lower` / `ci_upper`**（规划约定）表示在 **后验分布** 下的 **可信区间（credible interval）**，语义为：参数落在区间内的 **后验概率**（在报告的分位口径下，如等尾 95%）。
- **频率学派 OLS** 的置信区间（confidence interval）基于重复抽样下覆盖概率，**不是**后验概率陈述。
- 规划要求：贝叶斯路径下 **`stderror`、`pvalue` 等频率列置 `null`**，避免把 credible 误读为「在零假设下的显著性」。

## 3. `bayes_seed` 与可复现性

- **`bayes_seed`** 用于控制任何 **随机** 步骤（例如未来 MCMC、或数据子采样若引入）。
- **首期默认推断路径 A（解析/共轭）** 下，若实现中无随机采样，仍应在 **`diagnostics.seed_used`**（或与 `model_spec` 对齐的字段）中记录请求中的种子，便于审计与教学说明「本运行未使用 MCMC」。

## 4. `diagnostics` 字段怎么读（规划）

- **`inference_mode`**：`"analytical"` 表示共轭/解析后验；**`r_hat`、`ess`** 等为 **`null`** 且附带 **`mcmc_not_applicable_reason`** 时，表示 **未做 MCMC**，因此 **没有** R-hat／有效样本量——这是 **结构化诚实**，不是输出缺失。
- 若未来 **`inference_mode: "mcmc"`**（仅环境门控 + 硬上限启用），再阅读 `r_hat`、`ess`、`divergences` 等键；详见协议专节。

## 5. 首期限制（规划摘要）

- 仅 **单方程高斯线性**似然 + **冻结**先验族；不开放任意概率 DSL。
- **σ² 已知** 与 **σ² 未知（InvGamma 共轭）** 为 **互斥** 分支，由 `bayes_sigma2_known` / `bayes_sigma2_value` 与 `bayes_ig_alpha` / `bayes_ig_beta` 约定（见协议表）。
