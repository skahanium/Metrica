module MetricaOutput

using MetricaBase

export summary_card, markdown_regtable
export markdown_run_report
export csv_tidy, csv_glance, csv_diagnostics

function metric_value_text(metrics::Dict{Symbol, MetricaBase.MetricValue}, key::Symbol)
    value = get(metrics, key, nothing)
    isnothing(value) && return "—"
    return string(round(Float64(value), digits=4))
end

"""
根据结构化 glance 载荷生成教学向可读摘要。
"""
function summary_card(glance::MetricaBase.ModelGlance)
    metrics = glance.metrics
    return join(
        [
            "模型：$(glance.model)",
            "样本量：$(glance.nobs)",
            "自由度：$(glance.dof)",
            "R²：$(metric_value_text(metrics, :r2))",
            "调整 R²：$(metric_value_text(metrics, :adj_r2))",
            "Sigma：$(metric_value_text(metrics, :sigma))",
        ],
        " | ",
    )
end

function format_cell(value)
    isnothing(value) && return "—"
    value isa Number && return string(round(Float64(value), digits=4))
    return string(value)
end

"""
根据结构化 tidy 载荷生成 Markdown 回归表。
"""
function markdown_regtable(tidy::MetricaBase.TidyTable)
    lines = [
        "| 参数 | 估计值 | 标准误 | 统计量 | p 值 |",
        "|---|---:|---:|---:|---:|",
    ]
    append!(
        lines,
        [
            "| $(row.name) | $(format_cell(row.estimate)) | $(format_cell(row.stderror)) | $(format_cell(row.statistic)) | $(format_cell(row.pvalue)) |"
            for row in tidy.rows
        ],
    )
    return join(lines, "\n")
end

function _dict_get(dict, key, default=nothing)
    if dict isa Dict
        return get(dict, key, get(dict, Symbol(key), default))
    end
    return default
end

function _format_pvalue(pvalue)
    if isnothing(pvalue) || !(pvalue isa Number)
        return "—"
    end
    v = Float64(pvalue)
    if v < 0.001
        return "$(round(v, digits=6)) ***"
    elseif v < 0.01
        return "$(round(v, digits=6)) **"
    elseif v < 0.05
        return "$(round(v, digits=6)) *"
    elseif v < 0.1
        return "$(round(v, digits=6)) ."
    else
        return string(round(v, digits=6))
    end
end

function _format_diag_value(value)
    if isnothing(value)
        return "—"
    elseif value isa Number
        return string(round(Float64(value), digits=4))
    elseif value isa Array
        return join(string.(value), "; ")
    else
        return string(value)
    end
end

function _diagnostics_section(diagnostics)
    isempty(diagnostics) && return ""

    lines = ["## 诊断结果", ""]

    # OLS 诊断
    ols_keys = ["vif", "breusch_pagan", "white_test", "durbin_watson", "breusch_godfrey", "reset_test", "jarque_bera"]
    has_ols = any(k -> haskey(diagnostics, k), ols_keys)

    # Panel 诊断
    panel_keys = ["hausman", "fixed_effect_f", "breusch_pagan_lm"]
    has_panel = any(k -> haskey(diagnostics, k), panel_keys)

    if has_ols
        push!(lines, "| 诊断项 | 统计量 | p 值 | 自由度 |")
        push!(lines, "|---|---:|---:|--:|")

        # VIF
        vif = _dict_get(diagnostics, "vif")
        if !isnothing(vif) && vif isa AbstractVector
            vif_strs = [
                "$(get(v, "name", get(v, :name, "?"))): $(round(Float64(get(v, "vif", get(v, :vif, NaN))), digits=2))"
                for v in vif
            ]
            push!(lines, "| VIF | $(join(vif_strs, "; ")) | — | — |")
        end

        # 其他 OLS 诊断项
        for key in ["breusch_pagan", "white_test", "durbin_watson", "breusch_godfrey", "reset_test", "jarque_bera"]
            diag = _dict_get(diagnostics, key)
            isnothing(diag) && continue
            stat = _format_diag_value(_dict_get(diag, "statistic"))
            pval = _format_pvalue(_dict_get(diag, "pvalue"))
            dof = _format_diag_value(_dict_get(diag, "dof"))

            label = Dict(
                "breusch_pagan" => "Breusch-Pagan",
                "white_test" => "White 检验",
                "durbin_watson" => "Durbin-Watson",
                "breusch_godfrey" => "Breusch-Godfrey",
                "reset_test" => "RESET 检验",
                "jarque_bera" => "Jarque-Bera",
            )
            push!(lines, "| $(get!(label, key, key)) | $stat | $pval | $dof |")
        end
    end

    if has_panel
        if !isempty(lines) && has_ols
            push!(lines, "")
        end
        if !has_ols
            push!(lines, "| 诊断项 | 统计量 | p 值 | 自由度 |")
            push!(lines, "|---|---:|---:|--:|")
        end

        for key in ["hausman", "fixed_effect_f", "breusch_pagan_lm"]
            diag = _dict_get(diagnostics, key)
            isnothing(diag) && continue
            stat = _format_diag_value(_dict_get(diag, "statistic"))
            pval = _format_pvalue(_dict_get(diag, "pvalue"))
            dof = _format_diag_value(_dict_get(diag, "dof"))

            label = Dict(
                "hausman" => "Hausman 检验",
                "fixed_effect_f" => "固定效应 F 检验",
                "breusch_pagan_lm" => "Breusch-Pagan LM",
            )
            push!(lines, "| $(get!(label, key, key)) | $stat | $pval | $dof |")
        end
    end

    isempty(lines) || length(lines) <= 2 ? "" : join(lines, "\n")
end

"""
根据运行记录与结构化结果生成最小 Markdown 报告。
"""
function markdown_run_report(run_record, result)
    dataset_path = _dict_get(_dict_get(run_record, "dataset_ref", Dict()), "path", "—")
    model_spec = _dict_get(run_record, "model_spec", Dict())
    model_type = _dict_get(model_spec, "model_type", "—")
    formula = _dict_get(model_spec, "formula", "—")
    finished_at = _dict_get(run_record, "finished_at", "—")
    messages = _dict_get(run_record, "messages", Any[])
    warnings = get(result, "warnings", Any[])

    glance_lines = String[]
    if haskey(result, "glance")
        glance = result["glance"]
        metrics = get(glance, "metrics", Dict())
        push!(glance_lines, "- 模型：$(get(glance, "model", "—"))")
        push!(glance_lines, "- 样本量：$(get(glance, "nobs", "—"))")
        push!(glance_lines, "- 自由度：$(get(glance, "dof", "—"))")
        if haskey(metrics, "r2")
            push!(glance_lines, "- R²：$(metrics["r2"])")
        end
    end

    tidy_table = if haskey(result, "tidy")
        rows = [
            MetricaBase.CoefRow(
                Symbol(get(row, "term", get(row, "name", "term"))),
                Float64(get(row, "estimate", 0.0)),
                get(row, "std_error", get(row, "stderror", nothing)),
                get(row, "statistic", nothing),
                get(row, "p_value", get(row, "pvalue", nothing)),
                get(row, "ci_lower", nothing),
                get(row, "ci_upper", nothing),
            )
            for row in result["tidy"]
        ]
        markdown_regtable(MetricaBase.TidyTable(rows, string(get(result, "vcov_label", "classical"))))
    else
        ""
    end

    diagnostics = get(result, "diagnostics", Dict())
    diag_section = _diagnostics_section(diagnostics)

    warning_lines = isempty(warnings) ? ["- 无"] : [
        "- $(get(w, "title", "warning"))：$(get(w, "detail", ""))" for w in warnings
    ]
    message_lines = isempty(messages) ? ["- 无"] : [
        "- $(get(m, "code", "INFO"))：$(get(m, "text", ""))" for m in messages
    ]

    sections = [
        "# Metrica 单次运行报告",
        "",
        "## 基本信息",
        "- 数据集：$(dataset_path)",
        "- 模型类型：$(model_type)",
        "- 公式：$(formula)",
        "- 运行时间：$(finished_at)",
        "",
        "## 模型摘要",
        isempty(glance_lines) ? "- 无" : join(glance_lines, "\n"),
        "",
        "## 系数表",
        isempty(tidy_table) ? "无" : tidy_table,
    ]
    if diag_section != ""
        push!(sections, "", diag_section)
    end
    push!(sections, "", "## Warnings", join(warning_lines, "\n"), "", "## Messages", join(message_lines, "\n"))

    return join(sections, "\n")
end

"""
将 tidy 系数表导出为 CSV 字符串。
"""
function csv_tidy(result)
    rows = get(result, "tidy", Any[])
    isempty(rows) && return "term,estimate,std_error,statistic,p_value\n"

    lines = ["term,estimate,std_error,statistic,p_value"]
    for row in rows
        term = get(row, "term", get(row, "name", ""))
        estimate = get(row, "estimate", "")
        std_error = get(row, "std_error", get(row, "stderror", ""))
        statistic = get(row, "statistic", "")
        p_value = get(row, "p_value", get(row, "pvalue", ""))
        push!(lines, "$(term),$(estimate),$(std_error),$(statistic),$(p_value)")
    end
    return join(lines, "\n") * "\n"
end

"""
将 glance 摘要指标导出为 CSV 字符串。
"""
function csv_glance(result)
    glance = get(result, "glance", Dict())
    isempty(glance) && return "metric,value\n"

    lines = ["metric,value"]
    push!(lines, "model,$(get(glance, "model", ""))")
    push!(lines, "nobs,$(get(glance, "nobs", ""))")
    push!(lines, "dof,$(get(glance, "dof", ""))")

    metrics = get(glance, "metrics", Dict())
    for (key, value) in metrics
        push!(lines, "$(key),$(value)")
    end
    return join(lines, "\n") * "\n"
end

"""
将诊断结果导出为 CSV 字符串。
"""
function csv_diagnostics(result)
    diagnostics = get(result, "diagnostics", Dict())
    isempty(diagnostics) && return "diagnostic,statistic,pvalue,dof,available\n"

    lines = ["diagnostic,statistic,pvalue,dof,available"]
    for (name, diag) in diagnostics
        diag isa Dict || continue
        statistic = get(diag, "statistic", "")
        pvalue = get(diag, "pvalue", "")
        dof = get(diag, "dof", "")
        available = get(diag, "available", true)
        # 处理 dof 为数组的情况（如 fixed_effect_f）
        dof_str = dof isa Array ? join(dof, ";") : string(dof)
        push!(lines, "$(name),$(statistic),$(pvalue),$(dof_str),$(available)")
    end
    return join(lines, "\n") * "\n"
end

end
