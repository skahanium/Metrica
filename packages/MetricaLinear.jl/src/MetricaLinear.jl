module MetricaLinear

using MetricaBase

export OLSModel, OLSFitResult, PHASE_1_MODELS

const PHASE_1_MODELS = (:OLS,)

"""
第一条参考线性模型的规格对象。
"""
struct OLSModel <: MetricaBase.AbstractEconModel
    formula::String
end

"""
第一条垂直切片的拟合结果占位形状。
"""
struct OLSFitResult <: MetricaBase.AbstractFittedModel
    formula::String
    nobs::Int
    warnings::Vector{MetricaBase.ModelWarning}
end

end
