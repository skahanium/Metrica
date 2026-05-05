# === AIPW 估计器（占位，Phase 4 实现）=========================================
function MetricaBase.fit(::Type{AIPWModel}, formula::AbstractString, data;
                          treatment_column::Symbol, outcome_column::Symbol,
                          outcome_formula::String, propensity_formula::String)
    return MetricaBase.ModelError(:not_implemented, "AIPW 尚未实现", "将在 Phase 4 实现。", "")
end
