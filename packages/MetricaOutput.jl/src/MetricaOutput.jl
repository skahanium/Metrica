module MetricaOutput

using MetricaBase

export summary_card, markdown_regtable

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

end
