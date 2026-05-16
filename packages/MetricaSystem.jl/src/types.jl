# === 多方程系统模型类型 ========================================================

"""SUR（似不相关回归 / FGLS）模型占位规格。"""
struct SURModel <: MetricaBase.AbstractEconModel end

"""按方程 2SLS 的系统占位规格（共享 listwise 样本）。"""
struct System2SLSModel <: MetricaBase.AbstractEconModel end

"""单步 3SLS（2SLS 残差协方差 + 第二阶段 GLS）占位规格。"""
struct System3SLSModel <: MetricaBase.AbstractEconModel end

"""
多方程拟合的统一结构化结果。

- `equation_glances`：每方程一条 `ModelGlance`（与单方程输出键对齐，便于 App 复用）。
- `tidy_table`：合并系数表；`tidy_equation_labels` 与 `tidy_table.rows` 等长，用于序列化 `equation` 列。
"""
struct SystemEquationsFitResult <: MetricaBase.AbstractFittedModel
    model_type_key::Symbol
    system_method::String
    equation_labels::Vector{String}
    equation_glances::Vector{MetricaBase.ModelGlance}
    tidy_table::MetricaBase.TidyTable
    tidy_equation_labels::Vector{String}
    diagnostics::Dict{Symbol, Any}
    all_warnings::Vector{MetricaBase.ModelWarning}
    nobs::Int
    iterations::Int
end

function _aggregate_glance(r::SystemEquationsFitResult)
    isempty(r.equation_glances) && return MetricaBase.ModelGlance(
        r.model_type_key, r.nobs, 0,
        Dict{Symbol, MetricaBase.MetricValue}(:n_equations => length(r.equation_labels)),
        r.all_warnings,
    )
    g1 = r.equation_glances[1]
    metrics = copy(g1.metrics)
    metrics[:n_equations] = length(r.equation_glances)
    dof_sum = sum(g.dof for g in r.equation_glances; init = 0)
    return MetricaBase.ModelGlance(r.model_type_key, r.nobs, dof_sum, metrics, r.all_warnings)
end

MetricaBase.glance(r::SystemEquationsFitResult) = _aggregate_glance(r)
MetricaBase.tidy(r::SystemEquationsFitResult) = r.tidy_table
