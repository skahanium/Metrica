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

## 验证与未覆盖风险（`S5.0`）

- **已做：** 全仓 `grep` 旧 `spec`/`plan` 路径与 `ui-project-button-system-plan.md`；`docs/superpowers` 目录仅剩本计划与主设计；Runtime 路由与 `julia_bridge_entry.jl` / `julia_daemon.jl` 对照更新协议文档。
- **未做 / 风险：** 未运行自动化外链检查 CI；若外部 Wiki 仍链接已删除的 `plan` 文件，需人工更新。后续 `S5.x` 代码变更后须再次同步 `runtime-protocol` 中的端点表与 `model_type` 表。

## 验证习惯

- 文档删除后全仓 `grep` 旧路径；Julia/Runtime 变更后更新 `runtime-protocol` 端点表与 `model_type` 表。
- 阶段完成说明须列出**已验证范围**与**未覆盖风险**（见 `AGENTS.md` 完成定义）。
