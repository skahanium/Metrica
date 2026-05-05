# === PSM 估计器（占位，Phase 4 实现）==========================================
function MetricaBase.fit(::Type{PSMModel}, formula::AbstractString, data;
                          treatment_column::Symbol, outcome_column::Symbol,
                          propensity_formula::String, method::Symbol=:nearest,
                          caliper::Float64=0.2, n_neighbors::Int=1)
    return MetricaBase.ModelError(:not_implemented, "PSM 尚未实现", "将在 Phase 4 实现。", "")
end
