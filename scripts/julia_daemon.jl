# === Metrica Julia 守护进程 ====================================================
# 持久化进程，通过 stdin/stdout JSON lines 与 Runtime 通信。
#
# 协议（每行一个完整 JSON 对象）：
#   stdin:  {"id":"<请求标识>","action":"fit_model|inspect_dataset|query_dataset|transform|shutdown","params":{...}}
#   stdout: {"id":"<匹配请求标识>","status":"success|error","payload":{...}}
#   stdout: {"type":"ready"}  （启动就绪信号）
#   stdout: {"type":"error","text":"..."}  （非请求关联错误，如 JSON 解析失败）
# ==============================================================================

using JSON3
using CSV
using DataFrames
using MetricaBase
using MetricaLinear
using MetricaOutput
using MetricaDiscrete
using MetricaCausal
using MetricaDiagnostics
using MetricaPanel
using MetricaData
using MetricaSurvey
using MetricaTimeSeries
using LinearAlgebra: I

# 与桥接脚本一致：非有限浮点数序列化为 null，满足 JSON 规范。
function sanitize_json_floats(x::AbstractFloat)
    return isfinite(x) ? x : nothing
end
sanitize_json_floats(x::Integer) = x
sanitize_json_floats(x::Bool) = x
sanitize_json_floats(x::AbstractString) = x
sanitize_json_floats(::Nothing) = nothing
function sanitize_json_floats(x::AbstractDict)
    Dict(k => sanitize_json_floats(v) for (k, v) in pairs(x))
end
function sanitize_json_floats(x::AbstractVector)
    map(sanitize_json_floats, x)
end
sanitize_json_floats(x) = x

function runtime_fit_envelope(result_payload::AbstractDict)
    Dict{String, Any}(
        "status" => "success",
        "messages" => Any[],
        "result_payload" => result_payload,
        "artifacts" => Any[],
    )
end

function handle_request(req::Dict{String, Any})
    id = get(req, "id", nothing)
    payload = nothing

    try
        if !haskey(req, "action")
            println(JSON3.write(Dict("type" => "error", "id" => id, "text" => "请求缺少必需字段：action")))
            flush(stdout)
            return
        end
        if !haskey(req, "params")
            println(JSON3.write(Dict("type" => "error", "id" => id, "text" => "请求缺少必需字段：params")))
            flush(stdout)
            return
        end
        action = req["action"]
        params = req["params"]
        if action == "inspect_dataset"
            preview_rows = Int(get(params, "preview_rows", 5))
            payload = MetricaLinear.inspect_dataset(params["dataset_path"]; preview_limit=preview_rows)
        elseif action == "query_dataset"
            kind = String(get(params, "kind", ""))
            raw_variables = get(params, "variables", nothing)
            variables = isnothing(raw_variables) ? nothing : String.(collect(raw_variables))
            raw_limit = get(params, "limit", nothing)
            limit = isnothing(raw_limit) ? 200 : Int(raw_limit)

            if kind == "describe"
                payload = MetricaData.describe_dataset(params["dataset_path"]; variables = variables)
            elseif kind == "summarize"
                payload = MetricaData.summarize_dataset(params["dataset_path"]; variables = variables)
            elseif kind == "tabulate"
                variable = isnothing(variables) || isempty(variables) ? "" : first(variables)
                payload = MetricaData.tabulate_dataset(params["dataset_path"]; variable = variable, max_levels = limit)
            elseif kind == "browse"
                payload = MetricaData.browse_dataset(params["dataset_path"]; variables = variables)
            else
                payload = Dict(
                    "status" => "error",
                    "messages" => Any[Dict(
                        "level" => "error",
                        "code" => "unsupported_data_command",
                        "text" => "不支持的数据查看命令：$(kind)",
                        "hint" => "当前仅支持 describe、browse、summarize、tabulate。",
                    )],
                )
            end
        elseif action == "transform"
            dataset_path = params["dataset_path"]
            operations = JSON3.read(params["operations"], Vector{Dict{String, Any}})
            preview_rows = Int(get(params, "preview_rows", 10))
            output_path = get(params, "persist_output", true) ? get(params, "output_path", nothing) : nothing
            df = CSV.read(dataset_path, DataFrame)
            result = MetricaData.operate_chain(df, operations; output_path=output_path, preview_rows=preview_rows)
            payload = Dict(
                "status" => result["status"] == "error" ? "error" : "success",
                "result_payload" => result,
                "messages" => result["status"] == "error" ? [Dict(
                    "level" => "error",
                    "code" => "DATA_TRANSFORM_FAILED",
                    "text" => get(get(result, "error", Dict{String, Any}()), "message", "数据操作失败。"),
                    "hint" => "请检查失败步骤的参数、列名和表达式。",
                )] : [],
            )
        elseif action == "fit_model"
            dataset_path = params["dataset_path"]
            formula = params["formula"]
            model_type = get(params, "model_type", "ols")
            include_augment = get(params, "return_augment", false)

            if model_type in ("arima", "var", "unitroot", "cointegration")
                # 时间序列不在 MODEL_REGISTRY 中，必须先于注册表分支处理。
                data = CSV.read(dataset_path, DataFrame)
                time_col = Symbol(get(params, "time_column", "time"))

                if model_type == "arima"
                    var_sym = Symbol(get(params, "variable", first(names(data))))
                    order_arr = get(params, "order", [1, 1, 0])
                    length(order_arr) == 3 || error("order must have 3 elements [p, d, q]")
                    order_tuple = Tuple(Int.(order_arr))
                    seasonal_arr = get(params, "seasonal_order", [0, 0, 0, 0])
                    length(seasonal_arr) == 4 || error("seasonal_order must have 4 elements [P, D, Q, S]")
                    seasonal_tuple = Tuple(Int.(seasonal_arr))
                    ts_method = Symbol(get(params, "ts_method", "mle"))
                    model = ARIMAModel(
                        variable=var_sym,
                        time_column=time_col,
                        order=order_tuple,
                        seasonal_order=seasonal_tuple,
                        method=ts_method,
                    )
                elseif model_type == "var"
                    vars_raw = get(params, "variables", String[])
                    var_syms = Symbol.(String.(vars_raw))
                    lags = Int(get(params, "lags", 1))
                    model = VARModel(
                        variables=var_syms,
                        time_column=time_col,
                        lags=lags,
                    )
                elseif model_type == "unitroot"
                    var_sym = Symbol(get(params, "variable", first(names(data))))
                    det = Symbol(get(params, "deterministic", "constant"))
                    lags_val = Int(get(params, "lags", 0))
                    model = UnitRootModel(
                        variable=var_sym,
                        time_column=time_col,
                        deterministic=det,
                        max_lags=lags_val,
                    )
                else  # cointegration
                    vars_raw = get(params, "variables", String[])
                    var_syms = Symbol.(String.(vars_raw))
                    method_sym = Symbol(get(params, "ts_method", "engle_granger"))
                    lags = Int(get(params, "lags", 1))
                    det = Symbol(get(params, "deterministic", "constant"))
                    model = CointegrationModel(
                        variables=var_syms,
                        time_column=time_col,
                        method=method_sym,
                        lags=lags,
                        deterministic=det,
                    )
                end

                result = MetricaBase.fit(model, data)
                payload = runtime_fit_envelope(
                    MetricaTimeSeries.result_to_payload(result; include_augment=include_augment),
                )
            elseif haskey(MetricaBase.MODEL_REGISTRY, model_type)
                ModelT = MetricaBase.MODEL_REGISTRY[model_type]

                # 构造 kwargs
                kwargs = Dict{Symbol, Any}()
                # IPW / AIPW / PSM 的 fit 不接受 vcov、weights、cluster 等线性族关键字。
                if !(model_type in ("ipw", "aipw", "psm"))
                    vcov_type = get(params, "vcov", "classical")
                    vcov_key = lowercase(String(vcov_type))
                    vcov_symbol = vcov_key == "hc1" ? :HC1 : vcov_key == "cluster" ? :cluster : :classical
                    kwargs[:vcov] = vcov_symbol
                    weights = get(params, "weights", nothing)
                    if !isnothing(weights) && !isempty(weights); kwargs[:weights] = Symbol(weights); end
                    cluster_col = get(params, "cluster_column", nothing)
                    if !isnothing(cluster_col) && !isempty(cluster_col); kwargs[:cluster_column] = Symbol(cluster_col); end
                end

                # 面板特有参数
                if model_type in ("panel", "panel_iv", "did", "event_study")
                    kwargs[:panel_id] = Symbol(params["panel_id"])
                    kwargs[:panel_time] = Symbol(params["panel_time"])
                    kwargs[:panel_method] = Symbol(get(params, "panel_method", "fe"))
                    if haskey(params, "fe_spec")
                        kwargs[:fe_spec] = Symbol.(params["fe_spec"])
                    end
                end

                # IV 特有参数
                if model_type == "iv"
                    kwargs[:instruments] = String.(params["instruments"])
                    kwargs[:endog] = String.(params["endog_columns"])
                elseif model_type == "panel_iv"
                    kwargs[:instruments] = String.(params["instruments"])
                    kwargs[:endog] = String.(params["endog_columns"])
                elseif model_type == "gls"
                    kwargs[:omega_fn] = r -> Matrix{Float64}(I, length(r), length(r))
                end

                # S4b Causal 特有参数
                if haskey(params, "treated_column")
                    kwargs[:treated_column] = Symbol(params["treated_column"])
                end
                if haskey(params, "post_column")
                    kwargs[:post_column] = Symbol(params["post_column"])
                end
                if haskey(params, "event_time_column")
                    kwargs[:event_time_column] = Symbol(params["event_time_column"])
                end
                if haskey(params, "treatment_column")
                    kwargs[:treatment_column] = Symbol(params["treatment_column"])
                end
                if haskey(params, "outcome_column")
                    kwargs[:outcome_column] = Symbol(params["outcome_column"])
                end
                if haskey(params, "propensity_formula")
                    kwargs[:propensity_formula] = String(params["propensity_formula"])
                end
                if haskey(params, "outcome_formula")
                    kwargs[:outcome_formula] = String(params["outcome_formula"])
                end

                # S4d Survey 特有参数
                if startswith(model_type, "survey_")
                    kwargs[:weights_column] = Symbol(params["weights_column"])
                    if haskey(params, "strata_column") && !isempty(get(params, "strata_column", ""))
                        kwargs[:strata_column] = Symbol(params["strata_column"])
                    end
                    if haskey(params, "psu_column") && !isempty(get(params, "psu_column", ""))
                        kwargs[:psu_column] = Symbol(params["psu_column"])
                    end
                    if haskey(params, "fpc_column") && !isempty(get(params, "fpc_column", ""))
                        kwargs[:fpc_column] = Symbol(params["fpc_column"])
                    end
                end

                result = MetricaBase.fit(ModelT, formula, dataset_path; kwargs...)

                # 分派 result_to_payload
                if result isa MetricaCausal.AbstractCausalFitResult
                    payload = MetricaCausal.result_to_payload(result; include_augment=include_augment)
                elseif result isa MetricaDiscrete.AbstractDiscreteFitResult
                    payload = MetricaDiscrete.result_to_payload(result; include_augment=include_augment)
                elseif result isa MetricaSurvey.AbstractSurveyFitResult
                    payload = MetricaSurvey.result_to_payload(result; include_augment=include_augment)
                elseif model_type in ("panel", "panel_iv")
                    payload = MetricaPanel.result_to_payload(result; include_augment=include_augment)
                else
                    payload = MetricaLinear.result_to_payload(result; include_augment=include_augment)
                end
            else
                payload = Dict(
                    "status" => "error",
                    "messages" => [Dict(
                        "level" => "error",
                        "code" => "UNKNOWN_MODEL_TYPE",
                        "text" => "未知的模型类型：$model_type",
                        "hint" => "当前支持：$(collect(keys(MetricaBase.MODEL_REGISTRY)))",
                    )],
                )
            end
        elseif action == "export_report"
            format = get(params, "format", "markdown")
            run_record = get(params, "run_record", Dict{String, Any}())
            result = get(params, "result", Dict{String, Any}())

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

            payload = Dict(
                "status" => "success",
                "messages" => Any[],
                "result_payload" => Dict(
                    "content" => content,
                    "format" => format,
                ),
                "artifacts" => Any[],
            )
        elseif action == "run_diagnostic"
            dataset_path = params["dataset_path"]
            formula = params["formula"]
            model_type = get(params, "model_type", "ols")
            test_name = get(params, "test", "")
            lags = get(params, "lags", nothing)

            if !haskey(MetricaBase.MODEL_REGISTRY, model_type)
                payload = Dict(
                    "status" => "error",
                    "messages" => [Dict(
                        "level" => "error",
                        "code" => "UNKNOWN_MODEL_TYPE",
                        "text" => "诊断要求的模型类型未知：$model_type",
                    )],
                )
            else
                ModelT = MetricaBase.MODEL_REGISTRY[model_type]
                vcov_type = get(params, "vcov", "classical")
                vcov_key = lowercase(String(vcov_type))
                vcov_symbol = vcov_key == "hc1" ? :HC1 : vcov_key == "cluster" ? :cluster : :classical
                result = MetricaBase.fit(ModelT, formula, dataset_path; vcov=vcov_symbol)

                X = MetricaBase.design_matrix(result)
                if isnothing(X)
                    payload = Dict(
                        "status" => "error",
                        "messages" => [Dict(
                            "level" => "error",
                            "code" => "DIAGNOSTIC_REQUIRES_DESIGN_MATRIX",
                            "text" => "该模型类型不支持诊断检验（缺少设计矩阵）。",
                            "hint" => "当前诊断检验需要模型提供设计矩阵，请使用 OLS 等线性模型。",
                        )],
                    )
                else
                    diag = if test_name == "bp"
                        bp = MetricaDiagnostics.breusch_pagan(result)
                        Dict(
                            "test" => "bp",
                            "statistic" => bp.statistic,
                            "pvalue" => bp.pvalue,
                            "dof" => bp.dof,
                            "interpretation" => bp.pvalue < 0.05 ? "拒绝原假设（存在异方差）" : "不拒绝原假设（无异方差证据）",
                        )
                    elseif test_name == "bg"
                        p = isnothing(lags) ? 2 : round(Int, Float64(lags))
                        bg = MetricaDiagnostics.breusch_godfrey(result; p=p)
                        Dict(
                            "test" => "bg",
                            "statistic" => bg.statistic,
                            "pvalue" => bg.pvalue,
                            "dof" => bg.dof,
                            "interpretation" => bg.pvalue < 0.05 ? "拒绝原假设（存在自相关）" : "不拒绝原假设（无自相关证据）",
                        )
                    elseif test_name == "reset"
                        reset = MetricaDiagnostics.reset_test(result)
                        Dict(
                            "test" => "reset",
                            "statistic" => reset.statistic,
                            "pvalue" => reset.pvalue,
                            "df_num" => reset.df_num,
                            "df_den" => reset.df_den,
                            "interpretation" => reset.pvalue < 0.05 ? "拒绝原假设（模型设定可能有误）" : "不拒绝原假设（无设定偏误证据）",
                        )
                    elseif test_name == "jb"
                        jb = MetricaDiagnostics.jarque_bera(result)
                        Dict(
                            "test" => "jb",
                            "statistic" => jb.statistic,
                            "pvalue" => jb.pvalue,
                            "skewness" => jb.skewness,
                            "kurtosis" => jb.kurtosis,
                            "interpretation" => jb.pvalue < 0.05 ? "拒绝原假设（残差非正态）" : "不拒绝原假设（残差近似正态）",
                        )
                    elseif test_name == "dw"
                        dw = MetricaDiagnostics.durbin_watson(result)
                        Dict(
                            "test" => "dw",
                            "statistic" => dw.statistic,
                            "pvalue" => dw.pvalue,
                            "interpretation" => isnothing(dw.pvalue) ? "样本量不足，无法判断" :
                                dw.pvalue < 0.05 ? "存在一阶自相关" : "无一阶自相关证据",
                        )
                    elseif test_name == "white"
                        white = MetricaDiagnostics.white_test(result)
                        Dict(
                            "test" => "white",
                            "statistic" => white.statistic,
                            "pvalue" => white.pvalue,
                            "dof" => white.dof,
                            "interpretation" => white.pvalue < 0.05 ? "拒绝原假设（存在异方差）" : "不拒绝原假设（无异方差证据）",
                        )
                    elseif test_name == "vif"
                        vif_results = MetricaDiagnostics.vif(result)
                        Dict(
                            "test" => "vif",
                            "vif" => [Dict("name" => row.name, "vif" => row.vif) for row in vif_results],
                            "interpretation" => "VIF > 10 表示严重多重共线性",
                        )
                    else
                        nothing
                    end

                    if isnothing(diag)
                        payload = Dict(
                            "status" => "error",
                            "messages" => [Dict(
                                "level" => "error",
                                "code" => "UNKNOWN_DIAGNOSTIC",
                                "text" => "未知的诊断检验：$test_name",
                                "hint" => "支持的检验：bp, bg, reset, jb, dw, white, vif",
                            )],
                        )
                    else
                        payload = Dict(
                            "status" => "success",
                            "result_payload" => diag,
                        )
                    end
                end
            end
        else
            payload = Dict(
                "status" => "error",
                "messages" => [Dict(
                    "level" => "error",
                    "code" => "UNKNOWN_ACTION",
                "text" => "守护进程不支持的动作：$action",
                "hint" => "当前支持 fit_model、inspect_dataset、query_dataset、transform、run_diagnostic 与 export_report。",
                )],
            )
        end
    catch err
        payload = Dict(
            "status" => "error",
            "messages" => [Dict(
                "level" => "error",
                "code" => "JULIA_INTERNAL_ERROR",
                "text" => "Julia 内部错误：$(sprint(showerror, err))",
                "hint" => "请检查请求参数与数据文件。",
            )],
        )
    end

    if isnothing(payload)
        payload = Dict(
            "status" => "error",
            "messages" => [Dict(
                "level" => "error",
                "code" => "JULIA_INTERNAL_ERROR",
                "text" => "守护进程未能生成响应载荷。",
                "hint" => nothing,
            )],
        )
    end

    payload["id"] = id
    println(JSON3.write(sanitize_json_floats(payload)))
    flush(stdout)
end

# === 启动就绪信号 ==============================================================

println(JSON3.write(Dict("type" => "ready")))
flush(stdout)

# === 主循环 ====================================================================

while !eof(stdin)
    line = readline(stdin; keep=false)
    isempty(strip(line)) && continue

    req = try
        JSON3.read(line, Dict{String, Any})
    catch err
        println(JSON3.write(Dict(
            "type" => "error",
            "text" => "JSON 解析失败：$(sprint(showerror, err))",
        )))
        flush(stdout)
        continue
    end

    if get(req, "action", "") == "shutdown"
        break
    end

    handle_request(req)
end
