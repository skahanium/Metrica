# S4b MetricaCausal.jl 实施计划

> **Goal:** 创建 `MetricaCausal.jl` 包（DID / 事件研究 / IPW / PSM / AIPW / 处理效应），同步完成 Panel 公式解析器升级和 MODEL_REGISTRY 完整性修复。

> **Architecture:** Phase 1 升级 Panel 公式 → Phase 2 手写 TWFE → Phase 3 DID + 事件研究 → Phase 4 IPW/PSM/AIPW → Phase 5 处理效应汇总 → Phase 6 Runtime + App。每个阶段独立可测，不破坏已有基线。

> **Tech Stack:** Julia（MetricaCausal.jl / StatsModels / MetricaPanel / MetricaDiscrete）、Rust（axum handler）、TypeScript（React + ECharts）

---

## 优先级标注

| 标记 | 含义 |
|------|------|
| 🔴 | 阻塞后续阶段，必须最先完成 |
| 🟡 | 核心功能，本阶段主要交付 |
| 🟢 | 增强功能，不阻塞主链路 |

---

## Phase 1：Panel 公式解析器升级 🔴

**目标：** 统一公式接口为 StatsModels，修复 M4（Panel 注册 MODEL_REGISTRY）。

### Task 1.1：Panel 公式迁移到 StatsModels

**修改文件：**
- `packages/MetricaPanel.jl/src/MetricaPanel.jl`
- `packages/MetricaPanel.jl/src/fe.jl`
- `packages/MetricaPanel.jl/src/re.jl`
- `packages/MetricaPanel.jl/src/fd.jl`
- `packages/MetricaPanel.jl/src/between.jl`
- `packages/MetricaPanel.jl/src/cre.jl`

**要点：**
- 各估计器内 `parse_metrica_formula(formula)` 替换为 `MetricaLinear.parse_formula_term` + `collect_term_symbols`
- 设计矩阵构造从手动 `hcat` 改为调 `MetricaLinear.prepare_model_data`
- `PanelModel` 类型字段调整以兼容 StatsModels

**验证：** 所有已有 Panel 测试通过，`julia --project=packages/MetricaPanel.jl -e 'include("test/runtests.jl")'`

### Task 1.2：Panel 注册 MODEL_REGISTRY + daemon 分支移除

**修改文件：**
- `packages/MetricaPanel.jl/src/MetricaPanel.jl` — 添加 `__init__()` 注册 `"panel"` 和 `"panel_iv"`
- `scripts/julia_daemon.jl` — 移除 `model_type == "panel"` 硬编码分支，统一走 `MODEL_REGISTRY` dispatch

**daemon 改造要点：** Panel 的 `PanelData` 构造 + `panel_diagnostics` 需要适配通用 dispatch 流程；建议在 `handle_request` 外单独处理 Panel 特有的 `result_to_payload` + diagnostics，但不通过 `model_type` 字符串分支。

**验证：** daemon E2E 测试（curl 发送 OLS + Logit + Panel FE 请求，全部成功）

**承诺：** Phase 1 不破坏任何已有测试。

---

## Phase 2：TWFE 双向固定效应吸收算法 🟡

**创建文件：**
- `packages/MetricaCausal.jl/Project.toml`
- `packages/MetricaCausal.jl/src/MetricaCausal.jl`
- `packages/MetricaCausal.jl/src/twfe.jl`

### Task 2.1：创建 MetricaCausal.jl 包骨架

类型定义 + 依赖声明 + `__init__()` 注册到 MODEL_REGISTRY（初始注册空，随各 Phase 逐步添加）。

### Task 2.2：实现 TWFE 交替投影算法

**接口：**
```julia
fit_twfe(X::Matrix, y::Vector, id::Vector, time::Vector; max_iter=10, tol=1e-8)
# → (coefficients, fitted, residuals, vcov, stderror, dof_corrected)
```

**算法：** Entity-demean → Time-demean → 迭代至收敛。自由度校正 = N - K - (N_id - 1) - (N_time - 1)。VCov = σ²(X_demeaned'X_demeaned)⁻¹。

**验证：** 与 `FixedEffectModels.jl` 的 `reg(df, @formula(y ~ x + fe(id) + fe(time)))` 交叉验证，系数差异 < 1e-6。测试数据集：Grunfeld（firm + year 双 FE）。

**承诺：** Phase 2 不破坏已有测试。

---

## Phase 3：DID + 事件研究 🟡

**创建文件：**
- `packages/MetricaCausal.jl/src/did.jl`
- `packages/MetricaCausal.jl/src/event_study.jl`
- `packages/MetricaCausal.jl/src/serialize.jl`

### Task 3.1：DID 估计器

**接口：**
```julia
fit(DIDModel, formula, data; panel_id, panel_time, treated_column, post_column, vcov=:cluster)
```

**内部流程：** StatsModels 展开公式（含 `treat * post` 交互）→ 调 TWFE → 提取 `treat:post` 交互项系数作为处理效应。

**输出：** DIDFitResult — glance（处理效应、p 值、n_treated、n_control、n_pre、n_post）、tidy（完整系数表）、warnings（平行趋势不可检验的提示 ≥3 期时输出事前趋势 F 检验）。

### Task 3.2：事件研究估计器

**接口：**
```julia
fit(EventStudyModel, formula, data; panel_id, panel_time, treated_column, event_time_column, pre_periods=3, post_periods=5)
```

**内部展开：** 各相对时期虚拟变量 × treated 交互项，联立估计。基准期 = -1（事件前一期）。

**输出：** EventStudyFitResult — 各期系数向量 + 标准误 + 事前趋势联合 F 检验 p 值 + 平行趋势假设判断。

### Task 3.3：序列化 + MODEL_REGISTRY 注册

`result_to_payload` 分派 DIDFitResult 和 EventStudyFitResult。注册 `"did"`、`"event_study"` 到 MODEL_REGISTRY。

**验证：** 
- DID 与 Stata `reghdfe y treat##post x, absorb(id time) vce(cluster id)` 教学口径对比
- 事件研究事前趋势系数应接近 0（模拟数据）
- MetricaDiscrete + MetricaPanel 已有测试不退化

---

## Phase 4：IPW + PSM + AIPW 🟡

**创建文件：**
- `packages/MetricaCausal.jl/src/ipw.jl`
- `packages/MetricaCausal.jl/src/psm.jl`
- `packages/MetricaCausal.jl/src/doubly_robust.jl`

### Task 4.1：IPW

调 S4a Logit 估计倾向得分 → 构造权重 → 加权均值差 = ATE。Robust sandwich SE。

### Task 4.2：PSM

最近邻匹配（1:N + 卡尺）+ 核匹配。匹配后 ATT = 匹配样本均值差。输出平衡性检验表（标准化偏差 + t 检验）。

### Task 4.3：AIPW

OLS（结果模型）+ Logit（倾向得分）→ AIPW 公式。比纯 IPW 或纯回归更稳健。

**验证：** 
- IPW ATT 在模拟数据上与手算结果一致
- PSM 匹配后标准化偏差 < 10%
- AIPW 双重稳健性：结果模型或倾向模型一个错误，另一个正确时估计仍一致（模拟验证）
- 已有测试不退化

---

## Phase 5：处理效应汇总 🟢

**创建文件：**
- `packages/MetricaCausal.jl/src/treatment_effects.jl`

### Task 5.1：TreatmentEffectSummary

统一 `TreatmentEffectSummary` 类型，各方法输出 ATE/ATT/ATU + SE。支持 `compare_estimates([did_result, ipw_result, psm_result, aipw_result])` 多方法对比。

**验证：** 四种方法在同一数据上的估计值一致（方向相同、量级相近）。

---

## Phase 6：Runtime + App 集成 🟡

### Task 6.1：Runtime 层

**修改文件：**
- `runtime/metrica-runtime/src/lib.rs` — `model_required_fields()` 新增 causal model_type
- Rust `ModelSpec` struct 新增 `treatment_column: Option<String>`

### Task 6.2：TypeScript 类型 + 状态

**修改文件：**
- `apps/metrica-desktop/src-react/types/protocol.ts` — 扩展 `model_type` union，新增 `CausalDiagnostics`、`TreatmentEffectSummary` 等类型
- `apps/metrica-desktop/src-react/stores/modelStore.ts` — 新增 `treatmentColumn` state，扩展 `buildModelSpec`
- `apps/metrica-desktop/src-react/services/runtimeClient.ts` — 扩展 `FitModelParams`

### Task 6.3：App 组件

**新建文件：**
- `apps/metrica-desktop/src-react/components/EventStudyPlot.tsx` — ECharts 事件研究系数图（置信带 + 事前/事后分隔线）
- `apps/metrica-desktop/src-react/components/DIDResultCards.tsx` — 处理效应卡片 + 平行趋势教学提示
- `apps/metrica-desktop/src-react/components/BalanceTable.tsx` — PSM 匹配前后协变量平衡性检验表
- `apps/metrica-desktop/src-react/components/TreatmentEffectSummary.tsx` — ATE/ATT/ATU 汇总卡片

**修改文件：**
- `apps/metrica-desktop/src-react/components/ModelForm.tsx` — OptGroup 新增"因果推断"组（DID、Event Study、IPW、PSM、AIPW）
- `apps/metrica-desktop/src-react/App.tsx` — 挂载新组件

### Task 6.4：E2E 验证

- Tauri 桌面应用完整链路：选择数据集 → 选 DID 模型 → 输入公式 → 运行 → 结果渲染
- 验证 EventStudyPlot 图表正确显示
- 验证已有 OLS / Panel / Logit 不退化

---

## 依赖关系图

```
Phase 1 (Panel 升级) ──→ Phase 2 (TWFE) ──→ Phase 3 (DID + ES)
                                                    │
                          S4a Logit ──→ Phase 4 (IPW/PSM/AIPW)
                                                    │
                                          Phase 5 (处理效应)
                                                    │
                                          Phase 6 (Runtime + App) ← 需要 S4a 的 MODEL_REGISTRY + CORS 修复已在位
```

Phase 4 可与 Phase 3 并行（均依赖 Phase 2，但互不依赖）。

---

## 验证清单（Phase 完成后逐项勾选）

- [ ] Phase 1: Panel 测试全部通过，daemon E2E Panel FE 请求成功
- [ ] Phase 2: TWFE 与 FixedEffectModels.jl 交叉验证 < 1e-6
- [ ] Phase 3: DID 处理效应方向正确，事件研究事前系数 ≈ 0
- [ ] Phase 4: PSM 匹配平衡性达标，AIPW 双重稳健性验证
- [ ] Phase 5: 四种方法估计一致
- [ ] Phase 6: Tauri 桌面应用端到端运行成功
- [ ] 全程: MetricaLinear / MetricaPanel / MetricaDiscrete 测试不退化
