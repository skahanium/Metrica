# === PWT 教学数据生成脚本 ====================================================
# 从官方 PWT 10.01 Excel 文件生成 Metrica 教学用生产率面板子集。
#
# 默认输入：
#   https://dataverse.nl/api/access/datafile/354095
#
# 说明：
#   本脚本只依赖 Julia 标准库和系统 `unzip` 命令。为避免给核心包引入
#   Excel 解析依赖，这里以最小 OOXML 读取逻辑抽取 Data 工作表。
# ==============================================================================

using Dates
using Downloads
using Printf

const ROOT = dirname(dirname(@__FILE__))
const DEFAULT_URL = "https://dataverse.nl/api/access/datafile/354095"
const DEFAULT_XLSX = joinpath(ROOT, "datasets", "raw", "pwt1001.xlsx")
const DEFAULT_CSV = joinpath(ROOT, "datasets", "teaching", "pwt_productivity_panel.csv")
const DEFAULT_META = joinpath(ROOT, "datasets", "teaching", "pwt_productivity_panel_meta.json")
const COUNTRIES = ["USA", "CAN", "MEX", "BRA", "GBR", "FRA", "DEU", "JPN", "KOR", "CHN", "IND", "ZAF"]
const YEARS = 1990:2019

function ensure_source(path::String, url::String)
    if isfile(path)
        return path
    end

    mkpath(dirname(path))
    @info "下载 PWT 10.01 Excel 文件" url path
    Downloads.download(url, path)
    return path
end

function unzip_text(xlsx::String, member::String)
    return read(`unzip -p $xlsx $member`, String)
end

function shared_strings(xlsx::String)
    xml = unzip_text(xlsx, "xl/sharedStrings.xml")
    strings = String[]
    for item in eachmatch(r"<si>(.*?)</si>"s, xml)
        parts = [m.captures[1] for m in eachmatch(r"<t[^>]*>(.*?)</t>"s, item.captures[1])]
        push!(strings, replace(join(parts), "&amp;" => "&", "&lt;" => "<", "&gt;" => ">"))
    end
    return strings
end

function column_name(ref::String)
    return replace(ref, r"\d" => "")
end

function worksheet_rows(xlsx::String)
    strings = shared_strings(xlsx)
    xml = unzip_text(xlsx, "xl/worksheets/sheet3.xml")
    rows = Vector{Dict{String, String}}()

    for row_match in eachmatch(r"<row[^>]*>(.*?)</row>"s, xml)
        row = Dict{String, String}()
        for cell_match in eachmatch(r"<c[^>]*r=\"([A-Z]+)\d+\"[^>]*?(?:t=\"([^\"]+)\")?[^>]*>(.*?)</c>"s, row_match.captures[1])
            col = cell_match.captures[1]
            typ = cell_match.captures[2]
            body = cell_match.captures[3]
            value_match = match(r"<v>(.*?)</v>"s, body)
            isnothing(value_match) && continue

            value = value_match.captures[1]
            if typ == "s"
                value = strings[parse(Int, value) + 1]
            end
            row[col] = value
        end
        push!(rows, row)
    end

    return rows
end

function parse_float(row, key)
    value = get(row, key, "")
    isempty(value) && return nothing
    return parse(Float64, value)
end

function write_csv(rows, path::String)
    mkpath(dirname(path))
    columns = [
        "country", "isocode", "year", "rgdpo", "pop", "emp", "hc", "cn", "ctfp",
        "output_per_worker", "capital_per_worker",
        "log_output_per_worker", "log_capital_per_worker",
    ]

    open(path, "w") do io
        println(io, join(columns, ","))
        for row in rows
            println(io, join([row[col] for col in columns], ","))
        end
    end
end

function build_subset(xlsx::String)
    rows = worksheet_rows(xlsx)
    header = first(rows)
    names = Dict(value => col for (col, value) in header)
    output = Vector{Dict{String, Any}}()

    for raw in rows[2:end]
        code = get(raw, names["countrycode"], "")
        year_text = get(raw, names["year"], "")
        isempty(year_text) && continue
        year = parse(Int, split(year_text, ".")[1])
        (code in COUNTRIES && year in YEARS) || continue

        rgdpo = parse_float(raw, names["rgdpo"])
        pop = parse_float(raw, names["pop"])
        emp = parse_float(raw, names["emp"])
        hc = parse_float(raw, names["hc"])
        cn = parse_float(raw, names["cn"])
        ctfp = parse_float(raw, names["ctfp"])
        any(isnothing, (rgdpo, pop, emp, hc, cn)) && continue
        any(value -> value <= 0, (rgdpo, pop, emp, hc, cn)) && continue

        output_per_worker = rgdpo / emp
        capital_per_worker = cn / emp

        push!(output, Dict(
            "country" => get(raw, names["country"], ""),
            "isocode" => code,
            "year" => year,
            "rgdpo" => rgdpo,
            "pop" => pop,
            "emp" => emp,
            "hc" => hc,
            "cn" => cn,
            "ctfp" => isnothing(ctfp) ? "" : ctfp,
            "output_per_worker" => output_per_worker,
            "capital_per_worker" => capital_per_worker,
            "log_output_per_worker" => log(output_per_worker),
            "log_capital_per_worker" => log(capital_per_worker),
        ))
    end

    sort!(output; by=row -> (findfirst(==(row["isocode"]), COUNTRIES), row["year"]))
    return output
end

function write_metadata(rows, path::String)
    mkpath(dirname(path))
    metadata = Dict(
        "name" => "Penn World Table Productivity Teaching Panel",
        "description" => "从 PWT 10.01 生成的教学用国家生产率面板子集，覆盖 12 个经济体 1990-2019 年。",
        "source" => "Penn World Table version 10.01, Groningen Growth and Development Centre, University of Groningen.",
        "doi" => "10.34894/QT5BCC",
        "source_url" => "https://dataverse.nl/dataset.xhtml?persistentId=doi:10.34894/QT5BCC",
        "license" => "CC-BY-4.0",
        "period" => "1990-2019",
        "n_countries" => length(COUNTRIES),
        "n_observations" => length(rows),
        "balanced" => length(rows) == length(COUNTRIES) * length(YEARS),
        "recommended_formulas" => [
            "log_output_per_worker ~ log_capital_per_worker + hc",
            "log_output_per_worker ~ log_capital_per_worker",
            "ctfp ~ hc",
        ],
        "recommended_models" => ["FE（固定效应）", "RE（随机效应）", "Between（组间估计）"],
        "tutorials" => ["国家生产率面板", "固定效应与随机效应比较", "Hausman 检验"],
        "created" => string(today()),
    )
    open(path, "w") do io
        write_json(io, metadata)
        println(io)
    end
end

function json_escape(value::String)
    escaped = replace(value, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n")
    return "\"$escaped\""
end

function write_json(io, value, indent::Int=0)
    pad = " "^indent
    nextpad = " "^(indent + 2)
    if value isa Dict
        println(io, "{")
        pairs = collect(value)
        for (index, (key, item)) in enumerate(pairs)
            print(io, nextpad, json_escape(String(key)), ": ")
            write_json(io, item, indent + 2)
            index < length(pairs) && print(io, ",")
            println(io)
        end
        print(io, pad, "}")
    elseif value isa AbstractVector
        println(io, "[")
        for (index, item) in enumerate(value)
            print(io, nextpad)
            write_json(io, item, indent + 2)
            index < length(value) && print(io, ",")
            println(io)
        end
        print(io, pad, "]")
    elseif value isa String
        print(io, json_escape(value))
    elseif value isa Bool
        print(io, value ? "true" : "false")
    elseif value === nothing
        print(io, "null")
    else
        print(io, value)
    end
end

function main()
    source = ensure_source(DEFAULT_XLSX, DEFAULT_URL)
    rows = build_subset(source)
    write_csv(rows, DEFAULT_CSV)
    write_metadata(rows, DEFAULT_META)
    @info "PWT 教学数据已生成" rows=length(rows) output=DEFAULT_CSV
end

main()
