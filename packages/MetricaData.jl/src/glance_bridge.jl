# 数据查看命令与 MetricaBase.ModelGlance 协议对齐。

"""
    missing_cells_count(dataset::DataFrame) -> Int

统计全表缺失单元格数量。
"""
function missing_cells_count(dataset::DataFrame)
    total = 0
    for col in eachcol(dataset)
        total += count(ismissing, col)
    end
    return total
end

"""
    dataset_glance(dataset::DataFrame, kind::Symbol; extra_metrics=...) -> ModelGlance

构造数据查看类命令的 `ModelGlance`：`nobs` 为行数，`dof` 为列数。
"""
function dataset_glance(
    dataset::DataFrame,
    kind::Symbol;
    extra_metrics::Dict{Symbol, MetricaBase.MetricValue}=Dict{Symbol, MetricaBase.MetricValue}(),
)
    base_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :row_count => Float64(nrow(dataset)),
        :column_count => Float64(ncol(dataset)),
        :missing_cells => Float64(missing_cells_count(dataset)),
    )
    merge!(base_metrics, extra_metrics)
    return MetricaBase.ModelGlance(kind, nrow(dataset), ncol(dataset), base_metrics, MetricaBase.ModelWarning[])
end

"""
    attach_glance_to_payload(payload, glance::ModelGlance) -> Dict{String, Any}

在 `result_payload` 中嵌入与拟合结果同形的 `glance` 信封。
"""
function attach_glance_to_payload(payload::Dict{String, Any}, glance::MetricaBase.ModelGlance)
    gd, _ = MetricaBase.build_glance_envelope(glance)
    out = copy(payload)
    out["glance"] = gd
    return out
end
