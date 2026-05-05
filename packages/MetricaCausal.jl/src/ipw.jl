# === IPW 估计器（占位，Phase 4 实现）==========================================
function MetricaBase.fit(::Type{IPWModel}, formula::AbstractString, data;
                          treatment_column::Symbol, outcome_column::Symbol,
                          propensity_formula::String)
    return MetricaBase.ModelError(:not_implemented, "IPW 尚未实现", "将在 Phase 4 实现。", "")
end
