module MetricaOutput

using MetricaBase

export summary_card

"""
Render a minimal human-readable summary from a structured glance payload.
"""
function summary_card(glance::MetricaBase.ModelGlance)
    metric_pairs = collect(glance.metrics)
    metric_text = isempty(metric_pairs) ? "metrics: none" :
        join(["$(key)=$(value)" for (key, value) in metric_pairs], ", ")

    return "model=$(glance.model), nobs=$(glance.nobs), dof=$(glance.dof), " * metric_text
end

end
