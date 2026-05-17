# Runtime 协议

## 动作列表

### 第一阶段动作（S1/S2）

- `inspect_dataset`
- `query_dataset`
- `fit_model`
- `transform`

### 诊断动作

- `run_diagnostic` — 在已有拟合上下文上运行结构化诊断（HTTP 入口；载荷与 Julia 侧见实现）。

### S3 项目系统动作

- `save_project` — 保存项目清单到 `.metrica/project.json`
- `load_project` — 从 `.metrica/project.json` 加载项目清单
- `list_runs` — 列出 `.metrica/runs/` 下的所有运行记录
- `rerun_task` — 根据历史运行记录重新执行任务
- `export_report` — 导出运行报告（Markdown / CSV）

每个请求必须包含 `task_id`、`action`、`project_context` 以及动作相关载荷。  
每个响应必须包含 `task_id`、`status`、`messages`，以及可选的 `result_payload`。

## 传输方式

### 当前实现（axum HTTP）

当前链路通过 axum HTTP 框架暴露 Runtime（默认绑定 `127.0.0.1:47821`）。下列路径与 `runtime/metrica-runtime/src/server.rs` 中 `build_router` 一致；`OPTIONS` 由全局 `CorsLayer` 处理，与具体 `POST` 路由成对出现。

**持久化会话模式（默认）**

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/health` | 会话健康 |
| `GET` | `/session/env` | 变量环境 |
| `POST` | `/inspect_dataset` | 数据检查 |
| `POST` | `/query_dataset` | 只读数据命令（describe / browse / summarize / tabulate） |
| `POST` | `/fit_model` | 模型拟合 |
| `POST` | `/transform` | 数据变换 |
| `POST` | `/run_diagnostic` | 诊断检验 |
| `POST` | `/save_project` | 保存项目 |
| `POST` | `/load_project` | 加载项目 |
| `POST` | `/list_runs` | 列出运行记录 |
| `POST` | `/rerun_task` | 重跑历史任务 |
| `POST` | `/export_report` | 导出报告 |

**`--oneshot` 回退模式：** 路由为子集（见 `build_oneshot_router`）：含 `health`、`fit_model`、`inspect_dataset`、`query_dataset` 与项目类 `save_project` / `load_project` / `list_runs`；**不含** `transform`、`run_diagnostic`、`rerun_task`、`export_report`。文档与 App 须将上述缺失视为回退模式限制。

该 HTTP 层只负责搬运结构化请求与响应，不承载计量逻辑本身。

## `fit_model` 与 `model_type`（`S4` 当前枚举）

`model_spec.model_type` 为**白名单字符串**，由 `scripts/julia_bridge_entry.jl`（及时间序列独立桥接、**空间专用分支**等）与 `MetricaBase.MODEL_REGISTRY`（若适用）共同约束；Runtime 仅做 schema 与字段完整性校验，不解释计量语义。

| 模型族 | `model_type` 取值（当前） |
|--------|---------------------------|
| 线性 | `ols`、`iv`、`gmm_linear`、`quantile`、`gls`（WLS 等通过 `options` / 权重字段走线性流水线，见实现） |
| 非线性与门限（S5.5） | `nls`、`threshold`（`packages/MetricaNonlinear.jl`；受控白名单与网格搜索） |
| 系统方程（S5.3） | `sur`、`system_2sls`、`system_3sls`（`packages/MetricaSystem.jl`） |
| 面板 | `panel`、`panel_iv`、`dynamic_panel_gmm` |
| 时间序列 | `arima`、`var`、`unitroot`、`cointegration`、`arch`、`garch`、`gjr_garch`、`egarch`（波动率模型走 `julia_time_series_bridge_entry.jl` + `MetricaTimeSeries.jl`） |
| 离散 | `logit`、`probit`、`poisson`、`ordered_logit`、`multinomial_logit`、`negbin` |
| 因果 | `did`、`event_study`、`ipw`、`psm`、`aipw` |
| 复杂抽样 | `survey_ols`、`survey_logit`、`survey_probit`、`survey_poisson` |
| 空间（S5.7） | `spatial_lag`/`spatial_error`/`spatial_slx`/`spatial_sdm`/`spatial_sdem`/`spatial_sac`/`spatial_gwr`/`spatial_gtwr`/`spatial_probit`（`packages/MetricaSpatial.jl`；专用分支） |
| 久期（S5.8） | `duration_cox`/`aft_weibull`/`aft_exponential`/`aft_lognormal`/`aft_loglogistic`（`packages/MetricaDuration.jl`；专用分支） |
| 贝叶斯（S5.9） | `bayes_linear`/`bayes_logistic`/`bayes_hierarchical`（`packages/MetricaBayes.jl`；专用分支） |

### `S5` 扩展规则（摘要）

- 新高级专题（如 `gmm_linear`）仍须走 **`fit_model` 信封**（或未来经设计新增的白名单 `action`，不得使用自由文本替代结构化 `model_spec`）。
- 每个新类型必须返回结构化 **`glance`、`tidy`、`diagnostics`、`warnings`** 与可用时的 **`model_capabilities`**（及现有载荷约定中的扩展字段），App 只消费结构化字段。
- 在 Julia 侧注册 `MODEL_REGISTRY`（**若适用**；空间模型等可走专用分支）并在桥接入口增加派发；同步更新本文件上表与 CLI 语法文档。
- 详见 [`S5-模型族全量成熟化施工方案.md`](../../S5-模型族全量成熟化施工方案.md) 与 [`docs/roadmap/s5-advanced-research-topics.md`](../roadmap/s5-advanced-research-topics.md)。

### `quantile`（线性分位数回归，单 τ）

**`ModelSpec` 字段（除通用 `formula` / `dataset_ref` 外）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | 固定为 `quantile` |
| `quantile_tau` | 数 | 否 | 分位点 \(\tau\)；JSON 省略时按 **0.5** 处理；Runtime 要求 **有限** 且 **\(10^{-8} < \tau < 1-10^{-8}\)**。 |

**不转发字段：** 桥接对 `quantile` 不传 `vcov` / `weights` / `cluster`（与 `gmm_linear` 相同），避免 `MethodError`。推断为首期 **渐近核** 口径（见 Julia `diagnostics.inference_kind`）。

**`result_payload`：** 与线性族相同的 `glance` / `tidy` / `warnings` 结构；`glance.metrics` 含 **`tau`**、**`pseudo_r2`**（McFadden 型 check 损失比）。`diagnostics` 含 `tau`、`inference_kind`（如 `asymptotic_kernel`）、`rank_X`、`cond_X`、`solver`（如 `QuantileRegressions.IP`）、`pseudo_r2_definition` 等。

**CLI（App）：** `qreg y x1 x2, quantile(0.5)`；省略 `quantile(...)` 时默认 \(\tau=0.5\)。教程见 [`tutorials/s5-quantile-regression.md`](../../tutorials/s5-quantile-regression.md)。

### `nls`（受控非线性最小二乘，首期白名单）

**`ModelSpec` 字段（除通用 `formula` / `dataset_ref` 外）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | 固定为 `nls` |
| `nls_family` | 字符串 | 否 | 首期仅 **`exp_growth`**（\(\mu=\beta_1+\beta_2\exp(\beta_3 z)\)，\(z\) 为公式右侧除截距外第一个数值列）；省略时 Julia 端按 `exp_growth` 处理；Runtime 拒绝其它枚举值。 |
| `nls_start` | 数数组 | 是 | 长度 **3** 的初值向量，须全为有限数。 |
| `nls_max_iter` | 整数 | 否 | 传递给 Optim；省略时使用 Julia 端默认。 |
| `nls_tol` | 数 | 否 | 目标相对容差；省略时使用 Julia 端默认。 |

**不转发字段：** 与 `quantile` 相同，桥接对 `nls` 不传 `vcov` / `weights` / `cluster` / `instruments` 等线性族关键字。

**`result_payload.diagnostics`（示例键）：** `converged`、`iterations`、`optimizer`（如 `Optim.NelderMead`）、`objective_final`、`gradient_norm`（首期可为 `null`）、`start_used`、`failure_code`（未收敛时）、`nls_family`。首期 `tidy` 中标准误列可为 `null`，并在 `warnings` 中说明渐近 SE 未实现。

**CLI（App）：** `nls y x, family(exp_growth) start(β1 β2 β3)`；`family` 可省略（默认 `exp_growth`）。演示数据：`datasets/demo/nls_threshold_demo.csv`。

### `threshold`（单门限、双区制线性 OLS）

**`ModelSpec` 字段（除通用 `formula` / `dataset_ref` 外）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | 固定为 `threshold` |
| `threshold_variable` | 字符串 | 是 | 切换变量列名；**必须**同时出现在 `formula` 右侧，以便 listwise 与设计矩阵对齐。 |
| `threshold_grid` | 数数组 | 是 | 候选门限 \(\gamma\)，须按输入顺序 **严格递增**（不允许乱序或重复）；长度 **2–500**（Runtime 硬上限，防 DoS）。 |
| `threshold_trim_frac` | 数 | 否 | 在 \(q\) 上按分位修剪后再与网格求交；须满足 **\(0 \le \text{trim} < 0.45\)**；省略时 Julia 端默认 **0.1**。 |

**不转发字段：** 与 `nls` 相同，不传 `vcov` / `weights` / `cluster` / `instruments`。

**`result_payload.diagnostics`：** `gamma_hat`、`n_below`、`n_above`、`rss_piecewise`、`search_grid_meta`（对象：`n_candidates`、`trim_frac_applied`、`grid_input_length`）。

**CLI（App）：** 动词 **`threg`** 映射为 `model_type: "threshold"`；`threg y x1 q, qvar(q) grid(min max n)` 在解析器内将 `grid` 展开为等距单调数组（\(n\le 500\)）。教程见 [`tutorials/s5-nonlinear-threshold.md`](../../tutorials/s5-nonlinear-threshold.md)。

### `arch` / `garch`（ARCH(q) 与 GARCH(p,q)，常数均值，S5.6）

**路径：** 与 `arima` 相同，Runtime 将请求派发到 **`julia_time_series_bridge_entry.jl`**（`MetricaTimeSeries.jl` 独立 project），**不**走主 `julia_bridge_entry.jl` 截面 `MODEL_REGISTRY` 分支。

**共同必填：** `variable`、`time_column`；`formula` 可为占位字符串。

**`arch`：`ModelSpec` 字段**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | 固定为 `arch` |
| `arch_order` | 整数 | 是 | ARCH 阶 \(q\)，**1–12**；与 Runtime 校验一致。 |
| `garch_max_iter` / `garch_tol` | 整数 / 数 | 否 | 优化控制；Julia 默认与 `garch` 共用键名。 |

**`garch`：`ModelSpec` 字段**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | 固定为 `garch` |
| `garch_p` / `garch_q` | 整数 | 否 | 默认 **1 / 1**；须满足 **1≤p,q≤5** 且 **p+q≤8**。 |
| `garch_max_iter` / `garch_tol` | 整数 / 数 | 否 | 优化控制。 |

**互斥：** `arch` 请求**不得**携带 `garch_p` / `garch_q`；`garch` 请求**不得**携带 `arch_order`。

**`result_payload.diagnostics`（约定键）：** `converged`、`iterations`、`optimizer`、`loglik`、`persistence`、`unconditional_variance`、`conditional_volatility_preview`、`volatility_length`、`arch_order` 或 `garch_p`/`garch_q`、`failure_code`（未收敛或拟合失败时）。

**CLI（App）：** `arch y, time(date) arch(q)`；`garch y, time(date) [arch(p)] [garch(p q)]`（省略 `garch(...)` 时为 GARCH(1,1)；与总规兼容写法 `garch y, time(date) arch(1) garch(1)` 表示 \(p=1,q=1\)）。演示数据：`datasets/demo/garch_demo.csv`。教程见 [`tutorials/s5-arch-garch.md`](../../tutorials/s5-arch-garch.md)。

### `spatial_lag` / `spatial_error` / `spatial_slx`（截面 SAR / SEM / SLX，S5.7）

**路径：** 与截面 `MODEL_REGISTRY` 并行；Runtime 校验 `model_type` 白名单与 **`spatial_weights_path` 在磁盘上存在**（相对 `project_context.working_dir` 解析）；HTTP 与守护进程均在 `params` 中附带 **`working_dir`**（绝对路径），供 Julia 解析权重相对路径。

**`ModelSpec` 字段（除通用 `formula` / `dataset_ref` 外）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | `spatial_lag`、`spatial_error` 或 `spatial_slx` |
| `spatial_weights_path` | 字符串 | 是 | 边表 CSV 路径（列名固定 **`id_i`、`id_j`、`w`**）；相对工作目录或绝对路径 |
| `spatial_id_column` | 字符串 | 是 | 主数据中与边表 ID 对齐的列名（**每行唯一**） |
| `spatial_row_standardize` | 布尔 | 否 | 省略时 Julia 端默认 **`true`**（行标准化） |
| `vcov` | `{ type }` | 否 | 仅 **`spatial_lag`** 使用：`classical` 或 **`hc1`**（三明治，首期简化）；`spatial_error` / `spatial_slx` 忽略 |

**首期约束：** 权重在 Julia 侧展开为 **稠密** \(n\times n\) 矩阵；要求 **`n ≤ 5000`**、边表行数 **`≤ 200000`**（与 Core 实现一致）；超出时返回结构化错误。

**`result_payload.diagnostics`（约定 JSON 键）：** `n_obs`、`n_nonzero_links`、`symmetry_hint`、`id_join_unique`、`id_join_missing_count`、`spatial_weights_basename`、`row_standardized_report`（对象：`requested`、`applied`、`row_sums_min`、`row_sums_max`）、残差 **Moran**（`moran_i`、`moran_ei`、`moran_var`、`moran_z`、`moran_pvalue`）、SAR 的 **`rho`** 或 SEM 的 **`lambda`**；SAR / SLX 返回 `direct_effects` / `indirect_effects` / `total_effects` 与 `effects_method`，SEM 当前返回 `null` 并由 `model_capabilities.diagnostics_unavailable` 说明不可用项。

**`result_payload.model_capabilities`：** 空间模型返回 `status`、`model_family`、`supported_models`、`estimators`、`diagnostics_available`、`diagnostics_unavailable`、`effects_available`、`prediction_available`、`limitations`。Runtime 与 App 不根据模型名推断能力。

**CLI（App）：** 动词 **`spreg`**，例如  
`spreg y x1, spatial_weights("datasets/demo/spatial_demo_W.csv") id(region) model(lag)`；`model(slx)` 选择 SLX；`weights("...")` 为 **`spatial_weights` 的别名**。教程见 [`tutorials/s5-spatial.md`](../../tutorials/s5-spatial.md)。

### `duration_cox`（Cox 比例风险，右删失，S5.8）

**路径：** 与 `MODEL_REGISTRY` 并行；`julia_bridge_entry.jl` / `julia_daemon.jl` 专用分支调用 `MetricaDuration.fit_duration_cox`。

**`ModelSpec` 字段（除通用 `formula` / `dataset_ref` 外）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | 固定为 `duration_cox` |
| `formula` | 字符串 | 是 | 固定形态 **`ph ~ x1 + x2`**：`ph` 为占位左侧，**不要求**数据中存在该列；协变量仅出现在右侧 |
| `duration_time_column` | 字符串 | 是 | 随访时间列名；须为**正有限**实数（首期拒绝 0 与负值） |
| `duration_event_column` | 字符串 | 是 | 事件指示列名：**0=删失，1=事件**；亦支持布尔列 |

**不转发字段：** 桥接不传 `vcov` / `weights` / `cluster` 等线性族关键字。

**并列：** Breslow（`diagnostics.risk_set_ties_method` 为 `breslow`）。

**`result_payload`：** 与线性族相同的 `glance` / `tidy` / `warnings`；额外 **`hazard_ratios`** 数组（元素含 `term`、`hr`、`ci_lower`、`ci_upper`，基于 log 系数正态近似）；`tidy` 中 `estimate` 为 **log(HR)** 尺度。`diagnostics` 含 `n_obs`、`n_events`、`n_censored`、`censoring_fraction`、`converged`、`iterations`、`loglikelihood`、`baseline_hazard_summary`（含长度有界的 `preview`）、`ph_diagnostics`（首期 **`null`**）。

**CLI（App）：** `stcox time fail x1 x2` → `duration_time_column=time`、`duration_event_column=fail`、`formula="ph ~ x1 + x2"`。演示数据：`datasets/demo/duration_demo.csv`。教程见 [`tutorials/s5-duration.md`](../../tutorials/s5-duration.md)。

### `bayes_linear`（贝叶斯线性回归，S5.9 规划占位；当前不可调用）

**状态：** 当前仓库没有完整 `MetricaBayes.jl`、Runtime 白名单、App 类型与端到端测试，因此 `bayes_linear` 不得作为可调用模型出现在客户端。下列字段只作为后续正式建设的协议草案；实现落地前客户端不得依赖这些字段。

**`ModelSpec` 字段（除通用 `formula` / `dataset_ref` 外）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | 固定为 `bayes_linear` |
| `bayes_seed` | 整数 | 否 | 可复现种子；省略时 Julia 侧定义确定性默认或报错策略（须测试锁定） |
| `bayes_chains` | 整数 | 否 | 默认 **1** |
| `bayes_warmup` | 整数 | 否 | 默认 **0**；与 **`bayes_iter` 均为 0 或省略** 表示 **解析/共轭路径 A**（无 MCMC） |
| `bayes_iter` | 整数 | 否 | 默认 **0**；含义见上 |
| `bayes_prior_scale` | 数 | 否 | 独立高斯先验尺度控制；默认 **`1.0`**（与执行计划一致，若变更须双处同改） |
| `bayes_sigma2_known` | 布尔 | 否 | **`true`** 且提供 `bayes_sigma2_value` → σ² 已知解析分支 |
| `bayes_sigma2_value` | 数 | 条件 | σ² 已知时必填，须为有限 **正** 数 |
| `bayes_ig_alpha` | 数 | 条件 | σ² 未知 InvGamma 形状；与 `bayes_ig_beta` 成对；与「σ² 已知」分支 **互斥** |
| `bayes_ig_beta` | 数 | 条件 | σ² 未知 InvGamma 速率/尺度参数（文献记法差异在 Julia 文档字符串说明） |

**不转发字段（首期）：** 桥接不传 `vcov` / `weights` / `cluster` 等线性族推断关键字（与 Cox 专用分支类似）。

**`result_payload`：**

- **`glance` / `tidy` / `warnings`：** 与线性族相同信封。  
- **`tidy`：** 每系数含 **`posterior_mean`、`ci_lower`、`ci_upper`**（**credible interval**）；**`stderror`、`statistic`、`pvalue` 为 `null`**（首期禁止与频率学派列混读）。**不设** 顶层 `posterior_summary` 数组（避免与 `tidy` 双真来源，见执行计划 S5.9-J0）。  
- **`glance.metrics`：** 至少 `prior_family`（字符串）；**`log_marginal_likelihood`** 可解析则为数，否则 **`null`** 且 **`log_marginal_likelihood_not_available_reason`** 说明。  
- **`diagnostics`：** **`inference_mode`**（`"analytical"` 或 `"mcmc"`）；路径 A 下 **`r_hat`、`ess` 等为 `null`** 且 **`mcmc_not_applicable_reason`** 非空（教学诚实）；**`seed_used`、`chains`、`warmup`、`iter`** 与请求对齐或解析路径解释值。路径 B（可选二期）可含 `r_hat`、`ess`、`divergences` 等；**默认不启用 MCMC**（见执行计划：环境门控与硬上限）。

**CLI（App）：** **`bayesreg y x1 x2`** → `formula="y ~ x1 + x2"`（与 `reg` 习惯对齐）；可选括号选项映射到 `bayes_*` 键（以 App 解析器与 Vitest 为准）。教程见 [`tutorials/s5-bayes-linear.md`](../../tutorials/s5-bayes-linear.md)。

### 非参数 / 半参数（5c 预留，非实现）

以下能力**未**在 Julia 包中实现；若请求中出现独立 `model_type`（例如未来的 `kernel`、`partial_linear`）而 Runtime 未注册，应返回 **`RUNTIME_UNSUPPORTED_MODEL_TYPE`**（或等价的结构化错误码），**禁止**返回半套 JSON 或静默空结果。

**预留字段名（文档级）：** 未来若引入核回归 / 部分线性等，可在专节中冻结例如 `nonparam_kind`、`bandwidth`、`kernel_name` 等键名；在当前阶段，客户端与 Runtime **不得**假设这些字段已可用。

### `gmm_linear`（线性 IV-GMM）

**`ModelSpec` 字段（除通用 `formula` / `dataset_ref` 外）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | 固定为 `gmm_linear` |
| `instruments` | 字符串数组 | 是 | 工具变量列名，与 `iv` 相同 |
| `endog_columns` | 字符串数组 | 是 | 内生解释变量列名，须出现在公式右侧 |
| `gmm_weight` | 字符串，可选 | 否 | `one_step` 或 `two_step`（大小写不敏感）；省略时 Julia 端默认 `two_step` |

**不转发给 GMM 估计器的字段：** 桥接层对 `gmm_linear` 不传 `vcov` / `weights` / `cluster`（与 IPW 等因果模型处理方式一致），避免 `MethodError`。

**`result_payload.diagnostics`（GMM 专用键名，JSON 字符串键）：**

| 键 | 类型 | 说明 |
|----|------|------|
| `j_statistic` | 数 | Hansen / Sargan J |
| `j_df` | 整数 | 过识别自由度 \(L-k\) |
| `j_pvalue` | 数或 null | 恰识别时为 null |
| `n_moments` | 整数 | 矩条件个数 \(L\) |
| `n_params` | 整数 | 参数个数 \(k\) |
| `overidentifying_restrictions` | 整数 | 与 `j_df` 同义，便于展示 |
| `gmm_weight` | 字符串 | `one_step` / `two_step` |
| `weight_matrix_description` | 字符串 | 人类可读权重矩阵说明（含恰识别时退回 `(Z'Z)^{-1}` 的说明） |
| `iterations` | 整数 | 迭代次数 |
| `exactly_identified` | 布尔 | 为 true 时 J 检验不适用 |

**数值说明：** 过识别两步 GMM 中样本矩协方差 \(\hat\Omega\) 可能接近奇异；实现可对 \(\hat\Omega\) 施加极小对角收缩后再求逆。恰识别且请求 `two_step` 时，若 \(\hat\Omega\) 不可逆则退回与一步相同的权重 \((Z'Z)^{-1}\)，并在 `weight_matrix_description` 中说明。

### `dynamic_panel_gmm`（Arellano–Bond / Blundell–Bond 动态面板 GMM）

**`ModelSpec` 字段（除通用 `formula` / `dataset_ref` 外）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | 固定为 `dynamic_panel_gmm` |
| `panel_id` | 字符串 | 是 | 截面个体列名 |
| `panel_time` | 字符串 | 是 | 时间列名 |
| `instrument_lags` | 整数数组，长度 2 | 是 | `[min_lag, max_lag]`，水平因变量滞后层作为工具（如 `[2, 4]` 对应 `lags(2 4)`） |
| `gmm_weight` | 字符串，可选 | 否 | `one_step` / `two_step`，默认 `two_step` |
| `dpgmm_style` | 字符串，可选 | 否 | `difference`（Arellano-Bond） / `system`（Blundell-Bond）；默认 `difference` |
| `collapse_instruments` | 布尔，可选 | 否 | `true` 时将多级滞后合并为单列，缓解工具膨胀 |

**公式约定：** 左侧为水平因变量 \(y_{it}\)；右侧为**严格外生**解释变量（在差分方程中以 \(\Delta x\) 进入，并以自身为工具）。动态项 \(\Delta y_{i,t-1}\) 由实现自动加入，勿在公式中重复写滞后因变量列。

**不转发字段：** 与 `gmm_linear` 相同，桥接对 `dynamic_panel_gmm` 不传 `vcov` / `weights` / `cluster`。

**`result_payload.diagnostics`：** 含 S5.1 兼容键 `j_statistic`、`j_df`、`j_pvalue`、`n_moments`、`n_params`、`gmm_weight`、`weight_matrix_description`、`iterations`；并含 `ar1_test`、`ar2_test`（对象：`statistic`、`pvalue`、`description`）、`hansen_j`（对象）、`diff_hansen`（对象：`c_statistic`、`df`、`pvalue`；仅 System GMM）、`n_instruments`、`n_groups`、`n_periods`、`n_obs_diff`、`instrument_lags`、`dpgmm_style`、`collapse_instruments`。

### `sur` / `system_2sls` / `system_3sls`（S5.3 多方程系统）

**共同约定：** `formula` 可为空字符串；**方程列表**由 `equations: string[]` 承载（各方程为 StatsModels 单行公式，如 `y1 ~ x1 + x2`）。全系统在各方程涉及列**并集**上做 listwise 删行；删行信息在 `warnings` / `messages` 中结构化报告。

**Runtime 校验：** 方程数 **1–8**；`system_2sls` / `system_3sls` 要求 `system_endogenous`、`system_instruments` 外层长度与 `equations` 长度一致。

**`ModelSpec` 字段：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model_type` | 字符串 | 是 | `sur` / `system_2sls` / `system_3sls` |
| `equations` | 字符串数组 | 是 | 每方程一条公式 |
| `system_endogenous` | 字符串的数组的数组 | `system_*` 必填 | 按方程分组的内生解释变量列名 |
| `system_instruments` | 字符串的数组的数组 | `system_*` 必填 | 按方程分组的外生工具列名 |
| `sur_max_iter` | 整数，可选 | 否 | 仅 `sur`：FGLS 最大迭代次数 |
| `sur_tol` | 数，可选 | 否 | 仅 `sur`：系数变化收敛阈值 |

**不转发字段：** 桥接对 `sur` / `system_2sls` / `system_3sls` 不传 `vcov` / `weights` / `cluster`（与 `gmm_linear` 相同），避免 `MethodError`。

**`result_payload` 扩展：**

- `equation_glances`：数组，元素形状与顶层 `glance` 类似（`model`、`nobs`、`dof`、`metrics`、`warnings`），按方程索引。
- `tidy`：合并系数表；每行含 **`equation`**（方程公式字符串）及与单方程一致的系数字段（`name` / `estimate` / `stderror` / …）。
- `diagnostics`：**`system_method`**（如 `sur_fgls`、`2sls`、`3sls`）、**`sigma_residual`**（对象：`dim`、`matrix` 为方阵行主序）、**`equation_correlation`**（若实现则同结构）、**`iterations`**（若适用）。

**CLI（App）：** `sur (y1 x1 x2) (y2 x1 x2)`；`reg3 (y1 x1 x2), endogenous(x1) instruments(z1) method(3sls)`；多方程时 `endogenous` / `instruments` 内用 **`|`** 分隔方程段，与上述二维数组一一对应。教程见 [`tutorials/s5-sur-system.md`](../../tutorials/s5-sur-system.md)。

## Julia 进程模型

### 当前实现（持久化进程）

应用启动时拉起 Julia 进程，持久运行，通过 stdin/stdout JSON lines 通信：

```
┌──────────────────────────────────────────────┐
│              axum HTTP 服务                   │
│  POST /fit_model     → 转发到 Julia 会话     │
│  POST /inspect_dataset → 转发到 Julia 会话   │
│  POST /query_dataset → 转发到 Julia 会话     │
│  POST /transform     → 转发到 Julia 会话     │
│  POST /run_diagnostic → 转发到 Julia 会话   │
│  POST /save_project … /export_report（见上表） │
│  GET  /health        → 返回会话状态          │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────┴───────────────────────────┐
│           Julia 会话管理器                    │
│  ┌────────────────────────────────────────┐  │
│  │  Julia 进程 (持久化)                    │  │
│  │  stdin  ← JSON Request (逐行)          │  │
│  │  stdout → JSON Response (逐行)         │  │
│  │  stderr → 日志/警告                    │  │
│  └────────────────────────────────────────┘  │
│  - 启动时加载 MetricaBase、MetricaLinear、MetricaGMM、MetricaPanel、MetricaData、MetricaOutput、MetricaDiscrete、MetricaCausal、MetricaSurvey、MetricaTimeSeries、MetricaDiagnostics（以 `scripts/julia_daemon.jl` 为准） │
│  - 首次预热完成后通知前端就绪                  │
│  - [计划] 支持 cancel 信号                    │
│  - 进程崩溃自动重启（最多 3 次）              │
└──────────────────────────────────────────────┘
```

### stdin/stdout JSON Lines 协议

```json
// 请求（Runtime → Julia stdin，每行一个 JSON）
{"id": "req-001", "action": "fit_model", "params": {"dataset_path": "data/demo.csv", "formula": "y ~ x1 + x2", "model_type": "ols", "vcov": "classical"}}

{"id": "req-002", "action": "query_dataset", "params": {"dataset_path": "data/demo.csv", "kind": "summarize", "variables": ["y", "x1"], "limit": 200}}

// 响应（Julia stdout → Runtime，每行一个 JSON）
{"id": "req-001", "status": "success", "payload": {"glance": {...}, "tidy": [...], "warnings": [...]}}

// [计划] 进度通知（Julia stdout → Runtime）
// {"id": "req-001", "type": "progress", "message": "正在拟合模型...", "percent": 50}

// [计划] 取消信号（Runtime → Julia stdin）
// {"id": "req-001", "action": "cancel"}
```

### 关键设计点

1. **预热阶段**：应用启动时拉起 Julia 并加载所有包。前端显示"正在初始化 Julia 环境..."的加载状态。预热完成后才可交互。
2. **会话持久化**：数据集加载后留在 Julia 内存中。第二次拟合不同公式不需要重新读取 CSV。
3. **超时**：Julia 通信使用读线程 + channel 实现真实超时。超时后 kill 进程并返回错误。[计划] 取消信号和进度条尚未实现。
4. **崩溃恢复**：Julia 进程意外退出时，Runtime 自动重启并通知前端"Julia 环境已重置"。
5. **只读数据命令独立通道**：`describe`、`browse`、`summarize`、`tabulate` 统一走 `query_dataset`，不复用 `fit_model`，也不写模型运行记录。

## 请求示例

### 数据检查请求

`inspect_dataset` 可通过 `options.preview_rows` 请求返回指定数量的 `preview_rows`。桌面端“查看全部数据”会请求足够大的预览上限，用于在主面板展示完整小型数据集；Runtime 只透传该参数，实际取行由 Julia 数据检查函数完成。

```json
{
  "task_id": "uuid-inspect",
  "action": "inspect_dataset",
  "project_context": {
    "project_id": "proj_001",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "/path/to/data.csv",
    "format": "csv"
  },
  "model_spec": {
    "model_type": "ols",
    "formula": "y ~ x1"
  },
  "options": {
    "drop_missing": false,
    "return_augment": false,
    "preview_rows": 1000000
  }
}
```

### 数据查看请求

`query_dataset` 专门承载 Stata 风格只读数据命令。当前只支持四类核心命令：

- `describe`：返回数据集规模与变量元数据列表
- `summarize`：返回每变量 `Obs / Mean / Std. dev. / Min / Max`
- `tabulate`：返回单变量频数、百分比与累计百分比
- `browse`：只返回只读浏览配置，不伪造统计结果

```json
{
  "task_id": "uuid-query",
  "action": "query_dataset",
  "project_context": {
    "project_id": "proj_001",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "data/demo.csv",
    "format": "csv"
  },
  "command": {
    "kind": "summarize",
    "variables": ["y", "x1"],
    "limit": 200
  }
}
```

### OLS / WLS 请求

```json
{
  "task_id": "uuid",
  "action": "fit_model",
  "project_context": {
    "project_id": "proj_001",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "/path/to/data.csv",
    "format": "csv"
  },
  "model_spec": {
    "model_type": "ols",
    "formula": "y ~ x1 + x2 + x3",
    "weights": null,
    "vcov": {
      "type": "classical"
    }
  },
  "options": {
    "drop_missing": true,
    "return_augment": true
  }
}
```

### 面板模型请求

面板模型继续沿用 `fit_model` 信封，通过 `model_spec.model_type = "panel"` 与结构化面板索引字段进入 Julia 面板估计器。Runtime 只校验字段存在并转发请求，不在 Rust 侧实现面板计量逻辑。

```json
{
  "task_id": "uuid-panel",
  "action": "fit_model",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "/path/to/grunfeld.csv",
    "format": "csv"
  },
  "model_spec": {
    "model_type": "panel",
    "formula": "invest ~ mvalue + capital",
    "panel_id": "firm",
    "panel_time": "year",
    "panel_method": "fe"
  },
  "options": {
    "drop_missing": true,
    "return_augment": true
  }
}
```

### 数据变换请求

`/transform` 使用与 `fit_model` 一致的 Task 信封。Runtime 只负责解析项目工作目录、解析输入路径、生成派生 CSV 输出路径，并把结构化操作链转发给 Julia `MetricaData.jl`；具体数据语义不在 Rust 侧实现。

```json
{
  "task_id": "transform-001",
  "action": "transform",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "data/source.csv",
    "format": "csv"
  },
  "operations": [
    {
      "op": "filter",
      "args": {
        "condition": "year >= 2015"
      }
    },
    {
      "op": "generate",
      "args": {
        "name": "log_gdp",
        "expr": "log(gdp)"
      }
    }
  ],
  "options": {
    "preview_rows": 10,
    "persist_output": true
  }
}
```

当 `options.persist_output = true` 时，Runtime 将输出路径固定为：

```text
<working_dir>/.metrica/derived/<task_id>.csv
```

`.metrica/derived/` 是运行期派生数据目录，不进入版本控制。操作链具有事务语义：任一步失败时不写派生 CSV，响应中返回失败步骤序号和原因。

## 成功响应示例

```json
{
  "task_id": "uuid",
  "status": "success",
  "messages": [
    {
      "level": "info",
      "code": "INFO_ROWS_DROPPED",
      "text": "因缺失值已移除 12 行。"
    }
  ],
  "artifacts": [],
  "result_payload": {
    "glance": {},
    "tidy": [],
    "augment_preview": [],
    "diagnostics": [],
    "warnings": [],
    "summary_text": "model=ols, nobs=128, dof=124, r2=0.81"
  }
}
```

### 数据变换成功响应示例

```json
{
  "task_id": "transform-001",
  "status": "success",
  "messages": [],
  "artifacts": [],
  "result_payload": {
    "operation": "chain",
    "status": "ok",
    "result": {
      "nrows": 128,
      "ncols": 6,
      "notes": "执行 2 个数据操作。",
      "dataset_path": "/path/to/project/.metrica/derived/transform-001.csv"
    },
    "preview": {
      "columns": ["country", "year", "gdp", "log_gdp"],
      "rows": [
        {
          "country": "France",
          "year": 2015,
          "gdp": 2420.0,
          "log_gdp": 7.7915
        }
      ]
    },
    "warnings": [],
    "operations": [
      {
        "operation": "filter",
        "status": "ok",
        "result": {
          "nrows": 128,
          "ncols": 5,
          "notes": "保留满足条件 year >= 2015 的行。"
        },
        "warnings": []
      }
    ]
  }
}
```

### 数据查看成功响应示例

```json
{
  "task_id": "uuid-query",
  "status": "success",
  "messages": [],
  "artifacts": [],
  "result_payload": {
    "kind": "tabulate",
    "dataset_summary": {
      "row_count": 128,
      "column_count": 6
    },
    "variable": "region",
    "total": 128,
    "missing_count": 0,
    "truncated": false,
    "rows": [
      { "value": "east", "count": 40, "pct": 31.25, "cum_pct": 31.25 },
      { "value": "west", "count": 88, "pct": 68.75, "cum_pct": 100.0 }
    ]
  }
}
```

### 面板模型诊断响应片段

`model_type = "panel"` 的成功响应继续沿用同一个 `result_payload`，不新增 endpoint。面板诊断挂在 `result_payload.diagnostics` 下，当前包含 `hausman`、`fixed_effect_f`、`breusch_pagan_lm` 三个结构化诊断块。

```json
{
  "result_payload": {
    "glance": {
      "model_type": "panel",
      "method": "fe",
      "nobs": 200,
      "n_ids": 10,
      "n_times": 20
    },
    "tidy": [
      {
        "term": "mvalue",
        "estimate": 0.11,
        "std_error": 0.01,
        "statistic": 10.4,
        "p_value": 0.0
      }
    ],
    "augment_preview": [],
    "diagnostics": {
      "hausman": {
        "available": true,
        "statistic": 12.4,
        "pvalue": 0.002,
        "dof": 2,
        "method": "Hausman FE vs RE",
        "note": "教学版口径，比较 FE 与 RE 的共同斜率系数。"
      },
      "fixed_effect_f": {
        "available": true,
        "statistic": 18.6,
        "pvalue": 0.0,
        "dof": [9, 188],
        "method": "固定效应 F 检验",
        "note": "比较 pooled OLS 与个体固定效应模型。"
      },
      "breusch_pagan_lm": {
        "available": false,
        "statistic": null,
        "pvalue": null,
        "dof": null,
        "method": "Breusch-Pagan LM 随机效应检验",
        "note": "当前样本是不平衡面板，v1 不返回 LM 统计量。"
      }
    },
    "warnings": []
  }
}
```

不可用诊断必须显式返回 `available = false` 与 `note`，不得用 `0`、空字符串或展示层兜底文本伪造统计量。

## 数据检查成功响应示例

```json
{
  "task_id": "uuid",
  "status": "success",
  "messages": [],
  "result_payload": {
    "dataset_summary": {
      "row_count": 8,
      "column_count": 3
    },
    "columns": [
      {
        "name": "y",
        "inferred_type": "Int64",
        "missing_count": 0
      }
    ],
    "preview_rows": [
      {
        "y": 10,
        "x1": 1,
        "x2": 5
      }
    ],
    "warnings": []
  }
}
```

### 数据变换错误响应示例

```json
{
  "task_id": "transform-001",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "DATA_TRANSFORM_FAILED",
      "text": "数据操作链执行失败。",
      "hint": "请检查失败步骤的字段名、表达式或外部文件路径。"
    }
  ],
  "result_payload": {
    "operation": "chain",
    "status": "error",
    "warnings": [],
    "error": {
      "op_index": 2,
      "message": "列 gdp 不存在。"
    },
    "operations": [
      {
        "operation": "filter",
        "status": "ok",
        "result": {
          "nrows": 128,
          "ncols": 5,
          "notes": "保留满足条件 year >= 2015 的行。"
        },
        "warnings": []
      }
    ]
  }
}
```

## 错误响应示例

```json
{
  "task_id": "uuid",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "NUM_SINGULAR_MATRIX",
      "text": "设计矩阵奇异，无法估计模型。",
      "hint": "请检查是否存在某一预测变量是其他变量的线性组合。"
    }
  ]
}
```

## S3 项目系统端点

### POST /save_project

保存项目清单到 `<working_dir>/.metrica/project.json`。

**请求示例：**

```json
{
  "task_id": "save-project-001",
  "action": "save_project",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "manifest": {
    "project_id": "alpha-demo",
    "version": 1,
    "created_at": "2026-05-03T12:00:00Z",
    "updated_at": "2026-05-03T12:00:00Z",
    "source_dataset": "/path/to/source.csv",
    "active_dataset": "/path/to/active.csv",
    "saved_model_specs": [
      { "model_type": "ols", "formula": "y ~ x1 + x2" }
    ],
    "last_run_id": "run-001",
    "ui_state": { "active_tab": "glance" },
    "data_lineage": {
      "source_dataset": "/path/to/source.csv",
      "active_dataset": "/path/to/active.csv",
      "operations": [],
      "row_count_before": 100,
      "row_count_after": 100,
      "notes": []
    }
  }
}
```

**成功响应：**

```json
{
  "task_id": "save-project-001",
  "status": "success",
  "messages": [],
  "artifacts": ["/path/to/project/.metrica/project.json"],
  "result_payload": {
    "project_path": "/path/to/project/.metrica/project.json",
    "manifest": { ... }
  }
}
```

### POST /load_project

从 `<working_dir>/.metrica/project.json` 加载项目清单。

**请求示例：**

```json
{
  "task_id": "load-project-001",
  "action": "load_project",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  }
}
```

**成功响应：**

```json
{
  "task_id": "load-project-001",
  "status": "success",
  "messages": [],
  "artifacts": ["/path/to/project/.metrica/project.json"],
  "result_payload": {
    "project_path": "/path/to/project/.metrica/project.json",
    "manifest": { ... }
  }
}
```

**错误响应（项目不存在）：**

```json
{
  "task_id": "load-project-001",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "RUNTIME_PROJECT_NOT_FOUND",
      "text": "读取文件失败（/path/to/project/.metrica/project.json）",
      "hint": "请先保存项目。"
    }
  ]
}
```

### POST /list_runs

列出 `<working_dir>/.metrica/runs/` 下的所有运行记录，按 `finished_at` 降序排列。

**请求示例：**

```json
{
  "task_id": "list-runs-001",
  "action": "list_runs",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  }
}
```

**成功响应：**

```json
{
  "task_id": "list-runs-001",
  "status": "success",
  "messages": [],
  "result_payload": {
    "runs": [
      {
        "run_id": "run-001",
        "action": "fit_model",
        "started_at": "1714742400000",
        "finished_at": "1714742401000",
        "status": "success",
        "dataset_ref": { "source": "file", "path": "/path/to/data.csv", "format": "csv" },
        "model_spec": { "model_type": "ols", "formula": "y ~ x1" },
        "operations": null,
        "warnings": [],
        "messages": [],
        "artifacts": [],
        "result_summary": { "glance": { ... }, "tidy": [ ... ] },
        "request_payload": { ... }
      }
    ]
  }
}
```

### POST /rerun_task

根据历史运行记录重新执行任务。生成新的 `run_id`，若数据路径不存在则返回结构化错误。

**请求示例：**

```json
{
  "task_id": "rerun-001",
  "action": "rerun_task",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "run_id": "run-001"
}
```

**成功响应：** 与原始动作（`fit_model` / `transform` / `inspect_dataset`）的响应格式相同，但 `run_id` 更新。

**错误响应（数据路径失效）：**

```json
{
  "task_id": "rerun-001",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "RUNTIME_RERUN_DATASET_MISSING",
      "text": "重跑所需数据集不存在：/path/to/missing.csv",
      "hint": "请恢复数据文件后再重跑。"
    }
  ]
}
```

### POST /export_report

导出运行报告，支持 Markdown 和 CSV 格式。

**请求示例：**

```json
{
  "task_id": "export-001",
  "action": "export_report",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "run_id": "run-001",
  "format": "markdown"
}
```

**支持的格式：**
- `markdown` — 完整 Markdown 运行报告
- `csv_tidy` — 系数表 CSV
- `csv_glance` — 摘要指标 CSV
- `csv_diagnostics` — 诊断结果 CSV

**成功响应：**

```json
{
  "task_id": "export-001",
  "status": "success",
  "messages": [],
  "result_payload": {
    "content": "# Metrica 单次运行报告\n...",
    "format": "markdown",
    "run_id": "run-001"
  }
}
```

**错误响应（运行记录无结果）：**

```json
{
  "task_id": "export-001",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "RUNTIME_NO_RESULT_SUMMARY",
      "text": "该运行记录没有结果摘要，无法导出报告。",
      "hint": "请确保运行成功后再导出。"
    }
  ]
}
```

## 统一能力协议与增广状态（`model_capabilities` / `augment_status`）

### `model_capabilities`

所有 S5 模型（`spatial_*`、`duration_cox`、`arch`/`garch`、`gmm_linear`、`dynamic_panel_gmm`、`quantile`、`nls`、`threshold`、`sur`/`system_*`）的 `result_payload` 中必须包含 `model_capabilities` 字段。该字段由 `MetricaBase.ModelCapabilities` 结构体序列化而来，App 通过 `ModelCapabilitiesPanel` 消费展示。

未接入统一能力协议的旧模型（`ols`、`panel`、`logit` 等）返回 `null`，App 应静默跳过。

```json
{
  "model_capabilities": {
    "status": "partial",
    "model_family": "duration",
    "supported_models": ["duration_cox"],
    "estimators": ["Breslow partial likelihood + Optim (Nelder-Mead)"],
    "diagnostics_available": ["n_events", "n_censored", "censoring_fraction", "loglik", "baseline_hazard", "hazard_ratios"],
    "diagnostics_unavailable": ["schoenfeld_residuals", "ph_global_test", "strata", "time_varying_covariates", "aft_parametric"],
    "effects_available": ["hazard_ratios"],
    "prediction_available": false,
    "limitations": ["Schoenfeld 残差与 PH 假设检验为二期功能。", "不支持分层、时依协变量与 AFT 参数模型。"]
  }
}
```

**字段约定：**
- `status`：`implemented`（完整可用）、`partial`（部分实现）、`planned`（仅规划）
- `model_family`：模型族标识（`spatial`、`duration`、`volatility`、`gmm`、`dynamic_panel`、`quantile`、`nonlinear`、`threshold`、`system`）
- `diagnostics_available` / `diagnostics_unavailable`：明确告知 App 哪些诊断可展示、哪些不可用
- `limitations`：教学向说明，告知用户当前版本的能力边界

### `augment_status`

所有模型响应的 `result_payload` 中应包含 `augment_status`，描述增广数据（逐观测拟合值、残差等）的可用性。

```json
{
  "augment_status": {
    "available": true,
    "columns_available": ["fitted", "residual", "std_residual", "leverage", "cooks_d"],
    "columns_unavailable": [],
    "preview_included": true,
    "preview_rows": 100
  }
}
```

## 当前稳定基线

当前可执行端到端链路为：

- 本地 CSV 输入 → `fit_model` 动作 → `ols`、`panel`、`iv` 或 `gls` 模型类型
- 本地 CSV 输入 → `transform` 动作 → 派生 CSV → `fit_model` 动作
- 结构化的 `glance` 与 `tidy` 响应载荷
- 面板模型的结构化 `diagnostics` 响应载荷
- 数据操作链的结构化 `preview`、`operations` 与错误定位
- 删行与拟合错误的警告/消息传播

### 项目与导出端点（Runtime 已实现；桌面闭环为部分持续演进）

下列端点在 Rust 层实现并通过 `runtime/metrica-runtime/tests/vertical_slice.rs` 等集成测例覆盖；Julia 会话不参与项目 JSON 的读写本身。

- `POST /save_project`、`/load_project`、`/list_runs`、`/rerun_task`、`/export_report`

**桌面 App：** CLI 解析与 `executeCommand` 已包含 `export`、`rerun` 等动词路径（以 `apps/metrica-desktop/src-react` 当前实现为准）。**仍可能部分缺失或非目标的能力**包括：出版级图表 SVG/PNG 导出、多模型对比产品化、崩溃后完整工作区 UI 状态自动恢复等——以路线图与主设计「非目标」为准，不得将本节误读为「全已实现」。

**持久化 vs oneshot：** 见上文「`--oneshot` 回退模式」路由差异；依赖 `transform` / `rerun_task` / `export_report` 的流程在回退模式下不可用。

**其他已知限制（持久化模式仍适用）：**

- 加载项目不会自动把 CSV 灌回 Julia 内存；重跑依赖数据文件仍在可访问路径
- **[计划]** 经 stdin 的 cancel、进度事件尚未实现（见下文 JSON 示例注释）

主设计与阶段边界见：

- `Metrica.jl-计量经济学框架-完善版.md`
- `docs/roadmap/s1-foundation-and-workbench.md`
- `docs/roadmap/s2-core-empirical-workbench.md`
- `docs/superpowers/specs/2026-04-30-metrica-main-design.md`

当前实现路线补充约束：

- `fit_model` 必须通过 Runtime 调用 Julia 子进程真实执行
- 成功响应中的 `glance` 与 `tidy` 来自真实 Julia 拟合结果
- `fit_ols_demo` 或纯示例载荷不得作为当前完成标准

> 注意：成功响应中的 `augment_preview` 字段在 `options.return_augment = true` 时返回逐观测增强数据。OLS/WLS 包含拟合值、残差、标准化残差、杠杆值与 Cook's D；面板模型至少包含拟合值、残差与标准化残差。默认预览前 100 行。当 `return_augment = false` 时，该字段不包含在响应中。

当前默认基线为：

- `fit_model` 的默认模型类型是 `ols`
- 当前稳定协方差标签是 `classical`
- `model_spec.weights` 表示 WLS 权重变量名，值必须是数据集列名；缺省或 `null` 时保持 OLS
- `model_spec.panel_id`、`model_spec.panel_time`、`model_spec.panel_method` 仅在 `model_type = "panel"` 时使用；`panel_method` 当前支持 `fe`、`re`、`fd`、`between`，缺省由 Julia 桥接层按 `fe` 处理
- 面板 `diagnostics` 当前包含 `hausman`、`fixed_effect_f`、`breusch_pagan_lm`；诊断不可用时返回结构化不可用说明，而不是展示层推断
- 新增 `WLS`、`HC1`、`cluster` 等能力时，必须保持现有成功/失败响应信封不变

## 后续高级能力的协议预留

后续高级功能只预留两层扩展方向：

### 第一层：受控自定义公式与选项

这层继续沿用当前 `fit_model` 信封：

- `model_spec.formula`
- `model_spec.vcov`
- `options.*`

扩展原则：

- 新能力优先通过新增结构化字段表达
- 不以自由命令字符串替代 `model_spec` / `options`
- Runtime 只搬运并校验 schema，不解释计量语义
- Runtime 不传递 Julia 内部矩阵、分布对象或任意函数闭包；自定义计算能力必须先落为白名单动作、模板或结构化参数

### 第二层：受控自定义动作 / 自定义分析模板

这层允许未来在 `action` 上做受控扩展，例如：

- 新的白名单动作
- 以模板标识符驱动的分析流程

扩展约束：

- 新动作必须有明确 schema
- 模板必须映射到 Runtime 已注册的执行路径
- 响应仍返回结构化 `status`、`messages`、`result_payload`

### 当前明确不开放

当前协议不应扩展为：

- 任意 Julia 代码执行入口
- 任意 shell 命令执行入口
- 仅靠一段自由文本命令决定执行逻辑的产品接口
