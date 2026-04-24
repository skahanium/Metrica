module MetricaBase

export AbstractEconModel,
    AbstractFittedModel,
    AbstractCovarianceSpec,
    ModelWarning,
    ModelGlance,
    CoefRow,
    TidyTable,
    fit,
    coef,
    vcov,
    predict,
    glance,
    tidy,
    augment

abstract type AbstractEconModel end
abstract type AbstractFittedModel end
abstract type AbstractCovarianceSpec end

"""
供包内、Runtime 与 App 消费的轻量警告对象。
"""
struct ModelWarning
    code::Symbol
    title::String
    detail::String
    hint::Union{Nothing, String}
    severity::Symbol
end

"""
模型级摘要载荷，供下游消费者使用。
"""
struct ModelGlance
    model::Symbol
    nobs::Int
    dof::Int
    metrics::Dict{Symbol, Any}
    warnings::Vector{ModelWarning}
end

"""
结构化参数表中的一行系数。
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
"""
struct TidyTable
    rows::Vector{CoefRow}
    vcov_label::String
end

function fit end
function coef end
function vcov end
function predict end
function glance end
function tidy end
function augment end

end
