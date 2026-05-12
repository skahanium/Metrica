# === Metrica Runtime Julia 桥接入口 ===========================================
# 本脚本由 Runtime 通过 `julia -e` 的方式调用，接受两个命令行参数：
#   ARGS[1] — 序列化为 JSON 的 TaskRequest
#   ARGS[2] — 仓库根目录路径（用于定位包与诊断代码）
# 输出：单行 JSON 到 stdout，由 Runtime 解析为 JuliaEnvelope。
# ==============================================================================

using JSON3
using MetricaBase
using MetricaData
using MetricaDiscrete
using MetricaCausal
using MetricaLinear
using MetricaOutput
using MetricaPanel
using MetricaSurvey
using MetricaTimeSeries

include(joinpath(String(ARGS[2]), "packages", "MetricaDiagnostics.jl", "src", "MetricaDiagnostics.jl"))
using .MetricaDiagnostics

request = JSON3.read(ARGS[1])
action = String(request.action)
dataset_path = String(request.dataset_ref.path)

function present(value)
    return !isnothing(value) && !isempty(String(value))
end

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

    if model_type in ("arima", "var", "unitroot", "cointegration")
        # 时间序列模型：构造结构体 + DataFrame 拟合
        using CSV, DataFrames
        data = CSV.read(dataset_path, DataFrame)
        time_col = Symbol(String(get(request.model_spec, :time_column, "time")))
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment

        if model_type == "arima"
            var_sym = Symbol(String(get(request.model_spec, :variable, first(names(data)))))
            order_arr = get(request.model_spec, :order, [1, 1, 0])
            order_tuple = Tuple(Int.(collect(order_arr)))
            seasonal_arr = get(request.model_spec, :seasonal_order, [0, 0, 0, 0])
            seasonal_tuple = Tuple(Int.(collect(seasonal_arr)))
            ts_method = Symbol(String(get(request.model_spec, :ts_method, "mle")))
            model = ARIMAModel(
                variable=var_sym,
                time_column=time_col,
                order=order_tuple,
                seasonal_order=seasonal_tuple,
                method=ts_method,
            )
        elseif model_type == "var"
            vars_raw = collect(get(request.model_spec, :variables, String[]))
            var_syms = Symbol.(String.(vars_raw))
            lags = Int(get(request.model_spec, :lags, 1))
            model = VARModel(
                variables=var_syms,
                time_column=time_col,
                lags=lags,
            )
        elseif model_type == "unitroot"
            var_sym = Symbol(String(get(request.model_spec, :variable, first(names(data)))))
            det = Symbol(String(get(request.model_spec, :deterministic, "constant")))
            lags_val = Int(get(request.model_spec, :lags, 0))
            model = UnitRootModel(
                variable=var_sym,
                time_column=time_col,
                deterministic=det,
                max_lags=lags_val,
            )
        else  # cointegration
            vars_raw = collect(get(request.model_spec, :variables, String[]))
            var_syms = Symbol.(String.(vars_raw))
            method_sym = Symbol(String(get(request.model_spec, :ts_method, "engle_granger")))
            lags = Int(get(request.model_spec, :lags, 1))
            det = Symbol(String(get(request.model_spec, :deterministic, "constant")))
            model = CointegrationModel(
                variables=var_syms,
                time_column=time_col,
                method=method_sym,
                lags=lags,
                deterministic=det,
            )
        end

        result = MetricaBase.fit(model, data)
        MetricaTimeSeries.result_to_payload(result; include_augment=include_augment)
    elseif model_type in ("panel", "panel_iv")
        # 面板模型拟合
        panel_id = Symbol(String(request.model_spec.panel_id))
        panel_time = Symbol(String(request.model_spec.panel_time))
        panel_method = model_type == "panel_iv" ? :panel_iv : Symbol(String(get(request.model_spec, :panel_method, "fe")))

        # 加载数据并构造 PanelData
        using CSV, DataFrames
        df = CSV.read(dataset_path, DataFrame)
        panel_data = MetricaBase.PanelData(df, panel_id, panel_time)

        result = if model_type == "panel_iv"
            MetricaPanel.fit_panel_iv(
                panel_data,
                formula;
                instruments=String.(collect(request.model_spec.instruments)),
                endog=String.(collect(request.model_spec.endog_columns)),
            )
        else
            fit_panel(panel_data, formula; method=panel_method)
        end
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        _payload = MetricaPanel.result_to_payload(result; include_augment=include_augment)
        if model_type == "panel"
            _payload["result_payload"]["diagnostics"] = panel_diagnostics(panel_data, formula)
        end
        _payload
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
        MetricaSurvey.result_to_payload(result; include_augment=include_augment)
    else
        # 通过 MODEL_REGISTRY 统一派发
        kwargs = Dict{Symbol, Any}()
        vcov_type = haskey(request.model_spec, :vcov) ? String(request.model_spec.vcov.type) : "classical"
        vcov_key = lowercase(vcov_type)
        vcov_symbol = vcov_key == "hc1" ? :HC1 : vcov_key == "cluster" ? :cluster : :classical
        kwargs[:vcov] = vcov_symbol
        if haskey(request.model_spec, :weights) && !isnothing(request.model_spec.weights) && !isempty(request.model_spec.weights)
            kwargs[:weights] = Symbol(String(request.model_spec.weights))
        end
        if haskey(request.model_spec, :cluster_column) && !isnothing(request.model_spec.cluster_column) && !isempty(request.model_spec.cluster_column)
            kwargs[:cluster_column] = Symbol(String(request.model_spec.cluster_column))
        end
        if haskey(request.model_spec, :treatment_column) && present(request.model_spec.treatment_column)
            kwargs[:treatment_column] = Symbol(String(request.model_spec.treatment_column))
        end
        if haskey(request.model_spec, :outcome_column) && present(request.model_spec.outcome_column)
            kwargs[:outcome_column] = Symbol(String(request.model_spec.outcome_column))
        end
        if haskey(request.model_spec, :propensity_formula) && present(request.model_spec.propensity_formula)
            kwargs[:propensity_formula] = String(request.model_spec.propensity_formula)
        end
        if haskey(request.model_spec, :outcome_formula) && present(request.model_spec.outcome_formula)
            kwargs[:outcome_formula] = String(request.model_spec.outcome_formula)
        end
        ModelT = MetricaBase.MODEL_REGISTRY[model_type]
        result = MetricaBase.fit(ModelT, formula, dataset_path; kwargs...)
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        _payload = if result isa MetricaCausal.AbstractCausalFitResult
            MetricaCausal.result_to_payload(result; include_augment=include_augment)
        elseif result isa MetricaDiscrete.AbstractDiscreteFitResult
            MetricaDiscrete.result_to_payload(result; include_augment=include_augment)
        else
            MetricaLinear.result_to_payload(result; include_augment=include_augment)
        end
        if result isa MetricaLinear.OLSFitResult
            _payload["result_payload"]["diagnostics"] = diagnostics_to_dict(result)
        end
        _payload
    end
end
println(JSON3.write(payload))
