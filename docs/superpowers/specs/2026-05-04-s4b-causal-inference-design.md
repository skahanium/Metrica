# S4b 因果推断：总体设计

> 状态：设计阶段。本文件定义 S4b（因果推断子阶段）的完整边界、架构与约束。

## 1. 目标

覆盖教学和常见应用研究中最常用的因果推断方法，使 Metrica 具备面板因果 + 截面因果的完整能力。

**核心原则：** 所有方法通过统一的 `fit(::Type{<:AbstractCausalModel}, formula, data; kwargs...)` 接口进入，公式 MUST 通过 StatsModels 解析，结果 MUST 为结构化 `glance` / `tidy` / `augment` 对象。

## 2. 包结构

### 2.1 MetricaCausal.jl

```
MetricaCausal.jl/
  src/
    MetricaCausal.jl       # 模块入口、类型定义、MODEL_REGISTRY 注册
    twfe.jl                # 双向固定效应吸收算法（自主实现）
    did.jl                 # DID（2×2 + 多期）+ 平行趋势检验
    event_study.jl         # 事件研究（含事前趋势检验）
    ipw.jl                 # 逆概率加权（IPW）
    psm.jl                 # 倾向得分匹配（最近邻 + 核匹配）
    doubly_robust.jl       # AIPW 双重稳健估计
    treatment_effects.jl   # ATE/ATT/ATU 汇总
    serialize.jl           # result_to_payload
  test/
    runtests.jl
```

### 2.2 类型体系

```julia
AbstractCausalModel <: AbstractEconModel        # 因果模型规格父类型
AbstractCausalFitResult <: AbstractFittedModel   # 因果拟合结果父类型
```

具体模型类型：`DIDModel`、`EventStudyModel`、`IPWModel`、`PSMModel`、`AIPWModel`

具体结果类型：`DIDFitResult`、`EventStudyFitResult`、`IPWFitResult`、`PSMFitResult`、`AIPWFitResult`

### 2.3 依赖

- `MetricaBase.jl`（协议层）
- `MetricaPanel.jl`（FE 估计器，Phase 1 升级后走 StatsModels）
- `MetricaDiscrete.jl`（Logit 用于倾向得分）
- `MetricaLinear.jl`（OLS 用于 AIPW 结果模型）
- `Distributions.jl`、`LinearAlgebra`、`Statistics`

## 3. 实施阶段

### Phase 1：Panel 公式解析器升级

**目标：** 统一全项目公式接口。

**改动范围：**
- `MetricaPanel.jl/src/MetricaPanel.jl`：`PanelModel` 类型不再存 `formula::String`，改用 StatsModels 公式对象
- `MetricaPanel.jl/src/fe.jl`、`re.jl`、`fd.jl`、`between.jl`、`cre.jl`：公式解析替换为 `MetricaLinear.parse_formula_term` + `collect_term_symbols` + `prepare_model_data`
- `MetricaPanel.jl/src/MetricaPanel.jl`：`_PANEL_ESTIMATORS` 已移到 include 之后（S4a E2E 修复中完成）
- 将 `PanelModel`、`PanelIVModel` 注册到 `MODEL_REGISTRY`（修复 M4）
- `scripts/julia_daemon.jl`：移除 `if model_type == "panel"` 硬编码分支，统一走 MODEL_REGISTRY dispatch
- 所有已有面板测试仍通过，不引入回归

### Phase 2：TWFE 双向固定效应吸收算法

**目标：** 自主实现双向 FE，不依赖 `FixedEffectModels.jl`。

**算法路径：** 交替投影法（Alternating Projections）
1. Entity-demean：对每个 id 减去组内均值
2. Time-demean：在实体去均值后的残差上，对每个时间点减去时间均值
3. 迭代至收敛（通常 2-3 轮），等价于完整双向 FE 系数
4. 自由度校正：`dof = N - K - (N_id - 1) - (N_time - 1)`

**接口：**
```julia
function fit_twfe(X, y, id_col, time_col; max_iter=10, tol=1e-8)
    # 返回 (coefficients, fitted, residuals, vcov, stderror, dof_corrected)
end
```

**单元测试：** 与 `FixedEffectModels.jl` 的 `reg(df, @formula(y ~ x + fe(id) + fe(time)))` 结果对比，系数差异 < 1e-6。

### Phase 3：DID + 事件研究

**DID 接口：**
```julia
fit(::Type{DIDModel}, formula::String, data;
    panel_id::Symbol, panel_time::Symbol,
    treated_column::Symbol,    # 处理组标识（0/1）
    post_column::Symbol,       # 处理期标识（0/1）
    vcov::Symbol=:cluster,     # 默认 cluster 在个体层面
)
```

**DID 内部流程：**
1. 用 StatsModels 解析 `y ~ treat * post + x1 + x2` → 自动展开交互项
2. 调 TWFE 吸收 id + time 固定效应
3. 组装结果：处理效应系数 = `treat:post` 交互项系数
4. 平行趋势警告（面板数据 ≥ 3 期时自动检测）：预处理期虚拟变量联合 F 检验

**事件研究接口：**
```julia
fit(::Type{EventStudyModel}, formula::String, data;
    panel_id::Symbol, panel_time::Symbol,
    treated_column::Symbol,
    event_time_column::Symbol,   # 事件发生时间
    pre_periods::Int=3,          # 事前窗口
    post_periods::Int=5,         # 事后窗口
)
```

内部展开为各期虚拟变量 × treated 交互项，联立估计。返回各期系数向量 + 置信带，供 `EventStudyPlot` 渲染。

### Phase 4：IPW + PSM + AIPW

**IPW：**
```julia
fit(::Type{IPWModel}, formula::String, data;
    treatment_column::Symbol,      # 处理变量
    outcome_column::Symbol,        # 结果变量
    propensity_formula::String,    # 倾向得分公式
)
```
流程：(1) Logit 估计倾向得分 → (2) 权重构造（处理组 = 1/p，对照组 = 1/(1-p)）→ (3) 加权均值差 = ATE。标准误用稳健 sandwich。

**PSM：**
```julia
fit(::Type{PSMModel}, formula::String, data;
    treatment_column::Symbol,
    outcome_column::Symbol,
    propensity_formula::String,
    method::Symbol=:nearest,       # :nearest 或 :kernel
    caliper::Float64=0.2,          # 卡尺（标准差的倍数）
    n_neighbors::Int=1,            # 最近邻数
)
```
匹配后 ATE = ATT = 匹配样本的均值差。平衡性检验：匹配前后各协变量的标准化偏差 + t 检验。

**AIPW：**
```julia
fit(::Type{AIPWModel}, formula::String, data;
    treatment_column::Symbol,
    outcome_column::Symbol,
    outcome_formula::String,       # 结果模型公式
    propensity_formula::String,    # 倾向得分公式
)
```
双保险：(1) OLS 拟合 E[Y|X] → (2) Logit 拟合 P(T|X) → (3) AIPW 公式组合。比纯 IPW 或纯回归更稳健。

### Phase 5：处理效应汇总

统一汇总 ATE/ATT/ATU，支持多方法对比。

```julia
struct TreatmentEffectSummary
    method::Symbol
    ate::Float64; ate_se::Float64
    att::Float64; att_se::Float64
    atu::Float64; atu_se::Float64
    nobs_treated::Int; nobs_control::Int
end
```

### Phase 6：Runtime + App 集成

**Runtime 层：**
- `MODEL_REGISTRY` 注册：`"did"`、`"event_study"`、`"ipw"`、`"psm"`、`"aipw"`
- Rust `model_required_fields()` 新增 causal model_type 校验字段
- Rust `ModelSpec` struct 新增 `treatment_column`

**App 层：**
- `ModelForm.tsx` 新增 causal 模型选项（OptGroup: 因果推断）
- `EventStudyPlot.tsx`（ECharts）：事件研究系数 + 置信带 + 事前/事后分隔线
- `DIDResultCards.tsx`：处理效应 + 平行趋势教学提示
- `BalanceTable.tsx`：PSM 匹配前后协变量平衡性
- `TreatmentEffectSummary.tsx`：ATE/ATT/ATU 卡片

## 4. 贯穿性约束

### 4.1 公式统一约束

自 S4b 起，**所有模型**（含已有 MetricaPanel 和未来 S4c/S4d/S5）的 `formula` 参数 MUST 通过 StatsModels 解析。不在 MetricaBase 协议层接受简版字符串分割。Panel 公式升级（Phase 1）是一次性迁移，后续新模型直接继承约束。

### 4.2 MODEL_REGISTRY 完整性

自 S4b 起，**所有模型类型** MUST 在 `__init__()` 中注册到 `MODEL_REGISTRY`，包括 Panel 模型（修复 M4）。daemon 不再硬编码任何 `model_type` 分支。

### 4.3 教学友好约束

- DID 必须输出平行趋势检验统计量和结构化 warning
- PSM 必须输出匹配前后平衡性检验（标准化偏差 + t 检验）
- 事件研究必须附带事前趋势 p 值 + "是否支持平行趋势假设"的明确判断
- 所有 warning 必须含教学性解释（不只是统计量数值）

## 5. 不在此文档范围

- 高级 DID（Callaway-Sant'Anna、Sun-Abraham、Bacon-Decomp）→ S5
- 合成控制法 → S5
- 断点回归（RDD）→ S5
- 工具变量以外的内生性处理方法 → S5

## 6. 验收标准

1. Phase 1 后：所有已有 Panel 测试通过，Panel 模型在 MODEL_REGISTRY 中可查找
2. Phase 2 后：TWFE 系数与 `FixedEffectModels.jl` 差异 < 1e-6
3. Phase 3 后：DID 处理效应估计与 Stata `reghdfe` 结果一致（教学口径）
4. Phase 4 后：PSM 匹配后标准化偏差 < 10%（模拟数据）
5. Phase 6 后：App 可通过模型类型选择器切换到 DID/PSM 等新模型，端到端运行成功
6. 不破坏已有 OLS / Panel / 离散模型回归测试
