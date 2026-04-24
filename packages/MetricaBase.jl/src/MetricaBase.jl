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
Lightweight warning object designed for package, runtime, and app consumption.
"""
struct ModelWarning
    code::Symbol
    title::String
    detail::String
    hint::Union{Nothing, String}
    severity::Symbol
end

"""
Model-level summary payload for downstream consumers.
"""
struct ModelGlance
    model::Symbol
    nobs::Int
    dof::Int
    metrics::Dict{Symbol, Any}
    warnings::Vector{ModelWarning}
end

"""
One coefficient row in a structured parameter table.
"""
struct CoefRow
    name::Symbol
    estimate::Float64
    stderror::Union{Nothing, Float64}
    statistic::Union{Nothing, Float64}
    pvalue::Union{Nothing, Float64}
end

"""
Structured coefficient table for output and app layers.
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
