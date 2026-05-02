# 里程碑 6：线性模型成熟化

状态：规划中
日期：2026-05-03

> 收口约束：M6 完成前，不开启 M7（面板成熟化）或更高里程碑。统一 `fit` 接口需向后兼容——现有 `fit_ols_file` 在 M6 内标记为 deprecated wrapper，不立即删除。公式预处理不得破坏现有 `@formula` 宏的直接使用方式。

## 背景

M5 完成了地基升级（React 19 前端 + MetricaData.jl 数据管理 + Runtime `/transform` 端点），但 MetricaLinear.jl 的模型能力仍停留在教学口径的 OLS/WLS。M6 的目标是将线性模型族从"教学可用"升级为"研究可用"，补全 IV/2SLS、GLS、统一 fit 接口、predict 能力和协议方法。

## 产品定位

M6 使 Metrica 能覆盖计量经济学课程中线性模型族的核心内容：OLS、WLS、IV/2SLS、GLS。学生和研究者可以通过统一的 `fit` 接口拟合模型，通过 `glance/tidy/augment/coef/vcov/predict` 消费结构化结果，并在桌面应用中配置和比较不同模型。

## 架构决策

### 决策 1：统一 fit 接口

当前 `fit_ols_file(csv_path, formula; weights, vcov, cluster)` 是专用入口。目标模式：

```julia
fit(::Type{OLSModel}, formula, data; vcov, weights, cluster_column)
fit(::Type{IVModel}, formula, data; instruments, endog, vcov, cluster_column)
fit(::Type{GLSModel}, formula, data; omega_fn, vcov)
```

- `data` 接受 DataFrame 或 CSV 路径（内部 dispatch）
- `fit_ols_file` 保留为 deprecated wrapper
- 返回统一的 `AbstractFittedModel` 子类型

### 决策 2：抽象类型层级

```
AbstractEconModel
├── AbstractLinearModel <: AbstractEconModel    ← M6 新增
│   ├── OLSModel                                ← 改为继承 AbstractLinearModel
│   ├── IVModel                                 ← M6 新增
│   └── GLSModel                                ← M6 新增
├── AbstractPanelModel <: AbstractEconModel
└── ...

AbstractFittedModel
├── AbstractLinearFitResult <: AbstractFittedModel  ← M6 新增
│   ├── OLSFitResult                                ← 改为继承 AbstractLinearFitResult
│   ├── IVFitResult                                 ← M6 新增
│   └── GLSFitResult                                ← M6 新增
└── PanelFitResult
```

### 决策 3：公式预处理策略

IV/2SLS 的公式处理流程：

1. 用户调用 `fit(IVModel, "y ~ x1 + x2", data; instruments=["z1","z2"], endog=["x2"])`
2. 入口处拆分公式：外生变量、内生变量
3. 第一阶段：对每个内生变量，OLS 回归到外生变量 + 工具变量，得到拟合值
4. 第二阶段：用拟合值替换内生变量，执行 OLS

不修改 StatsModels.jl 的 `@formula` 解析，在 `fit(IVModel, ...)` 入口处做字符串拆分和路由。

### 决策 4：GLS 协方差函数接口

```julia
function my_omega(residuals::AbstractVector)
    # 返回 n×n 协方差矩阵 Ω
    return Omega
end

fit(GLSModel, formula, data; omega_fn=my_omega)
```

- `omega_fn` 接受残差向量，返回 Ω 矩阵
- 内部计算 Ω^(-1/2)（Cholesky 分解）做变换后执行 GLS
- 初始残差来自 OLS

### 决策 5：predict 点预测 + 预测区间

```julia
predict(fit_result; newdata, interval=:confidence, level=0.95)
# 返回 (predictions, lower, upper)
```

- 点预测：X_new * beta
- 置信区间：基于 t 分布和标准误
- 预测区间：包含残差方差 sigma^2

### 决策 6：IV 识别策略

通过 `instruments` 和 `endog` 参数显式指定，不在公式内使用 `endog()` 语法糖。公式仍使用标准 `y ~ x1 + x2` 格式。

## Part 1：协议层补全

### 目标

在 MetricaBase.jl 中补全抽象类型和 API 桩，在 MetricaLinear.jl 中为 OLS 实现所有协议方法，建立统一的 `fit` 泛型入口。

### MetricaBase.jl 变更

| 新增内容 | 说明 |
|---------|------|
| `AbstractLinearModel <: AbstractEconModel` | 线性模型族公共抽象 |
| `AbstractLinearFitResult <: AbstractFittedModel` | 线性拟合结果公共抽象 |
| `stderror(fit)` 函数桩 | 标准误 |
| `confint(fit; level)` 函数桩 | 置信区间 |
| `nobs(fit)` 函数桩 | 观测数 |
| `dof(fit)` 函数桩 | 自由度 |
| `r2(fit)` 函数桩 | R² |
| `fitted(fit)` 函数桩 | 拟合值 |
| `residuals(fit)` 函数桩 | 残差 |
| `predict(fit; newdata, interval, level)` 函数桩 | 预测 |

### MetricaLinear.jl OLS 变更

- `OLSModel` 改为继承 `AbstractLinearModel`
- `OLSFitResult` 改为继承 `AbstractLinearFitResult`
- 新增 `vcov_matrix::Matrix{Float64}` 字段到 `OLSFitResult`
- 新增 `stderror_values::Vector{Float64}` 字段到 `OLSFitResult`
- 为 `OLSFitResult` 实现所有协议方法
- 新增 `fit(OLSModel, formula, data; kwargs...)` 泛型入口
- `fit_ols_file` 标记为 deprecated

### 验收标准

- `fit(OLSModel, "y ~ x1 + x2", csv_path)` 返回有效 `OLSFitResult`
- `coef/vcov/predict/nobs/dof/r2/fitted/residuals/stderror/confint` 均返回正确值
- `fit_ols_file` 仍可用但打印 deprecation 警告
- 所有现有测试不受影响

## Part 2：IV/2SLS

### 目标

实现工具变量/两阶段最小二乘估计，支持弱工具变量诊断。

### 新增类型

```julia
struct IVModel <: AbstractLinearModel
    formula::String
    instruments::Vector{String}
    endog::Vector{String}
end

struct IVFitResult <: AbstractLinearFitResult
    formula::String
    glance_table::ModelGlance
    tidy_table::TidyTable
    coef_names::Vector{Symbol}
    coef_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    first_stage_stats::Dict{String, Float64}  # 每个内生变量的 F 统计量
    weak_instrument_warnings::Vector{ModelWarning}
end
```

### 估计流程

1. 解析公式，分离外生变量、内生变量、因变量
2. 第一阶段：对每个内生变量，OLS 回归到所有外生变量 + 工具变量
3. 弱工具变量诊断：检查第一阶段 F 统计量（Staiger-Stock F < 10 警告）
4. 第二阶段：用拟合值替换内生变量，执行 OLS
5. 协方差修正：复用 `compute_vcov` 逻辑
6. 组装结构化结果

### fit 入口

```julia
fit(::Type{IVModel}, formula::String, data;
    instruments::Vector{String}, endog::Vector{String},
    vcov::Symbol=:classical, cluster_column::Union{Nothing,String}=nothing)
```

### 验收标准

- `fit(IVModel, "y ~ x1 + x2", data; instruments=["z1","z2"], endog=["x2"])` 返回有效 `IVFitResult`
- 第一阶段 F 统计量正确计算
- 弱工具变量（F < 10）触发 `ModelWarning`
- `glance/tidy/augment/coef/vcov/predict` 均可用
- 协方差类型支持 classical / HC1 / cluster

## Part 3：GLS

### 目标

实现已知协方差结构的 GLS 估计。

### 新增类型

```julia
struct GLSModel <: AbstractLinearModel
    formula::String
    omega_fn::Function
end

struct GLSFitResult <: AbstractLinearFitResult
    formula::String
    glance_table::ModelGlance
    tidy_table::TidyTable
    coef_names::Vector{Symbol}
    coef_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    design_matrix::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    omega::Matrix{Float64}
end
```

### 估计流程

1. 先用 OLS 拟合，得到初始残差
2. 调用 `omega_fn(residuals)` 得到 Ω 矩阵
3. Cholesky 分解 Ω = LL'，计算 Ω^(-1/2) = L'^(-1)
4. 变换：y* = Ω^(-1/2) y，X* = Ω^(-1/2) X
5. 对变换后数据执行 OLS
6. 组装结构化结果

### fit 入口

```julia
fit(::Type{GLSModel}, formula::String, data; omega_fn::Function, vcov::Symbol=:classical)
```

### 验收标准

- `fit(GLSModel, "y ~ x1", data; omega_fn=my_fn)` 返回有效 `GLSFitResult`
- Ω=I 时 GLS 退化为 OLS（系数和标准误一致）
- `glance/tidy/augment/coef/vcov/predict` 均可用
- 传入无效 Ω（非正定）时返回 `ModelError`

## Part 4：Runtime/App 贯通

### Runtime (Rust) 变更

`ModelSpec` 扩展：

```rust
struct ModelSpec {
    model_type: String,                    // "ols" | "iv" | "gls" | "panel"
    formula: String,
    // 现有字段...
    #[serde(skip_serializing_if = "Option::is_none")]
    instruments: Option<Vec<String>>,      // IV 工具变量
    #[serde(skip_serializing_if = "Option::is_none")]
    endog_columns: Option<Vec<String>>,    // IV 内生变量
    #[serde(skip_serializing_if = "Option::is_none")]
    omega_spec: Option<String>,            // GLS 协方差说明（M6 内仅做透传）
}
```

- `validate_fit_model_request` 扩展支持 `"iv"` 和 `"gls"`
- `handle_model_request` 中透传新字段到 Julia 参数

### Julia 守护进程变更

`julia_daemon.jl` 新增 `"iv"` 和 `"gls"` 分支：

- `"iv"`：解析 `instruments`、`endog_columns` 参数，调用 `fit(IVModel, ...)`
- `"gls"`：解析 `omega_fn` 参数（M6 内使用预定义的协方差函数），调用 `fit(GLSModel, ...)`

### App (React/TS) 变更

- `protocol.ts`：`ModelSpec.model_type` 扩展为 `'ols' | 'iv' | 'gls' | 'panel'`；新增 `instruments`、`endog_columns` 字段
- `modelStore.ts`：新增 `instruments`、`endogColumns` 状态字段和 setter
- `ModelForm.tsx`：新增 IV 选项（显示 instruments/endog 输入字段）和 GLS 选项
- `runtimeClient.ts`：`FitModelParams` 扩展 IV/GLS 字段
- 结果渲染复用现有 `GlanceTable` / `TidyTable` 组件

### 验收标准

- App 模型类型下拉框包含 OLS / IV / GLS / Panel 四个选项
- 选择 IV 后显示 instruments 和 endog 输入字段
- 端到端：App 发送 IV 请求 → Runtime 路由 → Julia 拟合 → 结果返回 → App 渲染
- 端到端：App 发送 GLS 请求 → 同上

## Part 5：黄金样例测试与模型比较载荷

### 黄金样例测试

| 测试集 | 数据来源 | 验证内容 |
|--------|---------|---------|
| OLS 黄金样例 | Stata `auto` 数据集 | 系数、标准误、R² 与 Stata 对齐 |
| IV/2SLS 黄金样例 | 经典 IV 教学数据 | 与 Stata `ivregress 2sls` 结果对齐 |
| GLS 黄金样例 | 已知 Ω 的模拟数据 | 与手算结果对齐 |
| predict 测试 | 各模型 | 点预测值 + 预测区间覆盖率 |

### 模型比较载荷

扩展 `result_to_payload` 输出，增加：

- AIC / BIC（OLS 和 GLS 有似然函数时）
- 对数似然值
- 模型类型标签

## 非目标

| 排除项 | 理由 |
|--------|------|
| FGLS（可行广义最小二乘） | 已确认延后，M6 仅做已知 Ω 的 GLS |
| 面板 IV / 面板 GLS | 属于 M7 范围 |
| 多模型并列比较 UI | App 层仅扩展枚举，比较 UI 延后到 M8 |
| Logit / Probit / Poisson | 属于 M10 范围 |
| 时间序列模型 | 属于 M12 范围 |
| `endog()` 公式语法糖 | M6 通过参数显式指定，语法糖作为未来扩展 |
| 公式扩展框架（自定义 term 注册） | 过大，M6 仅做字符串预处理 |
| 删除 `fit_ols_file` | M6 内仅标记 deprecated |

## 验证策略

| Part | 验证方式 |
|------|---------|
| Part 1 | 为 OLS 运行所有新协议方法，与已知值对比；验证 fit(OLSModel,...) 与 fit_ols_file 结果一致 |
| Part 2 | 与 Stata ivregress 2sls 黄金样例对齐；弱工具变量警告触发测试 |
| Part 3 | 已知 Ω 模拟数据与手算对齐；Ω=I 时退化为 OLS |
| Part 4 | 端到端：App → Runtime → Julia → 结果返回 → App 渲染 |
| Part 5 | Stata 对齐测试 + predict 区间覆盖率检验 |

端到端验收标准：

1. `fit(IVModel, "y ~ x1 + x2", df; instruments=["z1","z2"], endog=["x2"])` 返回有效 `IVFitResult`
2. `fit(GLSModel, "y ~ x1", df; omega_fn=my_fn)` 返回有效 `GLSFitResult`
3. `predict(result; interval=:confidence, level=0.95)` 返回点预测 + 上下界
4. App 模型类型下拉框包含 OLS / IV / GLS / Panel
5. 所有现有测试（M1-M5）不受影响
6. 新增测试覆盖率：IV ≥ 8 个测试，GLS ≥ 6 个测试，协议方法 ≥ 10 个测试
