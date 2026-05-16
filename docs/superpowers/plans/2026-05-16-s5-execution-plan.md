# S5 执行计划（活跃）

> **状态：当前唯一活跃 `superpowers` 实施计划。** 分期目标、非目标与验收细节以仓库根目录 [`S5-高级研究专题总施工规划.md`](../../../S5-高级研究专题总施工规划.md) 为权威来源；本文件仅维护**执行顺序、文档锚点与跨层检查清单**，不重复总规全文。

## 文档锚点

| 用途 | 路径 |
|------|------|
| 总规 | [`S5-高级研究专题总施工规划.md`](../../../S5-高级研究专题总施工规划.md) |
| 路线图分期 | [`docs/roadmap/s5-advanced-research-topics.md`](../../roadmap/s5-advanced-research-topics.md) |
| 主设计 | [`docs/superpowers/specs/2026-04-30-metrica-main-design.md`](../specs/2026-04-30-metrica-main-design.md) |
| Runtime 协议 | [`docs/architecture/runtime-protocol.md`](../../architecture/runtime-protocol.md) |
| App 壳层 | [`docs/architecture/app-shell.md`](../../architecture/app-shell.md) |

## S5.0 文档治理与阶段基线（本计划前置）

- [x] 路线图 `s5-advanced-research-topics.md` 与总规对齐；历史对照矩阵改为非活跃快照说明。
- [x] 主设计更新为 `S1`–`S4` + CLI-first + `S5` 边界；`superpowers` 下已完成 spec/plan 结论并回主设计后删除原文件。
- [x] `app-shell.md` / `runtime-protocol.md` 与 **Runtime + 桌面宿主（`tao`/`wry` + `src-react`）** 源码对齐；补充 `model_type` 表与 `S5` 扩展规则。
- [x] 根目录 `ui-project-button-system-plan.md` 并回壳层「愿景」叙述后删除。
- [x] `README.md`、`apps/metrica-desktop/README.md`、`runtime/metrica-runtime/README.md`、`CLAUDE.md` 同步阶段说明。

## 后续分期（执行顺序）

按总规优先级：`S5.1` GMM → `S5.2` 动态面板 GMM → `S5.3` SUR / 系统方程 → `S5.4` 分位数 → `S5.5`–`S5.9` 见总规。

每分期开工前更新总规对应小节，并在本文件增加 **Task 清单**（文件路径、关键函数、测试断言各一行级），遵守 `AGENTS.md` 对 plan 篇幅约束。

## S5.1 线性 IV-GMM 与过识别检验（已完成）

- [x] `packages/MetricaGMM.jl`：一步/两步权重、Hansen J、`glance`/`tidy`/`serialize`、确定性测试。
- [x] `scripts/julia_bridge_entry.jl` / `julia_daemon.jl`：`gmm_linear` 分支与 `MetricaGMM.result_to_payload`。
- [x] Runtime：`ModelSpec.gmm_weight`、`validate_model_request`、`vertical_slice` 测例；`julia_bridge_entry` 仓库根解析修复（`-e` 下可靠 `include` MetricaDaemon）。
- [x] App：`gmm` CLI、`gmm_weight` 透传、`GmmDiagnosticsPanel`、协议类型与 Vitest。
- [x] 文档：`runtime-protocol` 本节、`tutorials/s5-gmm.md`。

**已验证（本阶段）：** `Pkg.test(MetricaGMM)`（Julia）；`cargo test --test vertical_slice fit_model_runs_gmm_linear`（Runtime + 桥接）；`apps/metrica-desktop` 下 `npm test`（Vitest）。

## S5.2 动态面板 GMM（实施规划）

> **权威条目：** 总规 [`S5-高级研究专题总施工规划.md`](../../../S5-高级研究专题总施工规划.md) §5；本节只写**边界、协议草案、文件级 Task、验收与风险**，实现细节从现有 `PanelData` / `fit_panel_iv` / `MetricaGMM` 代码中读取模式。

### 0. 收口状态（2026-05-16）

首期 **Difference GMM** 已贯通：Julia `fit_dynamic_panel_gmm` + `MetricaGMM.linear_iv_gmm_stack`、桥接/守护进程、`dynamic_panel_gmm` 白名单与校验、App `xtabond` CLI、Vitest、`runtime-protocol` 专节与本教程。二期 **System GMM** 仍为非目标。

### 1. 范围与非目标

- **纳入（首期）：** **Difference GMM**（Arellano–Bond 主路径）；平衡或轻度不平衡短面板；因变量含 **一期滞后** 的动态设定；显式 **工具滞后层**（对应总规示例 `lags(2 4)` 的受控语义）；结构化输出 **AR(1)、AR(2)、Hansen / Sargan J、工具数、个体数、时期数、差分/水平样本说明**；短面板、工具过多、时间不足、差分损失样本等 **结构化 warning/error**。
- **二期（总规已写）：** **System GMM**（Blundell–Bond）；仅当 Difference 路径测试与 Runtime 垂直切片稳定后再开独立 Task，避免同一分支内「半套 system」。
- **明确不做：** 不把动态 GMM 藏进 `model_type: "panel"` 或 `panel_iv` 的 kwargs；不开放用户自定义 moment / 任意 Julia；不在 `MetricaBase.jl` 内堆估计量（仅必要时扩 **共享错误码/抽象**）。

### 2. 架构与包依赖

- **实现归属：** `packages/MetricaPanel.jl`（与 `PanelData`、现有 `fit_panel_iv` 同层），新增 **`MetricaGMM` 依赖**（`Project.toml` + `MetricaRuntime.jl` 聚合 manifest），用于复用 **一步/两步权重与奇异 Ω 的数值策略**（抽小函数或调用包内已有辅助，避免 `MetricaPanel` ↔ `MetricaGMM` 循环依赖）。
- **独立 `model_type`：** `dynamic_panel_gmm`（与 `panel` / `panel_iv` 并列白名单），满足总规「不把动态面板作为普通 panel 隐藏选项」。
- **桥接分支：** `scripts/julia_bridge_entry.jl` / `julia_daemon.jl` 中与 `panel` / `panel_iv` 同级增加 `elseif model_type == "dynamic_panel_gmm"`（读 `panel_id` / `panel_time` / 新字段），**禁止**走 `MODEL_REGISTRY` 与 `gmm_linear` 混路径。

### 3. 协议草案（待写入 `runtime-protocol.md` 时再定稿键名）

| 方向 | 要点 |
|------|------|
| **`ModelSpec` 新增** | `dpgmm_style`: `"difference"` \| `"system"`（首期仅校验 `"difference"`，非法或缺省走默认 difference）；`instrument_lags`: `[min_lag, max_lag]` 整数对（与总规 CLI `lags(2 4)` 对齐）；可选 `collapse_instruments`（布尔，默认 `false`，语义与实现以 Julia 注释为准）。 |
| **与现有面板字段复用** | `panel_id`、`panel_time`、`formula`（须能解析出因变量及其滞后结构，或与显式选项一致）；不复用 `iv` 的 `instruments`/`endog_columns` 命名，避免与静态 IV 混淆——动态矩由 **滞后规则** 生成，除非总规修订为「额外外生 IV 列」再扩展。 |
| **`result_payload.diagnostics`** | 至少：`ar1_test`、`ar2_test`、`hansen_j`（或沿用 S5.1 的 `j_statistic`/`j_df`/`j_pvalue` 命名之一并全仓统一）、`n_instruments`、`n_groups`、`n_periods`、`n_obs_diff`、`gmm_step`/`weight_description`；键名在动码前写入 `runtime-protocol.md` 一节「动态面板 GMM」。 |
| **Rust / TS** | `lib.rs` 的 `model_required_fields` 与 `validate_model_request`；`server.rs` 透传；`apps/.../protocol.ts` 与 `commandParser` / `commandGrammar`（动词 **`xtabond`** 与总规一致）。 |

### 4. Task 清单（开工顺序）

| ID | 路径 / 位置 | 目标（一句话） |
|----|----------------|------------------|
| S5.2-J1 | `packages/MetricaPanel.jl`（`src/dynamic_panel_gmm.jl`）、`Project.toml` | [x] 在 `PanelData` 上构造差分方程样本与工具矩阵；Difference GMM 估计；`fit`/`glance`/`tidy` 契约与结构化 `warnings`。 |
| S5.2-J2 | 同上 + `src/serialize.jl` | [x] `result_to_payload`：`glance`/`tidy`/`diagnostics`/`warnings` 形状与 `panel_iv` 路径一致。 |
| S5.2-J3 | `packages/MetricaPanel.jl/test/runtests.jl` + `datasets/demo/dynamic_panel_gmm_demo.csv` | [x] 确定性：工具列数、差分样本行数、AR/J 键存在性（未对数值做 R 对齐黄金值）。 |
| S5.2-B1 | `scripts/julia_bridge_entry.jl`、`julia_daemon.jl` | [x] `dynamic_panel_gmm` 与面板同级分支；`MODEL_REGISTRY` 注册 + kwargs。 |
| S5.2-B2 | `packages/MetricaRuntime.jl/Manifest.toml` | [x] 聚合环境 `MetricaPanel`→`MetricaGMM` 依赖已解析。 |
| S5.2-R1 | `runtime/metrica-runtime/src/lib.rs`、`server.rs` | [x] `ModelSpec` 新字段与校验。 |
| S5.2-R2 | `runtime/metrica-runtime/tests/vertical_slice.rs` | [x] `dynamic_panel_gmm` 断言 `diagnostics` 含 AR/J。 |
| S5.2-A1 | `commandGrammar.ts`、`commandParser.ts`、`protocol.ts`、`ResultBlock.tsx`、`GmmDiagnosticsPanel.tsx` | [x] 动词 **`xtabond`** 与诊断展示。 |
| S5.2-A2 | `__tests__/commandParser.test.ts`、`runtimeClient.test.ts`、`ResultBlock.test.tsx` | [x] 解析与请求构建覆盖。 |
| S5.2-D1 | `docs/architecture/runtime-protocol.md`、`tutorials/s5-dynamic-panel-gmm.md` | [x] 协议专节与教程。 |
| S5.2-D2 | 本节与总规 §5 | [x] 收口勾选（以本节 §0 为准）。 |

### 5. 验收（对照总规 §5）

- Julia：`Pkg.test(MetricaPanel)` 中含动态面板 GMM 用例通过。
- Runtime：`vertical_slice` 中 `dynamic_panel_gmm` 成功且 JSON 形状符合协议表。
- App：CLI `xtabond ...` 后消息流出现结构化诊断块（非纯文本摘要）。
- 文档：教程命令在「Runtime + 守护进程已启动」前提下可本地复现。

### 6. 风险与依赖

- **数值：** 两步 GMM 在短面板下 Ω 奇异风险高——与 S5.1 对齐 **对角收缩 / 恰识别退避** 策略，并在 `weight_matrix_description` 中可读说明。
- **公式与滞后：** `StatsModels` 与面板差分叠代须约定**单一事实来源**（仅公式解析或仅显式 `lag` 选项），避免双重不一致；在 spec 定稿段写死一条决策。
- **教学：** AR(1)/AR(2) 为模型设定检验，须在 `warnings`/`diagnostics` 中区分 **info vs warning**，避免误标为「拟合失败」。

---

**System GMM（二期）预备：** 仅在 `dpgmm_style == "system"` 时增加水平方程与附加矩；依赖首期 Difference 的矩阵装配与序列化骨架，单独 PR 或子里程碑，不在首期混编。

## S5.3 SUR 与联立方程（实施规划）

> **权威条目：** 总规 [`S5-高级研究专题总施工规划.md`](../../../S5-高级研究专题总施工规划.md) §6；本节只写**边界、协议草案、文件级 Task、验收与风险**。

### 0. 收口状态（2026-05-16）

首期 **`sur` + `system_2sls` + `system_3sls`** 已按总规顺序在 `MetricaSystem.jl` 贯通；桥接/守护进程/registry、`runtime-protocol` 专节、App `sur` / `reg3` CLI 与结构化展示、教程 `tutorials/s5-sur-system.md` 与本节对齐。

### 1. 范围与非目标

- **纳入（3a `sur`）：** 同一样本、方程间相关误差的 **SUR / FGLS**（迭代至 `sur_max_iter` 或 `|Δβ|∞ < sur_tol` 收敛，二者先到为准；实现与 `diagnostics.iterations` 写明）；**listwise 删行**（各方程涉及列并集上 `completecases`），`warnings` 报告删行数（对齐 `MetricaLinear` 删样警告模式）；方程级 `glance`、合并 `tidy`（强制 `equation` 列）、**Σ̂** 与残差相关矩阵。
- **纳入（3b `system_2sls`）：** **按方程独立 2SLS**（与单方程 `iv` 同一数值路径），共享 listwise 样本；结构化欠识别/秩不足沿用 `ModelError`；**非**堆叠单 giant IV 矩阵的「全系统一步法」。
- **纳入（3c `system_3sls`）：** 在 2SLS 结构残差上估计 **Σ̂**，对**各方程第二阶段设计矩阵**做一次 **GLS（单步 3SLS）**；**不**捏造未文档化的系统级 Hansen 行；与 `MetricaGMM` 无循环依赖（本期不依赖 `MetricaGMM`）。
- **明确不做：** FIML、任意用户 Julia、在 `MetricaBase.jl` 内堆估计量；Runtime 对方程数 **≤8**（DoS 防护）。

### 2. 架构与包依赖

- **实现归属：** `packages/MetricaSystem.jl`；依赖 `MetricaBase`、`MetricaLinear`（公式解析、`prepare_model_data`）、`MetricaOutput`（`summary_card` 可选）、`CSV`、`DataFrames`、`LinearAlgebra`、`Distributions`、`StatsModels`。
- **注册：** `MetricaBase.MODEL_REGISTRY` 增加 `"sur"` / `"system_2sls"` / `"system_3sls"` → 对应 `AbstractEconModel` 子类型（规格体为占位 struct，算法在 `fit`）。
- **桥接：** `julia_bridge_entry.jl` / `julia_daemon.jl` 在 registry 分支为上述类型注入 `equations` 与 `system_endogenous` / `system_instruments`（JSON 数组的数组），并与 `gmm_linear` 一样**排除** `vcov`/`weights`/`cluster` 误传。

### 3. 协议草案（与 `runtime-protocol.md` 专节一致）

| 方向 | 要点 |
|------|------|
| **`ModelSpec` 共用** | `equations: string[]`，每项为单方程公式，如 `"y1 ~ x1 + x2"`；`formula` 可填首条方程或空串，Runtime 以 `equations` 为准。 |
| **`sur` 可选** | `sur_max_iter`（默认 5）、`sur_tol`（默认 `1e-6`）。 |
| **`system_2sls` / `system_3sls`** | `system_endogenous: string[][]`、`system_instruments: string[][]` 与 `equations` **等长**；列须存在于数据（与 `iv` 语义一致）。 |
| **`result_payload`** | `equation_glances`：与现有 `glance` 键对齐的对象数组；`tidy`：合并行且每行含 **`equation`**；`diagnostics`：`system_method`（`sur_fgls` / `2sls` / `3sls`）、`sigma_residual`（`dim` + 展平数值）、`equation_correlation`、`iterations`（若适用）。 |

### 4. App / CLI（定稿）

- **`sur (y1 x1 x2) (y2 z1 z2)`** → `model_type: "sur"`，`equations` 由括号块生成。
- **`reg3 (...)`** → 默认 `system_2sls`；**`method(3sls)`** → `system_3sls`；**`endogenous(x1|x2)`**、**`instruments(z1 z2|z1 z2)`** 用 **`|`** 分隔方程段（与协议二维数组一一对应）。

### 5. Task 清单

| ID | 路径 / 位置 | 目标 |
|----|----------------|------|
| S5.3-J1 | `packages/MetricaSystem.jl` | [x] SUR：FGLS、Σ̂、`equation_glances`、合并 `tidy`、`result_to_payload`。 |
| S5.3-J2 | 同上 | [x] `system_2sls`：按方程 IV + listwise。 |
| S5.3-J3 | 同上 | [x] `system_3sls`：2SLS 残差 Σ + 单步 GLS。 |
| S5.3-J4 | `packages/MetricaSystem.jl/test` + `datasets/demo/sur_system_demo.csv` | [x] 确定性：维度、Σ 对称、失败路径。 |
| S5.3-B1 | `julia_bridge_entry.jl`、`julia_daemon.jl`、`MetricaRuntime.jl` | [x] registry kwargs + `result_to_payload` 分派。 |
| S5.3-R1 | `runtime/metrica-runtime/src/lib.rs`、`server.rs` | [x] `ModelSpec` 字段与校验（方程数 ≤8）。 |
| S5.3-R2 | `vertical_slice.rs` | [x] `sur` 断言 `equation_glances` 与 `diagnostics.sigma_residual`。 |
| S5.3-A1 | `commandGrammar`/`commandParser`/`protocol`/`ResultBlock`/`SystemEquationsPanel` | [x] CLI 与结构化展示。 |
| S5.3-A2 | Vitest | [x] 括号方程与 `reg3` 选项。 |
| S5.3-D1 | `runtime-protocol.md`、`tutorials/s5-sur-system.md` | [x] 协议 + 教程。 |
| S5.3-D2 | 本节与总规 §6 | [x] 措辞对齐。 |

### 6. 验收

- Julia：`Pkg.test(MetricaSystem)`。
- Runtime：`cargo test --test vertical_slice` 中含 `sur` 用例。
- App：`npm test`（Vitest）覆盖解析；消息流含 `equation_glances` / 诊断块。

### 7. 风险

- **识别：** 系统 IV 秩亏 → 结构化 `ModelError` 与方程索引（沿用 IV 路径）。
- **协议体积：** `equations` + 二维工具配置 → Runtime **方程数上限 8**。

---

## S5.4 分位数回归（实施规划）

> **权威条目：** 总规 [`S5-高级研究专题总施工规划.md`](../../../S5-高级研究专题总施工规划.md) §7；本节只写**边界、协议定稿、文件级 Task、验收与风险**。

### 0. 收口状态

首期 **`quantile`**（单 $\tau$）在 `MetricaQuantile.jl` 贯通后，与本节 Task 表、桥接/Runtime/App、`runtime-protocol` 专节、教程 [`tutorials/s5-quantile-regression.md`](../../tutorials/s5-quantile-regression.md) 对齐并在此勾选。

### 1. 范围与非目标

- **纳入（4a）：** 线性分位数回归 **单一** `quantile_tau` $\in (0,1)$；`formula` + `dataset_ref`；**listwise** 与 `MetricaLinear` 删行警告一致；系数估计委托 **`QuantileRegressions.jl`（v0.1.x，专节定稿）** 内点求解器 `IP()`；**标准误 / 协方差** 使用该包内 **Hall–Sheather 核** 渐近三明治（`diagnostics.inference_kind = asymptotic_kernel`）；**伪 $R^2$** 采用 check 损失比 McFadden 型（实现见包内注释）；`glance.metrics` 含 **`tau`**（与总规 CLI `quantile(0.5)` 一致）；`diagnostics` 含 `rank_X`、`cond_X`（条件数近似）、`pseudo_r2_definition` 字符串。
- **明确不做（首期）：** 多 $\tau$ 数组、`bootstrap_B` / `bootstrap_seed`；`vcov` / `cluster` / `instruments` 与 OLS/IV 混传（桥接层对 `quantile` **排除**上述 kwargs）；在 `MetricaBase.jl` 内堆算法。

### 2. 架构与包依赖

- **实现归属：** `packages/MetricaQuantile.jl`；依赖 `MetricaBase`、`MetricaLinear`、`MetricaOutput`、`CSV`、`DataFrames`、`Distributions`、`LinearAlgebra`、`Statistics`、`StatsModels`、**`QuantileRegressions`**（仅本包引入，版本写死于 `Project.toml` `[compat]`）。
- **注册：** `MetricaBase.MODEL_REGISTRY["quantile"]` → `QuantileModel`（占位 struct，`fit` 内完成估计）。

### 3. 协议定稿（与 `runtime-protocol.md` 专节一致）

| 方向 | 要点 |
|------|------|
| **`ModelSpec`** | `model_type: "quantile"`；`formula`；**`quantile_tau`**（必填，浮点，Runtime 校验 `1e-8 < tau < 1-1e-8`）。 |
| **桥接** | 与 `gmm_linear` 相同：**不**转发 `vcov` / `weights` / `cluster` / `instruments` 等线性族 kwargs。 |
| **`result_payload`** | 与 OLS 相同顶层 `glance` / `tidy` / `vcov_label`；`diagnostics`：`tau`、`inference_kind`、`rank_X`、`cond_X`、`pseudo_r2_definition`、可选 `objective_check`；**禁止**捏造 Hansen 键。 |

### 4. App / CLI（定稿）

- **`qreg y x1 x2, quantile(0.5)`** → `model_type: "quantile"`，`quantile_tau: 0.5`。
- **展示：** `QuantileSummaryPanel` 只读 $\tau$、伪 $R^2$、推断口径一行；`TidyTable` 复用。

### 5. Task 清单

| ID | 路径 / 位置 | 目标 |
|----|----------------|------|
| S5.4-J1 | `packages/MetricaQuantile.jl` | 单 $\tau$ 拟合、`glance`/`tidy`、`MODEL_REGISTRY`。 |
| S5.4-J2 | 同上 + `serialize.jl` | `result_to_payload`、`diagnostics`/`warnings`。 |
| S5.4-J3 | `packages/MetricaQuantile.jl/test` + `datasets/demo/quantile_demo.csv` | 主路径 + 秩不足 / 极端 $\tau$ 失败或警告。 |
| S5.4-B1 | `julia_bridge_entry.jl`、`julia_daemon.jl`、`MetricaRuntime.jl` | registry + kwargs 过滤 + 分派 `result_to_payload`。 |
| S5.4-R1 | `runtime/.../lib.rs`、`server.rs` | `quantile_tau` 与校验。 |
| S5.4-R2 | `vertical_slice.rs` | `quantile` 断言 `glance.metrics.tau` 与 `tidy` 非空。 |
| S5.4-A1 | `commandGrammar`/`commandParser`/`protocol`/Result/`QuantileSummaryPanel` | `qreg` 与展示。 |
| S5.4-A2 | Vitest | `quantile(0.5)` 与非法 $\tau$。 |
| S5.4-D1 | `runtime-protocol.md`、`tutorials/s5-quantile-regression.md` | 协议 + 教程。 |
| S5.4-D2 | 本节与总规 §7 | 措辞对齐。 |

### 6. 验收

- Julia：`Pkg.test(MetricaQuantile)`。
- Runtime：`vertical_slice` 含 `quantile`。
- App：Vitest 覆盖解析；消息流结构化。

### 7. 风险

- **密度估计：** Hall–Sheather 带宽在极小 $n$ 或退化残差下 `fhat0` 异常 → 结构化 `warning` 或 `ModelError`，勿静默 NaN。
- **$\tau$ 边界：** 近 0/1 时解释变量效应方差放大 → `warnings` 提示教学风险。

---

## 验证与未覆盖风险（`S5.0`）

- **已做：** 全仓 `grep` 旧 `spec`/`plan` 路径与 `ui-project-button-system-plan.md`；`docs/superpowers` 目录仅剩本计划与主设计；Runtime 路由与 `julia_bridge_entry.jl` / `julia_daemon.jl` 对照更新协议文档。
- **未做 / 风险：** 未运行自动化外链检查 CI；若外部 Wiki 仍链接已删除的 `plan` 文件，需人工更新。后续 `S5.x` 代码变更后须再次同步 `runtime-protocol` 中的端点表与 `model_type` 表。

## 验证习惯

- 文档删除后全仓 `grep` 旧路径；Julia/Runtime 变更后更新 `runtime-protocol` 端点表与 `model_type` 表。
- 阶段完成说明须列出**已验证范围**与**未覆盖风险**（见 `AGENTS.md` 完成定义）。
