# Manual External Validation Command Coverage

本文件记录 Metrica CLI 命令的手动外部验证覆盖设计。目标是为每个命令提供可执行的验证路径：数据路径、Metrica 命令、Stata 验证方式、statsmodels/Python 验证方式，以及该命令适合沉淀成哪一类外部验证证据。

说明：

- 数据可以先用确定性脚本或 AI 辅助生成，但标准答案必须来自 Stata、statsmodels/Python、可审查闭式公式，或明确记录的人工审计结果。
- Stata 与 statsmodels 都按手动本地验证处理，不假设公开远程环境可以运行商业 Stata 或特定 Python 环境。
- 无法被 Stata/statsmodels 稳定覆盖的命令，需要明确标注为 `external-limited`、`公式候选` 或 `not applicable`，不得伪装成双参考候选。
- `datasets/golden/` 中的数据是手动外部验证输入数据；标准答案仍需由 Stata、statsmodels/Python 或闭式公式生成并记录。

## Command Coverage

| Metrica 命令 | 数据路径 | Stata 验证 | statsmodels / Python 验证 | 目标 |
|---|---|---|---|---|
| `regress y x1 x2` | `datasets/golden/linear_ols.csv` | `regress y x1 x2` | `sm.OLS(y, add_constant(X)).fit()` | 双参考候选 |
| `gls y x1 x2` | `datasets/golden/linear_gls.csv` | `regress` 或 `vwls` 对齐权重设定 | `sm.GLS(y, X, sigma=...)` | 双参考候选 |
| `ivregress y x1 x2, endogenous(x1) instruments(z1 z2)` | `datasets/golden/linear_iv.csv` | `ivregress 2sls y x2 (x1 = z1 z2)` | `statsmodels.sandbox.regression.gmm.IV2SLS` | 至少 Stata 候选 |
| `gmm y x1 x2, endogenous(x1) instruments(z1 z2)` | `datasets/golden/gmm_linear.csv` | `ivregress gmm` 或 `gmm` | statsmodels GMM sandbox | 单参考起步 |
| `qreg y x1 x2, quantile(0.5)` | `datasets/golden/quantile_median.csv` | `qreg y x1 x2, quantile(.5)` | `sm.QuantReg(y, X).fit(q=.5)` | 双参考候选 |
| `logit y x1 x2` | `datasets/golden/discrete_logit.csv` | `logit y x1 x2` | `sm.Logit(y, X).fit()` | 双参考候选 |
| `probit y x1 x2` | `datasets/golden/discrete_probit.csv` | `probit y x1 x2` | `sm.Probit(y, X).fit()` | 双参考候选 |
| `poisson y x1 x2` | `datasets/golden/discrete_poisson.csv` | `poisson y x1 x2` | `sm.Poisson(y, X).fit()` | 双参考候选 |
| `ologit y x1 x2` | `datasets/golden/ordered_logit.csv` | `ologit y x1 x2` | `OrderedModel(..., distr="logit")` | 双参考候选 |
| `mlogit y x1 x2` | `datasets/golden/multinomial_logit.csv` | `mlogit y x1 x2` | `MNLogit(y, X).fit()` | 双参考候选 |
| `nbreg y x1 x2` | `datasets/golden/negbin.csv` | `nbreg y x1 x2` | `NegativeBinomial(y, X).fit()` | 双参考候选 |
| `xtreg y x1 x2, id(firm) time(year) method(fe)` | `datasets/demo/grunfeld.csv`；必要时另行生成小面板 | `xtset firm year`; `xtreg y x1 x2, fe` | `PanelOLS` 若安装 linearmodels；否则 Python 去均值 OLS | Stata 候选 |
| `xtivreg y x1 x2, id(firm) time(year) method(fe) endogenous(x1) instruments(z1 z2)` | `datasets/golden/panel_iv.csv` | `xtivreg y x2 (x1=z1 z2), fe` | Python 去均值后 IV2SLS | Stata 候选 |
| `xtabond y x, id(firm) time(year) lags(2 4) weight(two_step)` | `datasets/demo/dynamic_panel_gmm_golden.csv` | `xtabond` 或 `xtdpdgmm` | 不强制 statsmodels | Stata audit |
| `did y, id(id) time(time) treat(treated) post(post)` | `datasets/golden/causal_did.csv` | `regress y i.treated##i.post` | OLS with interaction dummies | 双参考候选 |
| `eventstudy y, id(id) time(time) treat(treated) eventtime(event_time)` | `datasets/golden/event_study.csv` | `regress y i.event_time##i.treated` | OLS dummy design | 双参考候选 |
| `ipw y x1 x2, treat(treat) outcome(y)` | `datasets/golden/causal_ipw.csv` | `teffects ipw (y) (treat x1 x2, logit)` | Logit propensity + weighted ATE | 双参考 audit |
| `psm y x1 x2, treat(treat) outcome(y)` | `datasets/golden/psm.csv` | `teffects psmatch` | nearest-neighbor propensity matching | 单参考起步 |
| `aipw y x1 x2, treat(treat) outcome(y)` | `datasets/golden/aipw.csv` | `teffects aipw` | Logit PS + outcome model formula | 双参考 audit |
| `sur (y1 x1 x2) (y2 x1 x2)` | `datasets/demo/sur_system_demo.csv` | `sureg (y1 x1 x2) (y2 x1 x2)` | statsmodels SUR if available, else skip | Stata 候选 |
| `reg3 (...)` | `datasets/demo/system_2sls_demo.csv` | `reg3 (...) , 2sls/3sls` | no stable statsmodels baseline | Stata 候选 |
| `arima y, time(time) ar(1) i(0) ma(0)` | `datasets/golden/timeseries_arima.csv` | `tsset time`; `arima y, arima(1,0,0)` | `ARIMA(y, order=(1,0,0)).fit()` | method-aligned audit |
| `var y x, time(time) lags(1)` | `datasets/golden/var.csv` | `tsset time`; `var y x, lags(1/1)` | `VAR(df).fit(1)` | 双参考候选 |
| `dfuller y, time(time)` | `datasets/golden/timeseries_unitroot.csv` | `dfuller y` | `adfuller(y, regression="c")` | 双参考候选 for ADF |
| `coint y x, time(time)` | `datasets/golden/cointegration.csv` | `egranger` or Johansen command depending availability | `statsmodels.tsa.stattools.coint` | 部分外部候选 |
| `arch y, time(time) arch(1)` | `datasets/demo/garch_demo.csv` | `arch y, arch(1)` if available | `arch` Python package preferred, statsmodels limited | 可选外部候选 |
| `garch y, time(time) arch(1) garch(1)` | `datasets/demo/garch_demo.csv` | `arch y, arch(1) garch(1)` | `arch_model(..., p=1, q=1)` | 可选外部候选 |
| `spreg y x1, weights("...") id(region) model(lag)` | `datasets/golden/spatial_lag.csv` + W | Stata `spregress` if spatial setup succeeds | no statsmodels core equivalent | Stata audit |
| `gwr`, `gtwr`, `spprobit` | `datasets/demo/spatial_demo_coords.csv` or new small data | Stata availability varies | no stable statsmodels baseline | mark external-limited |
| `stcox time fail x1` | `datasets/golden/duration_cox.csv` | `stset time, failure(fail)`; `stcox x1` | `PHReg(...).fit()` | dual audit if tie handling aligns |
| `svy ols/logit/probit/poisson ...` | `datasets/golden/survey.csv` | `svyset`; `svy: regress/logit/probit/poisson` | statsmodels survey limited | Stata 候选 |
| `nls y x, family(exp_growth) start(...)` | `datasets/demo/nls_threshold_demo.csv` | `nl (y = {b1}+{b2}*exp({b3}*x))` | `scipy.optimize.curve_fit` | dual audit, statsmodels not required |
| `threg y x q, qvar(q) grid(...)` | `datasets/demo/nls_threshold_demo.csv` | grid OLS loop in do-file | Python grid OLS loop | dual 公式候选 |
| `bayesreg y x1 x2` | `datasets/golden/bayes_linear_conjugate.csv` | not applicable | closed-form Python/Numpy conjugate reference | 公式候选 |

## Manual Datasets

以下数据集已作为手动外部验证输入创建。后续应在同一验证批次中补充 Stata / Python 验证脚本或审计记录。

| 数据路径 | 覆盖命令 |
|---|---|
| `datasets/golden/ordered_logit.csv` | `ologit` |
| `datasets/golden/multinomial_logit.csv` | `mlogit` |
| `datasets/golden/negbin.csv` | `nbreg` |
| `datasets/golden/panel_iv.csv` | `xtivreg` |
| `datasets/golden/event_study.csv` | `eventstudy` |
| `datasets/golden/psm.csv` | `psm` |
| `datasets/golden/aipw.csv` | `aipw` |
| `datasets/golden/var.csv` | `var` |
| `datasets/golden/cointegration.csv` | `coint` |
| `datasets/golden/survey.csv` | `svy` |

## Non-Model Commands

| 命令类别 | 命令 | 验证方式 | 目标 |
|---|---|---|---|
| 数据读取 | `use` | Stata `import delimited`；pandas `read_csv` | 文件加载、列名、行数一致 |
| 数据查看 | `describe`、`browse` | Stata `describe` / `list`；pandas schema/head | 结构化字段、预览行一致 |
| 描述统计 | `summarize`、`tabulate` | Stata `summarize, detail` / `tabulate`；pandas `describe` / `value_counts` | N、均值、分位数、频数一致 |
| 数据变换 | `filter`、`generate`、`replace`、`drop`、`keep`、`rename`、`sort` | Stata 数据管理命令；pandas 等价操作 | 行数、列名、关键值一致 |
| 合并与重塑 | `merge`、`reshape`、`collapse` | Stata `merge` / `reshape` / `collapse`；pandas merge/pivot/groupby | schema 与聚合结果一致 |
| 诊断 | `hettest`、`ovtest`、`vif`、`dwstat`、`bgodfrey`、`hausman` | Stata 原生命令为主；statsmodels diagnostic functions 补充 | 统计量和 p 值一致或明确容差 |
| 后估计 | `predict`、`margins`、`test`、`lincom`、`estimates` | Stata postestimation；statsmodels prediction/wald_test | 预测值、残差、线性组合、Wald/F 统计量一致 |
| 项目与导出 | `project`、`save`、`export` | 不属于统计 golden；检查文件存在性、schema 与 round-trip | contract test |
