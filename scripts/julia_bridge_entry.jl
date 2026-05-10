# === Metrica Runtime Julia 桥接入口 ===========================================
# 本脚本由 Runtime 通过 `julia -e` 的方式调用，接受两个命令行参数：
#   ARGS[1] — 序列化为 JSON 的 TaskRequest
#   ARGS[2] — 仓库根目录路径（用于定位包与诊断代码）
# 输出：单行 JSON 到 stdout，由 Runtime 解析为 JuliaEnvelope。
# ==============================================================================

using JSON3
using MetricaBase
using MetricaData
using MetricaLinear
using MetricaOutput

include(joinpath(String(ARGS[2]), "packages", "MetricaDiagnostics.jl", "src", "MetricaDiagnostics.jl"))
using .MetricaDiagnostics

request = JSON3.read(ARGS[1])
action = String(request.action)
dataset_path = String(request.dataset_ref.path)
payload = if action == "inspect_dataset"
    options = get(request, :options, Dict{Symbol, Any}())
    preview_rows = Int(get(options, :preview_rows, 5))
    MetricaLinear.inspect_dataset(dataset_path; preview_limit=preview_rows)
elseif action == "query_dataset"
    command = get(request, :command, Dict{Symbol, Any}())
    kind = String(get(command, :kind, ""))
    raw_variables = get(command, :variables, nothing)
    variables = isnothing(raw_variables) ? nothing : String.(collect(raw_variables))
    raw_limit = get(command, :limit, nothing)
    limit = isnothing(raw_limit) ? 200 : Int(raw_limit)

    if kind == "describe"
        MetricaData.describe_dataset(dataset_path; variables = variables)
    elseif kind == "summarize"
        MetricaData.summarize_dataset(dataset_path; variables = variables)
    elseif kind == "tabulate"
        variable = isnothing(variables) || isempty(variables) ? "" : first(variables)
        MetricaData.tabulate_dataset(dataset_path; variable = variable, max_levels = limit)
    elseif kind == "browse"
        MetricaData.browse_dataset(dataset_path; variables = variables)
    else
        Dict(
            "status" => "error",
            "messages" => Any[Dict(
                "level" => "error",
                "code" => "unsupported_data_command",
                "text" => "不支持的数据查看命令：$(kind)",
                "hint" => "当前仅支持 describe、browse、summarize、tabulate。",
            )],
        )
    end
elseif action == "export_report"
    format = String(get(request, :format, "markdown"))
    run_record = get(request, :run_record, Dict{String, Any}())
    result = get(request, :result, Dict{String, Any}())

    content = if format == "markdown"
        MetricaOutput.markdown_run_report(run_record, result)
    elseif format == "csv_tidy"
        MetricaOutput.csv_tidy(result)
    elseif format == "csv_glance"
        MetricaOutput.csv_glance(result)
    elseif format == "csv_diagnostics"
        MetricaOutput.csv_diagnostics(result)
    else
        ""
    end

    Dict(
        "status" => "success",
        "content" => content,
        "format" => format,
    )
else
    formula = String(request.model_spec.formula)
    model_type = String(request.model_spec.model_type)

    if model_type == "panel"
        # 面板模型拟合
        panel_id = Symbol(String(request.model_spec.panel_id))
        panel_time = Symbol(String(request.model_spec.panel_time))
        panel_method = Symbol(String(get(request.model_spec, :panel_method, "fe")))

        # 加载数据并构造 PanelData
        using CSV, DataFrames
        df = CSV.read(dataset_path, DataFrame)
        panel_data = MetricaBase.PanelData(df, panel_id, panel_time)

        result = fit_panel(panel_data, formula; method=panel_method)
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        payload = MetricaPanel.result_to_payload(result; include_augment=include_augment)
        payload["result_payload"]["diagnostics"] = panel_diagnostics(panel_data, formula)
        payload
    elseif model_type in ("survey_ols", "survey_logit", "survey_probit", "survey_poisson")
        # 调查模型拟合
        using CSV, DataFrames
        df = CSV.read(dataset_path, DataFrame)

        kwargs = Dict{Symbol, Any}()
        kwargs[:weights_column] = Symbol(String(request.model_spec.weights_column))
        if haskey(request.model_spec, :strata_column) && !isnothing(request.model_spec.strata_column) && !isempty(request.model_spec.strata_column)
            kwargs[:strata_column] = Symbol(String(request.model_spec.strata_column))
        end
        if haskey(request.model_spec, :psu_column) && !isnothing(request.model_spec.psu_column) && !isempty(request.model_spec.psu_column)
            kwargs[:psu_column] = Symbol(String(request.model_spec.psu_column))
        end
        if haskey(request.model_spec, :fpc_column) && !isnothing(request.model_spec.fpc_column) && !isempty(request.model_spec.fpc_column)
            kwargs[:fpc_column] = Symbol(String(request.model_spec.fpc_column))
        end

        # 使用 MODEL_REGISTRY 获取模型类型
        ModelT = MetricaBase.MODEL_REGISTRY[model_type]
        result = MetricaBase.fit(ModelT, formula, df; kwargs...)

        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        payload = MetricaSurvey.result_to_payload(result; include_augment=include_augment)
        payload
    else
        # 通过 MODEL_REGISTRY 统一派发
        kwargs = Dict{Symbol, Any}()
        vcov_type = haskey(request.model_spec, :vcov) ? String(request.model_spec.vcov.type) : "classical"
        vcov_symbol = vcov_type == "HC1" ? :HC1 : vcov_type == "cluster" ? :cluster : :classical
        kwargs[:vcov] = vcov_symbol
        if haskey(request.model_spec, :weights) && !isnothing(request.model_spec.weights) && !isempty(request.model_spec.weights)
            kwargs[:weights] = Symbol(String(request.model_spec.weights))
        end
        if haskey(request.model_spec, :cluster_column) && !isnothing(request.model_spec.cluster_column) && !isempty(request.model_spec.cluster_column)
            kwargs[:cluster_column] = Symbol(String(request.model_spec.cluster_column))
        end
        result = MetricaBase.fit(OLSModel, formula, dataset_path; kwargs...)
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        payload = MetricaLinear.result_to_payload(result; include_augment=include_augment)
        if result isa OLSFitResult
            payload["result_payload"]["diagnostics"] = diagnostics_to_dict(result)
        end
        payload
    end
end
println(JSON3.write(payload))
