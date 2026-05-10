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
