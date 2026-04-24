module MetricaLinear

using MetricaBase

export OLSModel, OLSFitResult, PHASE_1_MODELS

const PHASE_1_MODELS = (:OLS,)

"""
Specification object for the first reference linear model.
"""
struct OLSModel <: MetricaBase.AbstractEconModel
    formula::String
end

"""
Placeholder fitted-result shape for the first vertical slice.
"""
struct OLSFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    nobs::Int
    warnings::Vector{MetricaBase.ModelWarning}
end

end
