function load_dataset(path::AbstractString)
    isfile(path) || return MetricaBase.ModelError(
        :dataset_not_found,
        "数据文件不存在",
        "指定的 CSV 文件不存在，无法读取数据。",
        "请确认文件路径后重试。",
    )

    try
        return CSV.read(path, DataFrame)
    catch err
        return MetricaBase.ModelError(
            :csv_parse_failed,
            "CSV 解析失败",
            "CSV 文件无法被正确解析：$(sprint(showerror, err))",
            "请检查分隔符、表头与编码是否正确。",
        )
    end
end

function normalize_preview_value(value)
    if ismissing(value)
        return nothing
    end

    return value
end

function inferred_type_label(column)
    return string(eltype(column))
end

function dataset_summary_dict(dataset)
    return Dict(
        "row_count" => nrow(dataset),
        "column_count" => ncol(dataset),
    )
end

function columns_summary(dataset)
    return [
        Dict(
            "name" => String(name),
            "inferred_type" => inferred_type_label(dataset[!, name]),
            "missing_count" => count(ismissing, dataset[!, name]),
        )
        for name in names(dataset)
    ]
end

function preview_rows(dataset; limit::Int=5)
    preview = first(dataset, min(limit, nrow(dataset)))

    return [
        Dict(
            String(name) => normalize_preview_value(row[name])
            for name in names(preview)
        )
        for row in eachrow(preview)
    ]
end
