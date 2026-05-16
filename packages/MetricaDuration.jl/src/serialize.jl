# === JSON 载荷（与 MetricaSpatial 形状对齐）================================

function severity_to_string(severity::MetricaBase.Severity)
    return String(Symbol(severity))
end

function warning_to_dict(warning::MetricaBase.ModelWarning)
    return Dict(
        "code" => String(warning.code),
        "title" => warning.title,
        "detail" => warning.detail,
        "hint" => warning.hint,
        "severity" => severity_to_string(warning.severity),
    )
end

function error_to_payload(err::MetricaBase.ModelError)
    return Dict(
        "status" => "error",
        "messages" => [
            Dict(
                "level" => "error",
                "code" => String(err.code),
                "text" => err.detail,
                "hint" => err.hint,
            ),
        ],
    )
end

function _diag_to_dict(d::Dict{Symbol, Any})
    out = Dict{String, Any}()
    for (k, v) in d
        if v isa Symbol
            out[String(k)] = String(v)
        elseif v === nothing
            out[String(k)] = nothing
        elseif v isa Dict
            out[String(k)] = _diag_to_dict(v)
        else
            out[String(k)] = v
        end
    end
    return out
end

function _hazard_ratio_rows(beta::Vector{Float64}, se::Vector{Float64}, names::Vector{Symbol})
    zcrit = 1.9599639845400536
    out = Dict{String, Any}[]
    for i in eachindex(names)
        b = beta[i]
        s = se[i]
        hr = exp(b)
        if s > 0 && isfinite(s)
            lo = exp(b - zcrit * s)
            hi = exp(b + zcrit * s)
        else
            lo = nothing
            hi = nothing
        end
        push!(
            out,
            Dict{String, Any}(
                "term" => String(names[i]),
                "hr" => hr,
                "ci_lower" => lo,
                "ci_upper" => hi,
            ),
        )
    end
    return out
end

function result_to_payload(result::CoxFitResult; include_augment::Bool = true)
    glance_table = MetricaBase.glance(result)
    tidy_table = MetricaBase.tidy(result)
    warnings = [warning_to_dict(w) for w in glance_table.warnings]

    summary_text = try
        MetricaOutput.summary_card(glance_table)
    catch
        ""
    end

    tidy_rows = [
        let se = r.stderror
            se2 = se === nothing || (se isa Float64 && isnan(se)) ? nothing : se
            Dict(
                "name" => String(r.name),
                "estimate" => r.estimate,
                "stderror" => se2,
                "statistic" => r.statistic,
                "pvalue" => r.pvalue,
                "ci_lower" => r.ci_lower,
                "ci_upper" => r.ci_upper,
            )
        end
        for r in tidy_table.rows
    ]

    hr_rows = _hazard_ratio_rows(result.beta, result.se, result.coef_names)

    payload = Dict(
        "status" => "success",
        "messages" => [
            Dict(
                "level" => severity_to_string(w.severity),
                "code" => String(w.code),
                "text" => w.detail,
                "hint" => w.hint,
            )
            for w in glance_table.warnings
        ],
        "result_payload" => Dict(
            "glance" => Dict(
                "model" => String(glance_table.model),
                "nobs" => glance_table.nobs,
                "dof" => glance_table.dof,
                "metrics" => Dict(String(k) => v for (k, v) in glance_table.metrics),
                "warnings" => warnings,
            ),
            "vcov_label" => tidy_table.vcov_label,
            "tidy" => tidy_rows,
            "warnings" => warnings,
            "summary_text" => summary_text,
            "loglikelihood" => result.loglik,
            "aic" => nothing,
            "bic" => nothing,
            "diagnostics" => _diag_to_dict(result.diagnostics),
            "hazard_ratios" => hr_rows,
        ),
    )

    # 首期 Cox 不提供 augment；忽略 include_augment。

    return payload
end

result_to_payload(err::MetricaBase.ModelError) = error_to_payload(err)
