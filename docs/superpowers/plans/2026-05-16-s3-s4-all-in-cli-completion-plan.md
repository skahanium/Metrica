# S3 / S4 All-in-CLI 补全实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 逐任务实现。所有步骤使用 checkbox 追踪；实现前必须先写失败测试，除非该任务只新增文档或静态教学数据。

**Goal:** 补齐 S3 / S4 剩余验收缺口，使项目保存、运行记录、重跑、报告导出、图表导出、模型对比、S4 教学资产与 warning 覆盖都能通过 CLI 主路径完成。

**Architecture:** App 层负责 all-in-cli 命令解析、分发、结果流展示、文件选择器路径补全与工作区状态恢复；Runtime 继续使用既有 S3 端点，不新增业务逻辑层；Core 包只保留既有结构化结果与 warning 语义，不让 UI 解析打印文本。S4 剩余工作以教学数据、教程命令序列、warning coverage 清单和垂直切片测试收口。

**Tech Stack:** React 19 + TypeScript + Zustand + Ant Design；Rust axum Runtime；Julia 多包结构；Vitest / Testing Library；Rust integration tests；Julia package tests。

## 文档状态（收口说明）

| 范围 | 状态 | 说明 |
|------|------|------|
| App CLI（Task 1–6 代码路径） | **已落地** | `commandGrammar` / `commandParser` / `App.tsx` 路由 / `commandExecutor` / `chartExport` / `healthPolling` 等已在仓库实现。 |
| 前端验收 | **已通过** | `cd apps/metrica-desktop && npm test`（含 `commandExecutor.test.ts`）；`npm run build`。 |
| S4 教程（Task 8） | **已创建** | `tutorials/s4-discrete.md`、`s4-causal.md`、`s4-timeseries.md`、`s4-survey.md`。 |
| S4 warning 对照（Task 9 文档） | **已创建** | `docs/architecture/s4-warning-coverage.md`（含「部分满足 / Backlog」行，避免虚报全覆盖）。 |
| Task 9 Julia 包测试增量 | **未作为本迭代硬门槛** | 仍以各包既有 `runtests.jl` 为主；负例矩阵见 warning 文档 **Backlog**。 |
| Task 10 Runtime 垂直切片 | **已维护** | `cargo test --test vertical_slice` 在 CI/本地按需执行。 |

---

## 0. 施工边界与硬约束

- all-in-cli 的硬约束适用于分析、建模、诊断、重跑、模型对比、导出格式选择与 run 选择。
- 文件选择器只允许辅助取得路径：`use`、`save`、`load`、`export ... using(...)` 缺省路径时可以打开系统 picker；picker 不得决定模型、格式、run_id 或比较对象。
- 鼠标交互可以用于查看、展开、复制、选择文件路径，但不得成为 S3/S4 验收路径。
- 不新增 Runtime 模型对比端点；S3 v1 模型对比消费已有 `RunRecord.result_summary`。
- 不把图表导出下沉到 Core 计量逻辑。v1 图表导出优先基于 App 中已有 ECharts 图表实例或结构化结果生成的图表视图。
- 不更新或删除用户未跟踪的 `docs/roadmap/2026-05-16-s3-s4-代码对照矩阵.md`，除非用户明确要求。

## 1. 文件责任清单

### App 命令与状态

- Modify: `apps/metrica-desktop/src-react/services/commandGrammar.ts`
  - 增加或修正 `load`、`runs`、`rerun`、`export`、`compare` 的语法树。
  - `export` 支持格式位置参数和 `using(...)`、`format(...)` 选项。
- Modify: `apps/metrica-desktop/src-react/services/commandParser.ts`
  - 确保 `load` 可作为独立命令或别名稳定解析。
  - 为非模型命令避免产生 `ModelSpec`。
- Modify: `apps/metrica-desktop/src-react/components/App.tsx`
  - 在路由表显式分发 `load`、`runs`、`rerun`、`export`、`compare`。
  - 不允许这些命令 fallthrough 到 `handleModel`。
- Modify: `apps/metrica-desktop/src-react/services/commandExecutor.ts`
  - 新增 `handleLoad`、`handleRuns`、`handleRerun`、`handleExport`、`handleCompare`。
  - 修复 `handleSave` 保存数据谱系。
- Modify: `apps/metrica-desktop/src-react/services/nativeHost.ts`
  - 在现有 `pickCsvFile` 模式上增加项目文件打开、保存路径选择、导出路径选择的 helper。
  - helper 只返回路径和取消状态。
- Modify: `apps/metrica-desktop/src-react/stores/projectStore.ts`
  - 不新增比较结果缓存；比较结果作为结果流 `data` message 保存。
  - 增加 `lastRecoveredAt: string | null` 和 `markRecovered()`，仅用于 Julia 重启后的工作区恢复提示节流。
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts`
  - 将 `DataResult` 扩展为前端 data message union，新增 `runs`、`export_preview`、`model_comparison` 三个 discriminant。
  - 不改变 Runtime 公开 wire schema，除非测试证明现有类型无法表达。

### App 展示

- Modify: `apps/metrica-desktop/src-react/components/DataResultBlock.tsx`
  - 渲染 `runs` 表、导出预览、模型对比表。
  - 保持只消费结构化对象，不解析文本报告。
- Modify: `apps/metrica-desktop/src-react/components/EventStudyPlot.tsx`
  - 暴露可由命令调用的图表导出能力，或将导出逻辑放入专用 service 并由组件注册图表实例。
- Create: `apps/metrica-desktop/src-react/services/chartExport.ts`
  - 负责从已知 run/result 中定位可导出的图表并生成 SVG/PNG data URL。
  - 若 run 无图表，返回结构化错误，不静默成功。

### S4 教学资产与验证

- Create: `datasets/teaching/s4_discrete_demo.csv`
- Create: `datasets/teaching/s4_timeseries_demo.csv`
- Create: `datasets/teaching/s4_survey_demo.csv`
- Create: `tutorials/s4-discrete.md`
- Create: `tutorials/s4-causal.md`
- Create: `tutorials/s4-timeseries.md`
- Create: `tutorials/s4-survey.md`
- Create: `docs/architecture/s4-warning-coverage.md`
  - 记录每个模型族的常见误用、期望 warning/error code、测试位置。

### 新增前端结构化结果类型

实现者应在 `types/protocol.ts` 中添加以下前端专用类型，并把 `DataResult` 扩展为：

```typescript
export type DataResult =
  | DescribeResult
  | SummarizeResult
  | TabulateResult
  | RunsTableResult
  | ExportPreviewResult
  | ModelComparisonResult;
```

新增类型字段固定如下：

- `RunsTableResult`
  - `kind: 'runs'`
  - `dataset_summary: { row_count: number; column_count: number }`
  - `runs: Array<{ run_id: string; action: string; model_type?: string | null; dataset_path: string; status: string; finished_at: string }>`
- `ExportPreviewResult`
  - `kind: 'export_preview'`
  - `dataset_summary: { row_count: 1; column_count: 4 }`
  - `run_id: string`
  - `format: string`
  - `target_path: string | null`
  - `content_preview: string`
- `ModelComparisonResult`
  - `kind: 'model_comparison'`
  - `dataset_summary: { row_count: number; column_count: number }`
  - `family: 'discrete' | 'causal'`
  - `rows: Array<Record<string, string | number | null>>`

### 测试

- Modify: `apps/metrica-desktop/src-react/__tests__/commandGrammar.test.ts`
- Modify: `apps/metrica-desktop/src-react/__tests__/commandParser.test.ts`
- Modify: `apps/metrica-desktop/src-react/__tests__/App.test.tsx`
- Modify: `apps/metrica-desktop/src-react/__tests__/runtimeClient.test.ts`
- Add/Modify: `apps/metrica-desktop/src-react/__tests__/commandExecutor.test.ts`（若当前没有可直接测试 handler 的文件）
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`
- Modify: `packages/MetricaDiscrete.jl/test/runtests.jl`
- Modify: `packages/MetricaCausal.jl/test/runtests.jl`
- Modify: `packages/MetricaTimeSeries.jl/test/runtests.jl`
- Modify: `packages/MetricaSurvey.jl/test/runtests.jl`

## 2. CLI 接口冻结

### 2.1 项目与运行记录

- `save [path]`
  - 有路径：若路径以 `.metrica` 或 `.json` 结尾，使用其父目录作为 working dir；否则使用该路径作为项目 working dir。
  - 无路径：调用保存路径 picker；picker 返回路径后反馈等价命令 `save "..."`。
  - 必须保存 `data_lineage`，不得写死 `null`。
- `load [path]`
  - 有路径：若路径指向文件，使用其父目录作为 working dir；若路径指向目录，直接作为 working dir。
  - 无路径：调用项目文件 picker；picker 返回路径后反馈等价命令 `load "..."`。
  - 加载后设置 `projectPath`、`manifest`、`runHistory`、`sourcePath`、`activePath`。
- `runs`
  - 列出当前项目 working dir 下 run records。
  - 输出结构化表，不要求用户点选。
- `rerun <run_id>`
  - run_id 必填。
  - 成功时追加结果流消息；若 Runtime 返回 `run_record`，同步 `projectStore.appendRunRecord`。

### 2.2 导出

- `export markdown [run_id] [using("path.md")]`
- `export csv_tidy [run_id] [using("path.csv")]`
- `export csv_glance [run_id] [using("path.csv")]`
- `export csv_diagnostics [run_id] [using("path.csv")]`
- `export plot <run_id>, format(svg|png) [using("path")]`

规则：

- 非 plot 导出如果省略 `run_id`，默认最近一次成功 `fit_model` run。
- plot 导出必须显式给 `run_id`，避免图表对象选择隐式化。
- `using(...)` 省略时可打开保存路径 picker；取消 picker 时命令返回 false，并给 CLI warning。
- `format(...)` 只用于 `export plot`；报告/CSV 格式由第一个位置参数决定。
- 导出结果要写入结果流，至少包含 `run_id`、格式、目标路径或预览摘要。
- 当前仓库没有明确的 native 写文件 helper 时，不在本任务中新增 Tauri 写文件 IPC；v1 使用浏览器 `downloadText` / `downloadDataUrl` 下载，并在 `ExportPreviewResult.target_path` 中记录用户选择的路径或建议文件名。

### 2.3 模型对比

- `compare <run_id> <run_id> [...]`
- `compare clear`

兼容性规则：

- 所有 run 必须存在于 `projectStore.runHistory` 或通过 `listRuns` 拉取后存在。
- 所有 run 必须 `action === "fit_model"`、`status === "success"`、有 `result_summary`。
- 所有 run 的 `dataset_ref.path` 必须一致。
- v1 可比较家族：
  - 离散模型：`logit`、`probit`、`poisson`、`ordered_logit`、`multinomial_logit`、`negbin`，展示 `nobs`、`loglikelihood/loglik`、`aic`、`bic`。
  - 因果模型：`did`、`event_study`、`ipw`、`psm`、`aipw`，展示 `ate`、`att`、`atu`、对应 SE、`n_treated`、`n_control`。
- 不支持家族要返回 CLI warning：说明当前 v1 不比较该模型族，而不是 fallthrough 或生成空表。

## 3. 任务分解

### Task 1: 命令语法与解析冻结

**Files:**
- Modify: `apps/metrica-desktop/src-react/services/commandGrammar.ts`
- Modify: `apps/metrica-desktop/src-react/services/commandParser.ts`
- Test: `apps/metrica-desktop/src-react/__tests__/commandGrammar.test.ts`
- Test: `apps/metrica-desktop/src-react/__tests__/commandParser.test.ts`

- [ ] 写失败测试：`load`、`runs`、`rerun run-1`、`export markdown run-1, using("/tmp/a.md")`、`export plot run-1, format(svg) using("/tmp/a.svg")`、`compare run-1 run-2` 均能解析为非模型命令。
- [ ] 写失败测试：`rerun` 缺 run_id、`compare run-1`、`export plot run-1` 缺 `format(...)` 时产生明确 parse 或 handler warning。
- [ ] 运行 `cd apps/metrica-desktop && npm test -- src-react/__tests__/commandParser.test.ts src-react/__tests__/commandGrammar.test.ts`，确认新测试失败且失败原因是命令未接入。
- [ ] 实现语法树和解析补齐。
- [ ] 再运行同一命令，确认测试通过。

### Task 2: 项目命令路由与 handler

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/App.tsx`
- Modify: `apps/metrica-desktop/src-react/services/commandExecutor.ts`
- Modify: `apps/metrica-desktop/src-react/services/nativeHost.ts`
- Test: `apps/metrica-desktop/src-react/__tests__/App.test.tsx`
- Test: `apps/metrica-desktop/src-react/__tests__/commandExecutor.test.ts`

- [ ] 写失败测试：输入 `load "/tmp/proj.metrica"` 调用 `loadProject/listRuns`，不调用 `fitModel`。
- [ ] 写失败测试：输入 `runs` 调用 `listRuns` 并向结果流追加结构化 data message。
- [ ] 写失败测试：输入 `rerun run-1` 调用 `rerunTask`，成功后追加 result message 和 run record。
- [ ] 写失败测试：`save` 使用当前 `projectStore.manifest.data_lineage`，保存请求中 `data_lineage.operations` 不丢失。
- [ ] 运行 App/handler 相关 vitest，确认失败。
- [ ] 实现 `handleLoad`、`handleRuns`、`handleRerun`，并在 `App.tsx` 显式路由。
- [ ] 修复 `handleSave`：从 manifest 复用谱系；manifest 为空时构造最小谱系对象。
- [ ] 实现 picker helper 的接口，但测试中 mock 返回路径即可，不依赖真实系统对话框。
- [ ] 再运行同一测试，确认通过。

### Task 3: 导出命令闭环

**Files:**
- Modify: `apps/metrica-desktop/src-react/services/commandExecutor.ts`
- Modify: `apps/metrica-desktop/src-react/stores/exportStore.ts`
- Modify: `apps/metrica-desktop/src-react/services/nativeHost.ts`
- Modify: `apps/metrica-desktop/src-react/components/DataResultBlock.tsx`
- Test: `apps/metrica-desktop/src-react/__tests__/App.test.tsx`
- Test: `apps/metrica-desktop/src-react/__tests__/runtimeClient.test.ts`

- [ ] 写失败测试：`export markdown run-1, using("/tmp/r.md")` 调用 `exportReport({ runId: "run-1", format: "markdown" })`。
- [ ] 写失败测试：`export csv_tidy, using("/tmp/tidy.csv")` 在省略 run_id 时选最近一次成功模型 run。
- [ ] 写失败测试：`export csv_glance bad-run` 在 run 不存在时给 CLI warning，不调用 Runtime。
- [ ] 写失败测试：`using(...)` 缺省时调用保存 picker，picker 取消时不调用 `exportReport`。
- [ ] 实现 `handleExport`，并让结果流显示导出摘要。
- [ ] 调用 `downloadText` 下载 Markdown/CSV；若 picker 返回了路径，将路径保存到 `ExportPreviewResult.target_path`，但不承诺已由 native 精确写入该绝对路径。
- [ ] 运行相关 vitest，确认通过。

### Task 4: 图表导出命令

**Files:**
- Create: `apps/metrica-desktop/src-react/services/chartExport.ts`
- Modify: `apps/metrica-desktop/src-react/services/commandExecutor.ts`
- Modify: `apps/metrica-desktop/src-react/components/EventStudyPlot.tsx`
- Test: `apps/metrica-desktop/src-react/__tests__/App.test.tsx`
- Add: `apps/metrica-desktop/src-react/__tests__/chartExport.test.ts`

- [ ] 写失败测试：`export plot run-event, format(svg) using("/tmp/event.svg")` 对 event study run 生成 SVG data URL 或调用可 mock 的 chart exporter。
- [ ] 写失败测试：`export plot run-ols, format(svg)` 对无图表 run 返回 CLI warning。
- [ ] 写失败测试：`export plot run-event, format(pdf)` 拒绝不支持格式。
- [ ] 实现 `chartExport.ts` 的最小能力：识别 `result_summary.glance.model === "event_study"`，导出 SVG/PNG。
- [ ] 若无法在单元测试环境拿到 ECharts 实例，则将图表导出服务设计为可注入 exporter，组件运行时注册实例，测试 mock exporter。
- [ ] 运行 chart/App 测试确认通过。

### Task 5: CLI 模型对比

**Files:**
- Modify: `apps/metrica-desktop/src-react/services/commandExecutor.ts`
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts`
- Modify: `apps/metrica-desktop/src-react/components/DataResultBlock.tsx`
- Test: `apps/metrica-desktop/src-react/__tests__/App.test.tsx`
- Add: `apps/metrica-desktop/src-react/__tests__/modelComparison.test.ts`

- [ ] 写失败测试：两个同数据集离散模型 run 生成比较表，包含 `run_id`、`model`、`nobs`、`aic`、`bic`。
- [ ] 写失败测试：不同 `dataset_ref.path` 的 run 被拒绝，并给 CLI warning。
- [ ] 写失败测试：非成功 run、非 `fit_model` run、缺 `result_summary` run 被拒绝。
- [ ] 写失败测试：`compare clear` 清除当前比较结果消息或比较缓存。
- [ ] 实现兼容性检查和比较结果构造。
- [ ] 渲染比较表时只读结构化字段，不解析 `summary_text`。
- [ ] 运行相关 vitest 确认通过。

### Task 6: 工作区状态恢复

**Files:**
- Modify: `apps/metrica-desktop/src-react/services/healthPolling.ts`
- Modify: `apps/metrica-desktop/src-react/stores/projectStore.ts`
- Modify: `apps/metrica-desktop/src-react/stores/datasetStore.ts`
- Test: `apps/metrica-desktop/src-react/__tests__/App.test.tsx`
- Add: `apps/metrica-desktop/src-react/__tests__/healthPolling.test.ts`

- [ ] 写失败测试：当 health 从 unhealthy 变回 healthy，App 恢复 `manifest.source_dataset`、`manifest.active_dataset` 和 `runHistory`。
- [ ] 写失败测试：恢复不触发模型自动重跑；用户仍需 `rerun <run_id>`。
- [ ] 实现恢复逻辑：只恢复 App store，不恢复 Julia 内存状态。
- [ ] CLI feedback 中说明“Julia 环境已重启，项目上下文已恢复；如需重算请使用 rerun”。
- [ ] 运行相关测试确认通过。

### Task 7: S4 教学数据集

**Files:**
- Create: `datasets/teaching/s4_discrete_demo.csv`
- Create: `datasets/teaching/s4_timeseries_demo.csv`
- Create: `datasets/teaching/s4_survey_demo.csv`

- [ ] 创建离散模型数据：列至少包含 `y_bin`、`y_count`、`x1`、`x2`、`group`，可支持 `logit y_bin x1 x2` 与 `poisson y_count x1 x2`。
- [ ] 创建时间序列数据：列至少包含 `time`、`y`、`x1`、`x2`，可支持 `dfuller y`、`arima y, ar(1) i(1) ma(0)`、`var y x1, lags(1)`。
- [ ] 创建 survey 数据：列至少包含 `y`、`y_bin`、`y_count`、`x1`、`x2`、`wt`、`strata`、`psu`，可支持 `svy regress/logit/poisson`。
- [ ] 数据体积保持小型、确定性、可读；不引入外部下载依赖。
- [ ] 核对 CSV 表头和教程命令一致。

### Task 8: S4 教程命令序列

**Files:**
- Create: `tutorials/s4-discrete.md`
- Create: `tutorials/s4-causal.md`
- Create: `tutorials/s4-timeseries.md`
- Create: `tutorials/s4-survey.md`

- [ ] 每篇教程必须以 CLI 命令为主路径，不写“点击按钮运行模型”。
- [ ] 每篇包含：数据路径、最小命令序列、预期结构化输出字段、常见 warning 解读、导出命令。
- [ ] 因果教程可复用 `datasets/demo/did_demo.csv`。
- [ ] 文档正文使用简体中文；代码块中的注释也使用简体中文。
- [ ] 用 `rg` 核对教程引用的数据路径都存在。

### Task 9: S4 warning coverage 文档与测试

**Files:**
- Create: `docs/architecture/s4-warning-coverage.md`
- Modify: `packages/MetricaDiscrete.jl/test/runtests.jl`
- Modify: `packages/MetricaCausal.jl/test/runtests.jl`
- Modify: `packages/MetricaTimeSeries.jl/test/runtests.jl`
- Modify: `packages/MetricaSurvey.jl/test/runtests.jl`

- [ ] 文档列出四类模型族：Discrete、Causal、TimeSeries、Survey。
- [ ] 每类列出至少 3 个常见误用或教学关键场景。
- [ ] 每行包含：场景、期望 `ModelWarning` 或 `ModelError` code、当前测试文件、验收状态。
- [ ] 补 Julia 测试优先覆盖已有逻辑：缺失删样、未收敛、Poisson 过度离散、事件研究平行趋势、单位根样本不足或滞后设置、survey 权重/strata/PSU 错误。
- [ ] 运行对应包测试，不能用“存在 warning”替代 code/hint 断言。

### Task 10: Runtime 垂直切片补充

**Files:**
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`

- [ ] 写测试：Logit 命令通过 `fit_model` 返回 `glance.model` 和 `tidy`。
- [ ] 写测试：ARIMA 或 VAR 通过 `fit_model` 返回时间序列结构化字段。
- [ ] 写测试：Survey OLS 或 Survey Logit 通过 `fit_model` 返回 survey 结构化字段。
- [ ] 复用 `datasets/teaching/` 或测试临时 CSV。
- [ ] 运行 `cargo test --test vertical_slice`。

## 4. 验证命令清单

前端：

```bash
cd apps/metrica-desktop
npm test -- src-react/__tests__/commandParser.test.ts src-react/__tests__/commandGrammar.test.ts
npm test -- src-react/__tests__/App.test.tsx src-react/__tests__/runtimeClient.test.ts
npm test -- src-react/__tests__/commandExecutor.test.ts
npm test -- src-react/__tests__/DataResultBlock.test.tsx
npm test
npm run build
```

Runtime：

```bash
cargo test --test vertical_slice
```

Julia：

```bash
julia --project=packages/MetricaDiscrete.jl -e 'using Pkg; Pkg.test()'
julia --project=packages/MetricaCausal.jl -e 'using Pkg; Pkg.test()'
julia --project=packages/MetricaTimeSeries.jl -e 'using Pkg; Pkg.test()'
julia --project=packages/MetricaSurvey.jl -e 'using Pkg; Pkg.test()'
```

文档与数据：

```bash
rg -n "datasets/(teaching|demo)/" tutorials docs/architecture/s4-warning-coverage.md
find datasets/teaching tutorials -maxdepth 1 -type f | sort
```

## 5. 完成判定

- `load/runs/rerun/export/compare` 全部由 CLI 路由，不再进入模型 fallthrough。
- `save` 保留数据谱系。
- Markdown/CSV/plot 导出都能通过 CLI 表达格式、run_id 和路径。
- 模型对比不依赖鼠标选择，且不兼容模型会被结构化拒绝。
- Julia 重启后恢复 App 工作区状态，但不伪称恢复 Julia 内存对象。
- S4 每个模型族至少有一个教学数据集和一个 CLI 教程。
- S4 warning coverage 文档与测试能逐项对应。
- 更新路线图矩阵时，只把已通过测试的条目标为“已满足”。
