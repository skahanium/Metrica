# 里程碑 7：面板模型成熟化

状态：已完成；本设计文档保留为 M7 的历史设计依据
日期：2026-05-03

> **新阶段归属：** 本文档属于 `S2（核心实证工作台）`。`M7` 保留为当前活跃里程碑编号，不单独承担长期阶段叙事。

> 历史收口约束：M7 实施期间，不开启 M8 或更高里程碑。引入 FixedEffectModels.jl 后，原有 FE 估计器需保持向后兼容。该约束现已完成收口。

## 背景

M3/M4 建立了教学口径的面板基础（FE/RE/FD/Between + Hausman/F/LM 诊断），但所有能力停留在单维固定效应和经典协方差。M7 将面板模型升级为研究口径：多维 FE、稳健协方差、CRE 和面板 IV。

## 架构决策

### 决策 1：引入 FixedEffectModels.jl

用于 HDFE（高维固定效应）估计。MetricaPanel.jl 的 FE 估计器保留为教学向简单实现，新增 `fit_hdfde` 函数调用 FixedEffectModels.jl 支持多维 FE（如 `fe(firm) + fe(year)`）。

### 决策 2：Driscoll-Kraay + IV-DK

在 MetricaPanel.jl 中实现 `compute_dk_vcov` 函数，支持：
- 标准 DK：截面相关 + 异方差 + 时序自相关
- IV-DK：面板 IV 模型的 DK 协方差

### 决策 3：独立 CRE 估计器

将 Mundlak 从 RE 内部实现提升为独立的 `CREModel` 估计器，支持用户检验 E(u_i | X_i) 的函数形式。

### 决策 4：面板 IV 在 MetricaPanel.jl

新增 `PanelIVModel`，复用 MetricaLinear.jl 的 IV 逻辑但感知面板结构（按个体分组处理第一阶段）。

## Part 分配

| Part | 内容 | 核心交付物 |
|------|------|-----------|
| Part 1 | 引入 FixedEffectModels.jl + HDFE | `fit_hdfde(panel_data, formula; fe_spec)` 函数；双向 FE 支持 |
| Part 2 | Driscoll-Kraay + IV-DK | `compute_dk_vcov(residuals, X, panel_data)` 函数；扩展 `panel_diagnostics` |
| Part 3 | CRE/Mundlak | `CREModel` 估计器；`fit_crea(panel_data, formula)` 函数 |
| Part 4 | 面板 IV | `PanelIVModel`/`PanelIVFitResult` 类型；面板感知的两阶段估计 |
| Part 5 | 面板诊断升级 + Runtime/App | Hausman 完整协方差矩阵；BP LM 不平衡面板支持；Runtime 面板 IV/GLS 贯通 |
| Part 6 | NLSY 数据 + 黄金样例 | NLSY 教学子集；与 Stata xtreg/xtivreg 对齐测试 |

## 非目标

- 动态面板 GMM（Arellano-Bond）— 延后到 M10+
- 面板 GLS — RE 已通过 Mundlak/CRE 覆盖
- 面板 Probit/Logit — 属于 M10
- 面板协整/单位根 — 属于 M12

## 验收标准

1. `fit(PanelModel, "y ~ x1", data; method=:hdfde, fe=[:firm, :year])` 双向 FE 可用
2. DK 协方差与 Stata `xttest2` 结果对齐
3. `fit(CREModel, "y ~ x1", data; id=:firm)` 返回含组均值系数的结果
4. `fit(PanelIVModel, "y ~ x1", data; instruments=["z1"], endog=["x1"], id=:firm, time=:year)` 可用
5. 面板诊断（Hausman/F/BP）升级为完整协方差口径
6. App 面板模型类型新增 HDFE/CRE/PanelIV 选项
7. 所有 M3/M4 现有测试不受影响
