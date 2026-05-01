# 里程碑 3 实施计划：面板基础

> **状态：已完成。** 本计划定义里程碑 3（面板基础）的详细实施步骤。所有任务已完成。

> **给代理式执行者：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务推进。步骤使用 checkbox（`- [ ]`）语法跟踪。

**目标：** 实现面板数据基础能力，包括 PanelData 类型、FE/RE/FD/Between 估计器、基础面板诊断、Grunfeld 教学数据集。

**架构：** 按照总体蓝图的阶段 2E 规划，创建 `MetricaPanel.jl` 包，复用 `MetricaBase.jl` 的协议内核，实现面板模型的 `glance` / `tidy` / `augment` 结构化输出。

**技术栈：** Julia, DataFrames.jl, StatsModels.jl, LinearAlgebra, Statistics, Distributions.jl

---

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 是否依赖 FixedEffectModels.jl | 先自行实现，后续可选择性引入 | 保持灵活性，避免过早绑定外部依赖 |
| 面板数据集选择 | Grunfeld（经典投资数据集） | 经典教科书示例，20 家公司 × 20 年 |
| 实施顺序 | 端到端垂直切片 | 快速验证，先实现 FE 贯通全链路，再扩展其他方法 |
| 公式系统扩展 | 最小扩展，先不支持 `fe()` 语法 | 简化实现，避免过早引入复杂 DSL |
| 面板方法优先级 | FE > RE > FD > Between | FE 最常用，教学价值最高 |

---

## 阶段 1：MetricaBase.jl 面板类型定义

**文件：**

- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl`
- Modify: `packages/MetricaBase.jl/test/runtests.jl`

- [ ] **步骤 1.1：定义 `AbstractPanelModel` 抽象类型**

在 `MetricaBase.jl` 中新增 `AbstractPanelModel <: AbstractEconModel`，用于面板模型的类型分派。

- [ ] **步骤 1.2：定义 `PanelData` 数据容器**

定义 `PanelData` 结构体，包含：
- `data` — 实际数据（DataFrame 或 Tables.jl 兼容容器）
- `id_col` — 个体标识列名
- `time_col` — 时间标识列名

- [ ] **步骤 1.3：定义面板相关 `ModelWarning` 码**

新增面板相关的警告码：
- `:panel_unbalanced` — 不平衡面板警告
- `:panel_single_obs` — 单个个体仅有单期观测
- `:panel_summary` — 面板结构摘要（个体数、时期数）

- [ ] **步骤 1.4：更新 MetricaBase 测试**

验证新定义的类型和警告码。

- [ ] **步骤 1.5：运行 MetricaBase 测试**

```bash
julia --project=/Users/skahanium/Metrica/packages/MetricaBase.jl -e "using Pkg; Pkg.test()"
```

预期：全部通过。

---

## 阶段 2：创建 MetricaPanel.jl 包骨架

**文件：**

- Create: `packages/MetricaPanel.jl/Project.toml`
- Create: `packages/MetricaPanel.jl/src/MetricaPanel.jl`
- Create: `packages/MetricaPanel.jl/test/runtests.jl`

- [ ] **步骤 2.1：创建包目录结构**

```
packages/MetricaPanel.jl/
├── Project.toml
├── src/
│   ├── MetricaPanel.jl
│   ├── types.jl
│   ├── fe.jl
│   ├── re.jl
│   ├── fd.jl
│   ├── between.jl
│   └── serialize.jl
└── test/
    └── runtests.jl
```

- [ ] **步骤 2.2：定义 `Project.toml`**

依赖：MetricaBase, DataFrames, StatsModels, LinearAlgebra, Statistics, Distributions

- [ ] **步骤 2.3：定义 `PanelModel` 规格对象**

```julia
struct PanelModel <: MetricaBase.AbstractPanelModel
    formula::String
    id_col::Symbol
    time_col::Symbol
    method::Symbol  # :fe, :re, :fd, :between
end
```

- [ ] **步骤 2.4：定义 `PanelFitResult` 结构化结果**

```julia
struct PanelFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    panel_data::PanelData
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    coefficient_names::Vector{Symbol}
    method::Symbol
end
```

- [ ] **步骤 2.5：实现 `glance` / `tidy` / `augment` 方法**

为 `PanelFitResult` 实现 MetricaBase 的接口方法。

---

## 阶段 3：实现 FE 固定效应估计器

**文件：**

- Create: `packages/MetricaPanel.jl/src/fe.jl`
- Modify: `packages/MetricaPanel.jl/src/MetricaPanel.jl`
- Modify: `packages/MetricaPanel.jl/test/runtests.jl`

- [ ] **步骤 3.1：实现组内去均值算法（Within Transformation）**

核心算法：
1. 按个体分组
2. 计算每个变量的组内均值
3. 用原始值减去组内均值
4. 对去均值后的数据执行 OLS

- [ ] **步骤 3.2：实现 `fit_fe` 函数**

```julia
function fit_fe(panel_data::PanelData, formula::String)
    # 1. 解析公式
    # 2. 提取变量
    # 3. 组内去均值
    # 4. OLS 拟合
    # 5. 计算统计量
    # 6. 返回 PanelFitResult
end
```

- [ ] **步骤 3.3：实现 FE 的 `glance` 方法**

返回面板模型摘要：
- 模型类型（FE）
- 样本量
- 个体数
- 时期数
- R²
- 调整 R²

- [ ] **步骤 3.4：实现 FE 的 `tidy` 方法**

返回系数表：
- 系数估计值
- 标准误
- t 统计量
- p 值

- [ ] **步骤 3.5：实现 FE 的 `augment` 方法**

返回逐观测增强数据：
- 拟合值
- 残差
- 标准化残差

- [ ] **步骤 3.6：编写 FE 测试**

覆盖场景：
- 平衡面板
- 不平衡面板
- 单个个体
- 单个时期
- 缺失值处理

- [ ] **步骤 3.7：运行 MetricaPanel 测试**

```bash
julia --project=/Users/skahanium/Metrica/packages/MetricaPanel.jl -e "using Pkg; Pkg.test()"
```

预期：全部通过。

---

## 阶段 4：创建 Grunfeld 数据集

**文件：**

- Create: `datasets/teaching/grunfeld.csv`
- Create: `datasets/teaching/grunfeld_meta.json`

- [ ] **步骤 4.1：创建 Grunfeld CSV 数据集**

经典 Grunfeld 投资数据集：
- 20 家公司 × 20 年（1935-1954）
- 变量：company, year, invest, mvalue, capital
- 来源：Wooldridge 教科书

- [ ] **步骤 4.2：创建数据集元数据**

JSON 格式，包含：
- 数据说明
- 变量标签
- 来源
- 推荐教程

---

## 阶段 5：贯通 Runtime/App

**文件：**

- Modify: `scripts/julia_bridge_entry.jl`
- Modify: `runtime/metrica-runtime/src/lib.rs`
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`
- Modify: `apps/metrica-desktop/src/runtime-client.js`
- Modify: `apps/metrica-desktop/src/result-view.js`
- Modify: `apps/metrica-desktop/tests/result-view.test.js`

- [ ] **步骤 5.1：更新 Julia 桥接脚本**

在 `julia_bridge_entry.jl` 中新增面板拟合入口：
- 读取 `model_spec.model_type`
- 当 `model_type = "panel"` 时，调用 `fit_panel`
- 传递 `panel_id`、`panel_time`、`panel_method`

- [ ] **步骤 5.2：更新 Runtime 请求结构**

在 `lib.rs` 中新增：
- `panel_id` 字段
- `panel_time` 字段
- `panel_method` 字段

- [ ] **步骤 5.3：编写 Runtime 集成测试**

新增面板拟合测试，验证：
- 面板请求成功序列化
- Julia 子进程成功返回结构化面板结果
- 面板结果包含 glance / tidy / augment

- [ ] **步骤 5.4：更新 App 请求构造**

在 `runtime-client.js` 中新增：
- 面板模型选择
- 面板索引配置
- 面板方法选择

- [ ] **步骤 5.5：更新 App 结果渲染**

在 `result-view.js` 中新增：
- 面板摘要卡片
- 面板系数表
- 面板 augment 预览

- [ ] **步骤 5.6：编写 App 前端测试**

覆盖场景：
- 面板请求构造
- 面板结果渲染

- [ ] **步骤 5.7：运行完整验证矩阵**

```bash
cargo test
npm test
julia --project=/Users/skahanium/Metrica/packages/MetricaPanel.jl -e "using Pkg; Pkg.test()"
```

预期：全部通过。

---

## 阶段 6：扩展 RE/FD/Between

**文件：**

- Create: `packages/MetricaPanel.jl/src/re.jl`
- Create: `packages/MetricaPanel.jl/src/fd.jl`
- Create: `packages/MetricaPanel.jl/src/between.jl`
- Modify: `packages/MetricaPanel.jl/test/runtests.jl`

- [ ] **步骤 6.1：实现 RE（随机效应）估计器**

Mundlak 方法：
1. 计算组均值
2. 将组均值作为额外回归元
3. 执行 OLS
4. 使用 GLS 修正标准误

- [ ] **步骤 6.2：实现 FD（一阶差分）估计器**

核心算法：
1. 按个体分组
2. 计算相邻期差值
3. 对差值数据执行 OLS
4. 修正自由度

- [ ] **步骤 6.3：实现 Between（组间估计）估计器**

核心算法：
1. 按个体分组
2. 计算组均值
3. 对组均值数据执行 OLS
4. 修正标准误

- [ ] **步骤 6.4：扩展测试**

为 RE/FD/Between 编写测试，覆盖：
- 平衡面板
- 不平衡面板
- 边界情况

- [ ] **步骤 6.5：运行完整测试**

```bash
julia --project=/Users/skahanium/Metrica/packages/MetricaPanel.jl -e "using Pkg; Pkg.test()"
```

预期：全部通过。

---

## 阶段 7：更新文档

**文件：**

- Modify: `docs/superpowers/specs/2026-04-30-metrica-main-design.md`
- Modify: `docs/architecture/runtime-protocol.md`
- Modify: `Metrica.jl-计量经济学框架-完善版.md`

- [ ] **步骤 7.1：更新主设计文档**

补充里程碑 3 完成状态：
- 面板基础能力已实现
- FE/RE/FD/Between 已贯通
- Grunfeld 数据集已创建

- [ ] **步骤 7.2：更新 Runtime 协议文档**

补充面板模型的请求/响应格式。

- [ ] **步骤 7.3：更新总体蓝图**

更新里程碑 3 状态为已完成。

---

## 验收标准

里程碑 3 完成的验收条件：

1. `MetricaBase.jl` 包含 `AbstractPanelModel`、`PanelData` 类型
2. `MetricaPanel.jl` 包实现 FE/RE/FD/Between 四种估计器
3. 每种估计器都有 `glance` / `tidy` / `augment` 结构化输出
4. Grunfeld 数据集可端到端验证 FE 拟合
5. Runtime 支持 `model_type = "panel"` 请求
6. App 可渲染面板模型结果
7. 所有测试通过（Julia + Runtime + App）
8. 文档已更新

---

## 后续里程碑铺垫

里程碑 3 完成后，为后续里程碑保留的铺垫：

1. **公式系统扩展**：`fe()` 语法（v1.2 面板扩展）
2. **面板诊断**：Hausman 检验、F 检验、LM 检验
3. **动态面板**：GMM（不建议过早进入首批交付）
4. **教学数据集**：更多面板数据集（NLSY、Penn World Table）
