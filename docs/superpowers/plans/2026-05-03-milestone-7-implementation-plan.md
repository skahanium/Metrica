# 里程碑 7：面板模型成熟化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

状态：已完成
设计规格：`docs/superpowers/specs/2026-05-03-milestone-7-panel-models-design.md`

**Goal:** 将 MetricaPanel.jl 从教学口径升级为研究口径，补全 HDFE、Driscoll-Kraay、CRE、面板 IV。

**Architecture:** 6 个 Part 按层横切。Part 1 引入 FixedEffectModels.jl 并重构 FE 基础设施，Part 2-4 独立实现 DK/CRE/PanelIV，Part 5 贯通 Runtime/App，Part 6 补数据和测试。

**Tech Stack:** Julia 1.12, FixedEffectModels.jl, MetricaBase.jl, MetricaPanel.jl, Rust/axum, React 19, TypeScript 5

---

## 文件结构

### Part 1
- Modify: `packages/MetricaPanel.jl/Project.toml` — 添加 FixedEffectModels.jl 依赖
- Create: `packages/MetricaPanel.jl/src/hdfde.jl` — HDFE 估计器
- Modify: `packages/MetricaPanel.jl/src/MetricaPanel.jl` — 导出 HDFE

### Part 2
- Create: `packages/MetricaPanel.jl/src/dk.jl` — Driscoll-Kraay 协方差
- Modify: `packages/MetricaPanel.jl/src/diagnostics.jl` — 扩展诊断

### Part 3
- Create: `packages/MetricaPanel.jl/src/cre.jl` — CRE 估计器

### Part 4
- Create: `packages/MetricaPanel.jl/src/panel_iv.jl` — 面板 IV

### Part 5
- Modify: `runtime/metrica-runtime/src/lib.rs` — ModelSpec 扩展
- Modify: `runtime/metrica-runtime/src/server.rs` — validate 扩展
- Modify: `scripts/julia_daemon.jl` — 面板 IV/HDFE 分支
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts` — 类型扩展
- Modify: `apps/metrica-desktop/src-react/stores/modelStore.ts` — 状态扩展
- Modify: `apps/metrica-desktop/src-react/components/ModelForm.tsx` — 表单扩展

### Part 6
- Create: `datasets/teaching/nlsy_panel.csv` — NLSY 教学子集
- Modify: `packages/MetricaPanel.jl/test/runtests.jl` — 黄金样例测试

---

## Part 1：引入 FixedEffectModels.jl + HDFE

### Task 1.1：添加依赖并创建 HDFE 估计器

**Files:** `packages/MetricaPanel.jl/Project.toml`, `packages/MetricaPanel.jl/src/hdfde.jl`, `packages/MetricaPanel.jl/src/MetricaPanel.jl`

- [ ] 在 Project.toml 添加 `FixedEffectModels` 依赖
- [ ] 创建 `hdfde.jl`：`HDFEModel` 规格对象（formula, fe_spec::Vector{Symbol}），`HDFEFitResult` 结构
- [ ] 实现 `fit_hdfde(panel_data, formula; fe_spec)` 函数，内部调用 `FixedEffectModels.reg`
- [ ] 为 `HDFEFitResult` 实现 glance/tidy/augment 协议方法
- [ ] 在 MetricaPanel.jl 中 include 并导出
- [ ] 测试：Grunfeld 数据双向 FE（firm+year）拟合，验证系数和 R²
- [ ] Commit

---

## Part 2：Driscoll-Kraay 协方差

### Task 2.1：实现 DK 协方差估计器

**Files:** `packages/MetricaPanel.jl/src/dk.jl`, `packages/MetricaPanel.jl/src/diagnostics.jl`

- [ ] 创建 `dk.jl`：`compute_dk_vcov(residuals, X, panel_data; bandwidth)` 函数
- [ ] 实现标准 DK：按时间期分组计算得分，Newey-West 加权截面平均
- [ ] 实现 IV-DK：面板 IV 残差和第二阶段设计矩阵的 DK 协方差
- [ ] 在 `panel_diagnostics` 中添加 DK 选项
- [ ] 测试：模拟数据验证 DK 标准误 > classical 标准误（存在截面相关时）
- [ ] Commit

---

## Part 3：CRE/Mundlak 独立估计器

### Task 3.1：实现 CRE 估计器

**Files:** `packages/MetricaPanel.jl/src/cre.jl`, `packages/MetricaPanel.jl/src/MetricaPanel.jl`

- [ ] 创建 `cre.jl`：`CREModel` 规格对象，`CREFitResult` 结构
- [ ] 实现 `fit_crea(panel_data, formula)` 函数：计算组均值 -> 作为回归元 -> OLS
- [ ] 组均值系数单独标记（`group_mean_*`），便于用户检验 E(u_i | X_i)
- [ ] 为 `CREFitResult` 实现 glance/tidy/augment
- [ ] 测试：Grunfeld 数据 CRE 拟合，验证组均值系数存在且可解释
- [ ] Commit

---

## Part 4：面板 IV

### Task 4.1：实现面板 IV 估计器

**Files:** `packages/MetricaPanel.jl/src/panel_iv.jl`, `packages/MetricaPanel.jl/src/MetricaPanel.jl`

- [ ] 创建 `panel_iv.jl`：`PanelIVModel` 规格对象（formula, instruments, endog, id, time），`PanelIVFitResult` 结构
- [ ] 实现面板感知的两阶段估计：第一阶段按面板结构回归内生变量到工具变量
- [ ] 弱工具变量诊断（第一阶段 F 统计量）
- [ ] 支持 DK 协方差（调用 Part 2 的 `compute_dk_vcov`）
- [ ] 为 `PanelIVFitResult` 实现 glance/tidy/augment
- [ ] 测试：构造面板 IV 数据，验证估计和诊断
- [ ] Commit

---

## Part 5：面板诊断升级 + Runtime/App 贯通

### Task 5.1：升级 Hausman 和 BP LM 诊断

**Files:** `packages/MetricaPanel.jl/src/diagnostics.jl`

- [ ] Hausman 检验升级为完整协方差矩阵口径（FE 与 RE 的 vcov 差值矩阵）
- [ ] BP LM 扩展支持不平衡面板
- [ ] 测试：与 Stata `hausman` 命令结果对齐
- [ ] Commit

### Task 5.2：Runtime/App 贯通

**Files:** `runtime/metrica-runtime/src/lib.rs`, `runtime/metrica-runtime/src/server.rs`, `scripts/julia_daemon.jl`, `apps/metrica-desktop/src-react/types/protocol.ts`, `apps/metrica-desktop/src-react/stores/modelStore.ts`, `apps/metrica-desktop/src-react/components/ModelForm.tsx`

- [ ] Rust ModelSpec 添加 `fe_spec` 字段（Vec<String>）
- [ ] Julia daemon 添加 `panel_hdfde`、`panel_cre`、`panel_iv` 分支
- [ ] App 面板方法下拉新增 HDFE / CRE / Panel IV 选项
- [ ] 端到端验证：App -> Runtime -> Julia -> 结果返回
- [ ] Commit

---

## Part 6：NLSY 教学数据 + 黄金样例测试

### Task 6.1：NLSY 教学子集

**Files:** `datasets/teaching/nlsy_panel.csv`, `datasets/teaching/nlsy_panel_meta.json`

- [ ] 生成 NLSY 教学子集（约 500 人 × 5 年）
- [ ] 元数据文件
- [ ] 验证可用于面板拟合和诊断
- [ ] Commit

### Task 6.2：黄金样例测试

**Files:** `packages/MetricaPanel.jl/test/runtests.jl`

- [ ] HDFE 与 Stata `xtreg, fe` 对齐
- [ ] DK 与 Stata `xttest2` 对齐
- [ ] CRE 组均值系数验证
- [ ] Panel IV 与 Stata `xtivreg` 对齐
- [ ] 所有现有 M3/M4 测试不受影响
- [ ] Commit
