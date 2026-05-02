# === Metrica Julia 守护进程 ====================================================
# 持久化进程，通过 stdin/stdout JSON lines 与 Runtime 通信。
#
# 启动方式：
#   METRICA_REPO_ROOT=/path/to/repo julia --project=packages/MetricaLinear.jl \
#       --startup-file=no --color=no scripts/julia_daemon.jl
#
# 协议（每行一个完整 JSON 对象）：
#   stdin:  {"id":"<请求标识>","action":"fit_model|inspect_dataset|transform|shutdown","params":{...}}
#   stdout: {"id":"<匹配请求标识>","status":"success|error","payload":{...}}
#   stdout: {"type":"ready"}  （启动就绪信号）
#   stdout: {"type":"error","text":"..."}  （非请求关联错误，如 JSON 解析失败）
# ==============================================================================

using JSON3
using CSV
using DataFrames
using MetricaBase
using MetricaLinear
using LinearAlgebra: I

include(joinpath(ENV["METRICA_REPO_ROOT"], "packages", "MetricaDiagnostics.jl", "src", "MetricaDiagnostics.jl"))
using .MetricaDiagnostics

# 加载面板模块
include(joinpath(ENV["METRICA_REPO_ROOT"], "packages", "MetricaPanel.jl", "src", "MetricaPanel.jl"))
using .MetricaPanel

# 加载数据操作模块
include(joinpath(ENV["METRICA_REPO_ROOT"], "packages", "MetricaData.jl", "src", "MetricaData.jl"))
using .MetricaData

function handle_request(req::Dict{String, Any})
    id = req["id"]
    action = req["action"]
    params = req["params"]
    payload = nothing

    try
        if action == "inspect_dataset"
            payload = inspect_dataset(params["dataset_path"])
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
            include_augment = get(params, "return_augment", true)

            if model_type == "panel"
                panel_id = Symbol(params["panel_id"])
                panel_time = Symbol(params["panel_time"])
                panel_method = Symbol(get(params, "panel_method", "fe"))

                df = CSV.read(dataset_path, DataFrame)
                panel_data = MetricaBase.PanelData(df, panel_id, panel_time)

                result = fit_panel(panel_data, formula; method=panel_method)
                payload = MetricaPanel.result_to_payload(result; include_augment=include_augment)
                payload["result_payload"]["diagnostics"] = panel_diagnostics(panel_data, formula)
            elseif model_type == "iv"
                instruments = String.(params["instruments"])
                endog_columns = String.(params["endog_columns"])
                vcov_type = params["vcov"]
                vcov_symbol = vcov_type == "HC1" ? :HC1 : vcov_type == "cluster" ? :cluster : :classical
                cluster_col = get(params, "cluster_column", nothing)
                cluster_sym = isnothing(cluster_col) || isempty(cluster_col) ? nothing : Symbol(cluster_col)

                result = fit(IVModel, formula, dataset_path;
                    instruments=instruments, endog=endog_columns,
                    vcov=vcov_symbol, cluster_column=cluster_sym)
                payload = result_to_payload(result; include_augment=include_augment)

            elseif model_type == "gls"
                omega_fn = r -> Matrix{Float64}(I, length(r), length(r))
                vcov_type = get(params, "vcov", "classical")
                vcov_symbol = vcov_type == "HC1" ? :HC1 : vcov_type == "cluster" ? :cluster : :classical

                result = fit(GLSModel, formula, dataset_path;
                    omega_fn=omega_fn, vcov=vcov_symbol)
                payload = result_to_payload(result; include_augment=include_augment)
            else
                vcov_type = params["vcov"]
                vcov_symbol = if vcov_type == "HC1"
                    :HC1
                elseif vcov_type == "cluster"
                    :cluster
                else
                    :classical
                end
                weights = get(params, "weights", nothing)
                weights_sym = isnothing(weights) || isempty(weights) ? nothing : Symbol(weights)
                cluster_col = get(params, "cluster_column", nothing)
                cluster_sym = isnothing(cluster_col) || isempty(cluster_col) ? nothing : Symbol(cluster_col)

                result = fit_ols_file(dataset_path, formula;
                    vcov=vcov_symbol,
                    weights=weights_sym,
                    cluster=cluster_sym,
                )

                payload = result_to_payload(result; include_augment=include_augment)
                if result isa OLSFitResult
                    payload["result_payload"]["diagnostics"] = diagnostics_to_dict(result)
                end
            end
        else
            payload = Dict(
                "status" => "error",
                "messages" => [Dict(
                    "level" => "error",
                    "code" => "UNKNOWN_ACTION",
                    "text" => "守护进程不支持的动作：$action",
                    "hint" => "当前仅支持 fit_model、inspect_dataset 与 transform。",
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
    println(JSON3.write(payload))
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
