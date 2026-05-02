module MetricaBase

# === 导出列表 ================================================================

export AbstractEconModel,
    AbstractFittedModel,
    AbstractCovarianceSpec,
    AbstractPanelModel,
    AbstractLinearModel,
    AbstractLinearFitResult,
    Severity,
    info,
    warning,
    critical,
    ModelWarning,
    ModelError,
    MetricValue,
    ModelGlance,
    CoefRow,
    TidyTable,
    AugmentTable,
    PanelData,
    fit,
    coef,
    vcov,
    predict,
    glance,
    tidy,
    augment,
    stderror,
    confint,
    nobs,
    dof,
    r2,
    fitted,
    residuals

# === 严重程度枚举 ============================================================

"""
消息与警告的严重程度等级，供 `ModelWarning` 等类型使用。
"""
@enum Severity begin
    info
    warning
    critical
end

# === 抽象协议类型 ============================================================

"""
计量模型的抽象父类型。

既是模型规格对象（如 `OLSModel`）的协议入口，也是已拟合结果
（`AbstractFittedModel`）的祖先链终点。所有跨包共享的模型语义均通过
此类型及其子类型承载。
"""
abstract type AbstractEconModel end

"""
已拟合模型的抽象父类型。

携带拟合后的结果载荷、警告与诊断信息。下游应通过 `glance`、`tidy`、
`coef`、`vcov` 等函数消费其内容，而非直接访问内部字段。
"""
abstract type AbstractFittedModel end

"""
协方差估计规格的抽象父类型。

供 `vcov`、`fit` 等函数分派。子类型应编码协方差估计方法
（经典、HC1、聚类等）及其所需参数。
"""
abstract type AbstractCovarianceSpec end

"""
面板模型的抽象父类型。

子类型应编码面板估计方法（FE、RE、FD、Between 等）及其所需参数。
面板模型需要个体标识和时间标识来定义面板结构。
"""
abstract type AbstractPanelModel <: AbstractEconModel end

"""
线性模型族的抽象父类型。

OLS、WLS、IV/2SLS、GLS 等线性模型均应继承此类型。
用于统一 `fit` 泛型分派和协议方法分派。
"""
abstract type AbstractLinearModel <: AbstractEconModel end

"""
线性模型拟合结果的抽象父类型。

所有线性模型的拟合结果（OLSFitResult、IVFitResult、GLSFitResult）
均应继承此类型，以统一 `coef`、`vcov`、`predict` 等协议方法的分派。
"""
abstract type AbstractLinearFitResult <: AbstractFittedModel end

# === 消息与错误载荷 ==========================================================

"""
供包内、Runtime 与 App 消费的轻量警告对象。

警告表示拟合过程中发生了值得用户关注、但不阻断结果产出的情况
（例如缺失值删除、样本量变化、自由度修正等）。
"""
struct ModelWarning
    code::Symbol
    title::String
    detail::String
    hint::Union{Nothing, String}
    severity::Severity
end

"""
拟合或数据处理过程中断性错误的载荷。

与 `ModelWarning` 不同，`ModelError` 表示结果**无法**产出的阻断性错误
（例如设计矩阵奇异、有效样本为空、公式含未定义变量等）。

字段 `hint` 可为 `nothing`，此时下游不应展示建议区域。
"""
struct ModelError
    code::Symbol
    title::String
    detail::String
    hint::Union{Nothing, String}
end

# === 结构化结果中使用的值类型 =================================================

"""
`ModelGlance.metrics` 字典中允许的值类型。

当前仅包含 `Float64` 与 `Int`，后续可根据需要扩展 `Missing` 等成员。
"""
const MetricValue = Union{Float64, Int}

# === 结构化输出类型 ==========================================================

"""
模型级单行摘要载荷。

一个 `ModelGlance` 包含拟合后单模型的关键数字，供 Runtime 序列化及
App 结果卡片渲染。不携带系数表、诊断图或逐行预测数据。
"""
struct ModelGlance
    model::Symbol
    nobs::Int
    dof::Int
    metrics::Dict{Symbol, MetricValue}
    warnings::Vector{ModelWarning}
end

"""
结构化参数表中的一行系数。

`stderror`、`statistic`、`pvalue` 可为 `nothing`——当某模型未输出
相应列（例如仅提供标准误而不计算 t 统计量）时，下游应据此省略展示。
"""
struct CoefRow
    name::Symbol
    estimate::Float64
    stderror::Union{Nothing, Float64}
    statistic::Union{Nothing, Float64}
    pvalue::Union{Nothing, Float64}
end

"""
面向输出层与 App 的结构化系数表。

由 `tidy()` 返回。`vcov_label` 标明所使用的协方差估计方法
（例如 `"classical"`、`"HC1"`），便于下游标注。
"""
struct TidyTable
    rows::Vector{CoefRow}
    vcov_label::String
end

"""
逐观测值增强表（拟合值、残差、诊断量等）。

由 `augment()` 返回。列式存储，每列为一个 `Vector{Float64}`。
标准列包括 `:observation`、`:fitted`、`:residual`，可选列包括
`:std_residual`、`:leverage`、`:cooks_d` 等。

下游可通过 `table.columns[:fitted]` 访问指定列。
"""
struct AugmentTable
    columns::Dict{Symbol, Vector{Float64}}
    nobs::Int
end

"""
面板数据容器。

存储面板结构的数据，包含个体标识和时间标识。
`data` 可以是 DataFrame、Dict 或任何 Tables.jl 兼容容器。
类型参数 `T` 保留具体数据类型，便于下游分派。
"""
struct PanelData{T}
    data::T
    id_col::Symbol
    time_col::Symbol
end

# === 公共 API 函数（接口桩）==================================================

"""
使用给定模型规格与数据拟合模型。

返回 `AbstractFittedModel` 的子类型实例；若拟合失败则返回 `ModelError`。
具体方法由各模型包（如 `MetricaLinear`）实现。
"""
function fit end

"""
从已拟合结果中提取系数向量。
"""
function coef end

"""
从已拟合结果中提取方差-协方差矩阵。

协方差估计方法由可选的 `AbstractCovarianceSpec` 参数指定。
"""
function vcov end

"""
基于已拟合结果对新数据进行预测。
"""
function predict end

"""
返回模型级单行摘要（`ModelGlance`）。
"""
function glance end

"""
返回结构化系数表（`TidyTable`）。
"""
function tidy end

"""
返回逐观测值增强表（拟合值、残差、诊断量等）。

具体列集合由各模型实现决定。
"""
function augment end

"""
从已拟合结果中提取标准误向量。
"""
function stderror end

"""
计算系数的置信区间。默认置信水平为 0.95。
"""
function confint end

"""
返回拟合所用的有效观测数。
"""
function nobs end

"""
返回模型的残差自由度。
"""
function dof end

"""
返回模型的 R² 决定系数。
"""
function r2 end

"""
返回拟合值向量。
"""
function fitted end

"""
返回残差向量。
"""
function residuals end

end
