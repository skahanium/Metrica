module MetricaOutput

using MetricaBase

export summary_card

"""
根据结构化 glance 载荷生成最简可读摘要。
"""
function summary_card(glance::MetricaBase.ModelGlance)
    metric_pairs = collect(glance.metrics)
    metric_text = isempty(metric_pairs) ? "metrics: none" :
        join(["$(key)=$(value)" for (key, value) in metric_pairs], ", ")

    return "model=$(glance.model), nobs=$(glance.nobs), dof=$(glance.dof), " * metric_text
end

end
