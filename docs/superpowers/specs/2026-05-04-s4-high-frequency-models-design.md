# S4 高频应用研究模型：总体设计

> 状态：设计阶段。本文件定义 S4 四个子阶段的边界、内容与承上启下策略。

## 1. S4 总体目标

S4 覆盖教学和常见应用研究里最高频的模型族，使 Metrica 从"线性与面板工作台"扩展为"常见应用研究工作台"。

### 1.1 四个子阶段

| 子阶段 | 包名 | 核心内容 | 依赖 |
|--------|------|---------|------|
| S4a | `MetricaDiscrete.jl` | Logit / Probit / Poisson / 有序 Logit / 多项 Logit / 负二项 + 边际效应 + LR 检验 / AIC/BIC | OLS 底座（MetricaLinear） |
| S4b | `MetricaCausal.jl` | DID / 事件研究 / 双重稳健 + IPW / PSM / ATE/ATT/ATU | 面板底座（MetricaPanel）+ S4a Logit |
| S4c | `MetricaTimeSeries.jl` | ARIMA / VAR / 单位根 / 协整 / Granger 因果 / 脉冲响应 / 预测 | 无（全新域） |
| S4d | `MetricaSurvey.jl` | Survey OLS + Survey GLM + 设计效应 + Taylor 线性化方差 | S4a GLM |

四个子阶段严格顺序推进，每个独立完成 Core→Runtime→App 闭环。

### 1.2 明确排除

- 不以全量跨软件互验或命令覆盖率为目标
- 不提前展开高复杂专题（动态面板 GMM、SUR、空间、贝叶斯）
- 不让 App 退化为通用参数堆叠界面

## 2. S4a：GLM / 离散模型

### 2.1 Core — MetricaDiscrete.jl

**文件结构：**

```
MetricaDiscrete.jl/
  src/
    MetricaDiscrete.jl     # 模块入口、类型定义、MODEL_REGISTRY 注册
    irls.jl                # IRLS 通用求解器（收敛判定、链接函数族、分布族）
    logit.jl               # Logit 模型（二分类）
    probit.jl              # Probit 模型
    poisson.jl             # Poisson 回归（计数数据）
    ologit.jl              # 有序 Logit（比例几率）
    mlogit.jl              # 多项 Logit
    negbin.jl              # 负二项回归
    margins.jl             # 边际效应：AME、MEM（Delta 法标准误）
    model_selection.jl     # LR 检验、AIC/BIC 比较
    serialize.jl           # result_to_payload
```

**类型体系：**

- `AbstractDiscreteModel <: AbstractEconModel` — 所有离散模型的父类型
- `AbstractDiscreteFitResult <: AbstractFittedModel` — 所有离散拟合结果的父类型
- 具体模型类型：`LogitModel`、`ProbitModel`、`PoissonModel`、`OrderedLogitModel`、`MultinomialLogitModel`、`NegBinModel`

**依赖：** `MetricaBase.jl`、`MetricaLinear.jl`（复用公式解析、数据管道、序列化模板）、`Distributions.jl`。IRLS 手写，不依赖 GLM.jl。

**通用 IRLS 求解器：**

```julia
function irls(X, y, link, family; max_iter=25, tol=1e-8)
    # 1. 初始化（线性模型系数作为初值）
    # 2. 每轮迭代：计算 η = Xβ → μ = linkinv(η) → z = η + (y-μ)*dη/dμ → W = diag(...) → β_new = (X'WX)⁻¹X'Wz
    # 3. 收敛判定：‖β_new - β‖ / ‖β‖ < tol
    # 4. 末轮 Hessian = X'WX，VCov = Hessian⁻¹ * dispersion
end
```

**各模型链接函数与分布族：**

| 模型 | 链接函数 | 分布 | 特殊输出 |
|------|---------|------|---------|
| Logit | logit | Binomial | OddsRatio |
| Probit | probit | Binomial | — |
| Poisson | log | Poisson | — |
| 有序 Logit | logit（累计概率） | Multinomial(ordered) | 阈值 τ |
| 多项 Logit | log（类别对基准） | Multinomial | 类别对比 |
| 负二项 | log | NegBinomial(θ) | 过度分散参数 α |

### 2.2 Runtime 层

**贯穿性基础设施改造（S4a 内完成）：**

在 `MetricaBase.jl` 建立模型注册表，替代 daemon 中的 if-else 链：

```julia
const MODEL_REGISTRY = Dict{String, Type}(
    "ols" => OLSModel, "iv" => IVModel, "gls" => GLSModel,
    "panel" => PanelModel,
    "logit" => LogitModel, "probit" => ProbitModel,
    "poisson" => PoissonModel,
)
```

daemon dispatch 统一为：

```julia
model_type = params["model_type"]
ModelT = MODEL_REGISTRY[model_type]
result = fit(ModelT, formula, data; kwargs...)
payload = result_to_payload(result)
```

Rust 端 `validate_model_request()` 改为读取每个 model_type 的 required_fields 映射表，不再硬编码 model_type 列表。端点不变（`POST /fit_model`）。

### 2.3 App 层

**现有组件改动：**

- `ModelForm.tsx`：新增 logit / probit / poisson 选项，表单字段与 OLS 一致。声明式映射替代 if-else 链。
- `ModelTypeSelector.tsx`：分组显示（线性模型 / 面板模型 / 离散模型）

**新增组件：**

| 组件 | 说明 |
|------|------|
| `DiscreteGlanceCards` | Pseudo-R²（McFadden）、Log-Likelihood、AIC/BIC |
| `OddsRatioTable` | Logit/Probit 的 OR + 置信区间（可切换系数/OR 视图） |
| `MarginalEffectsTable` | AME 表（Delta 法标准误），支持连续/分类变量的边际效应 |
| `ClassificationPreview` | 混淆矩阵 + 准确率/精确率/召回率（augment 数据驱动预测概率） |
| `ModelSelectionPanel` | LR 检验嵌套模型比较 + AIC/BIC 排行 |

## 3. S4b：因果推断

### 3.1 Core — MetricaCausal.jl

**文件结构：**

```
MetricaCausal.jl/
  src/
    MetricaCausal.jl       # 模块入口、类型定义
    did.jl                 # 经典 2x2 DID + 多期 DID（双向固定效应）
    event_study.jl         # 事件研究（含事前趋势检验）
    doubly_robust.jl       # 双重稳健估计（AIPW）
    ipw.jl                 # 逆概率加权
    psm.jl                 # 倾向得分匹配（最近邻 + 核匹配）
    treatment_effects.jl   # ATE/ATT/ATU 汇总
    serialize.jl           # result_to_payload
```

**类型体系：**

- `AbstractCausalModel <: AbstractEconModel`
- `AbstractCausalFitResult <: AbstractFittedModel`

**关键技术路径：**

- DID/事件研究：复用 `MetricaPanel.jl` 的 FE 估计器做双向固定效应。事件研究 = DID 的交互项展开为各期虚拟变量 × 处理组。
- IPW/PSM：倾向得分用 S4a 的 Logit 拟合。PSM 匹配用最近邻（1:N、卡尺）和核匹配。
- 双重稳健（AIPW）：结果模型（OLS）+ 倾向得分模型（Logit）双保险。
- 标准误：DID 默认 cluster 在个体层面；PSM 用 Abadie-Imbens SE 或 bootstrap。

**依赖：** `MetricaBase.jl`、`MetricaPanel.jl`（FE）、`MetricaDiscrete.jl`（Logit）、`MetricaLinear.jl`（OLS）。

### 3.2 Runtime 层

注册表新增 `"did"`、`"event_study"`、`"ipw"`、`"psm"`。DID 和事件研究需校验 `panel_id`、`panel_time`。IPW/PSM 需校验 `treatment_column`。

### 3.3 App 层

| 组件 | 说明 |
|------|------|
| `DIDResultCards` | 处理效应 + 平行趋势假设教学提示 |
| `EventStudyPlot` | ECharts 事件研究图（系数 + 置信带 + 事前事后分隔线） |
| `BalanceTable` | PSM 匹配前后协变量平衡性检验（标准化偏差 + t 检验） |
| `TreatmentEffectSummary` | ATE/ATT/ATU 汇总卡片 + 方法对比 |

## 4. S4c：时间序列

### 4.1 Core — MetricaTimeSeries.jl

**文件结构：**

```
MetricaTimeSeries.jl/
  src/
    MetricaTimeSeries.jl   # 模块入口、类型定义、时间索引工具
    arima.jl               # ARMA/ARIMA（含 auto_arima 信息准则定阶）
    var.jl                 # VAR + Granger 因果 + 脉冲响应 + 方差分解
    unitroot.jl            # ADF + Phillips-Perron + KPSS
    cointegration.jl       # Engle-Granger + Johansen
    forecast.jl            # 一步/多步预测 + 预测区间
    serialize.jl
```

**类型体系：**

- `AbstractTimeSeriesModel <: AbstractEconModel`
- `AbstractTSFitResult <: AbstractFittedModel`

**关键技术路径：**

- ARIMA：MLE via Kalman 滤波 或 CSS（条件平方和）。`auto_arima` 用网格搜索 + AICc 选阶。
- VAR：方程-方程 OLS 估计；Granger 因果用 F 检验；脉冲响应用 Cholesky 分解；方差分解。
- 单位根：ADF（带滞后选择）、PP（非参数修正）、KPSS（趋势平稳 vs 差分平稳互补）。
- 协整：Engle-Granger 两步法（残差 ADF）为核心；Johansen 作为扩展。

**数据要求：** 时序数据需指定 `time_column`，自动排序和构造滞后。不引入完整 StatsModels 公式——时序公式以变量列表 + 滞后阶数为主。

**依赖：** `MetricaBase.jl`、`LinearAlgebra`、`Distributions.jl`。

### 4.2 Runtime 层

注册表新增 `"arima"`、`"var"`、`"unitroot"`、`"cointegration"`。需校验 `time_column`、滞后/差分阶数字段。

### 4.3 App 层

| 组件 | 说明 |
|------|------|
| `TimeSeriesForm` | 时间列选择 + 滞后阶数 + 差分阶数 + 预测步数 |
| `ForecastChart` | ECharts 历史数据 + 预测值 + 置信带（半透明填充） |
| `UnitRootTable` | ADF/PP/KPSS 三种检验结果并行展示 |
| `ImpulseResponseChart` | 脉冲响应图矩阵（ECharts 多子图） |
| `ACFPACFChart` | 自相关/偏自相关图（ECharts bar） |

## 5. S4d：复杂抽样

### 5.1 Core — MetricaSurvey.jl

**文件结构：**

```
MetricaSurvey.jl/
  src/
    MetricaSurvey.jl       # 模块入口、类型定义、设计效应
    survey_design.jl       # 抽样设计对象：pweights、strata、PSU、FPC
    survey_ols.jl          # Survey OLS + Taylor 线性化方差
    survey_glm.jl          # Survey Logit/Probit/Poisson
    deff.jl                # 设计效应 DEFF + 有效样本量
    serialize.jl
```

**类型体系：**

```julia
struct SurveyDesign
    data
    weights::Vector{Float64}        # 抽样权重
    strata::Union{Vector{Int}, Nothing}   # 分层标识
    psu::Union{Vector{Int}, Nothing}      # 初级抽样单元
    fpc::Union{Vector{Float64}, Nothing}  # 有限总体校正因子
end

AbstractSurveyModel <: AbstractEconModel
AbstractSurveyFitResult <: AbstractFittedModel
```

**关键技术路径：**

- **SurveyDesign** 是非模型对象——是数据 + 设计元信息的包装。
- Survey OLS：内部调用 `MetricaLinear.fit(OLSModel, ...)` 获取点估计，然后替换协方差矩阵为 Taylor 线性化方差（`sandwich` 形式）。
- Survey GLM：内部调用 `MetricaDiscrete.jl` 的各 GLM 模型，同样替换协方差。
- DEFF = survey_var / srs_var，衡量设计效应。有效样本量 = n / DEFF。
- 分层：层内独立方差求和。PSU：cluster 级别得分贡献求和。FPC：(1 - n/N) 校正。

**依赖：** `MetricaBase.jl`、`MetricaLinear.jl`（OLS）、`MetricaDiscrete.jl`（GLM）。

### 5.2 Runtime 层

注册表新增 `"survey_ols"`、`"survey_logit"`、`"survey_probit"`、`"survey_poisson"`。需校验 `weights_column`、可选 `strata_column`、`psu_column`。

### 5.3 App 层

| 组件 | 说明 |
|------|------|
| `SurveyDesignPanel` | 抽样设计配置：权重列、分层列、PSU 列 + FPC |
| `DEFFSummary` | 设计效应 + 有效样本量表（每个系数一行） |
| `StrataSummary` | 各层样本量分布 + 权重分布摘要 |

## 6. 贯穿性基础设施改造（S4a 内完成）

以下改造在 S4a 子阶段一次性完成，后续 S4b-d 零成本继承：

| 改造项 | 所在层 | 说明 |
|--------|--------|------|
| MODEL_REGISTRY | Core (MetricaBase) | `Dict{String, Type}` 替代 daemon if-else |
| daemon 统一 dispatch | Runtime (Julia) | `fit(MODEL_REGISTRY[type], ...)` |
| schema 驱动校验 | Runtime (Rust) | `model_type → required_fields` 映射表 |
| 声明式 ModelForm | App (TS) | `model_type → form_fields` 映射，替代 if-else 链 |
| MODEL_TYPE_LABELS | App (TS) | `Record<string, {label, family, icon}>` 统一维护 |

## 7. 承上启下策略

### 7.1 S4a → S4b

S4a 产出的 Logit 作为 S4b IPW/PSM 的倾向得分模型。S4a 的 MODEL_REGISTRY 和声明式表单被 S4b 直接复用。

### 7.2 S4b → S4c

无直接代码依赖。但 S4b 的事件研究图（`EventStudyPlot`）和 S4c 的预测图（`ForecastChart`）共享 ECharts 时序图渲染模式，可抽取公共 `TimeSeriesChart` 基组件。

### 7.3 S4c → S4d

无直接代码依赖。S4c 的时间列处理经验可参考但不强制引入 S4d。

### 7.4 S4a → S4d

S4a 的 Logit/Probit/Poisson 被 Survey GLM 内部调用。边际效应框架的 Delta 法协方差计算可适配 Taylor 线性化。

### 7.5 S4 整体 → S5

S4 完成后，MODEL_REGISTRY 已有 15+ 模型，daemon dispatch 完全通用化。S5 新增任何高级模型（GMM、分位数回归、非线性等）只需：(1) 新包实现 `fit()` 和协议方法，(2) 注册表加一行，(3) App 加表单映射和结果组件。

## 8. 阶段验收标准

每个子阶段必须满足：

1. 每个模型族至少有一个教学数据集和一个端到端工作流示例
2. 输出系统能与 S1-S3 的结果对象并列工作
3. 结构化 warning 能覆盖该阶段模型族的常见误用
4. glance / tidy / augment 协议语义不退化
5. 已有模型（OLS / IV / GLS / Panel）的回归测试不破坏
6. `MetricaDiscrete.jl` 是 S4 首个落地包，必须在自身测试通过后再开始 S4b Core 实现

## 9. 不在此文档范围

- 具体 IRIS 算法细节 → 各子阶段的实现 spec
- 教学数据集来源与内容 → 各子阶段数据准备任务
- ECharts 图表的具体配置 → App 实现 spec
- 具体测试用例 → 各子阶段测试计划
