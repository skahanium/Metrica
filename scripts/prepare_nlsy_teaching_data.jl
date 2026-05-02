# === NLSY 教学数据导入模板 ===================================================
# 本脚本不下载 NLSY 原始数据。请先通过 NLS Investigator 导出 public-use CSV，
# 再将导出文件路径传给本脚本。
#
# 用法：
#   julia scripts/prepare_nlsy_teaching_data.jl /path/to/nlsy_export.csv
#
# 输出：
#   datasets/teaching/nlsy_panel_template_meta.json
# ==============================================================================

const ROOT = dirname(dirname(@__FILE__))
const OUTPUT_META = joinpath(ROOT, "datasets", "teaching", "nlsy_panel_template_meta.json")

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
    source = length(ARGS) >= 1 ? ARGS[1] : ""

    metadata = Dict(
        "name" => "NLSY Public-use Teaching Panel Template",
        "description" => "NLSY 教学面板数据入口模板。实际 CSV 需由用户通过 NLS Investigator 选择变量并导出。",
        "source" => "National Longitudinal Surveys public-use data via NLS Investigator",
        "source_url" => "https://www.nlsinfo.org/content/access-data-investigator",
        "license" => "请以 NLS 官方 public-use 条款和用户导出的变量清单为准。",
        "local_source_csv" => source,
        "recommended_variables" => [
            "person_id",
            "survey_year",
            "hourly_wage",
            "education",
            "experience",
            "employment_status",
        ],
        "recommended_formulas" => [
            "log_wage ~ education + experience",
            "log_wage ~ education",
        ],
        "notes" => [
            "本仓库不提交未经明确变量抽取记录的 NLSY 原始行数据。",
            "生成真实教学子集时，应同步提交变量映射、cohort、年份范围与缺失值规则。",
        ],
    )

    mkpath(dirname(OUTPUT_META))
    open(OUTPUT_META, "w") do io
        write_json(io, metadata)
        println(io)
    end
    @info "NLSY 教学数据模板元数据已生成" output=OUTPUT_META
end

main()
