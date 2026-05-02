# === Metrica Runtime Julia 桥接入口 ===========================================
# 本脚本由 Runtime 通过 `julia -e` 的方式调用，接受两个命令行参数：
#   ARGS[1] — 序列化为 JSON 的 TaskRequest
#   ARGS[2] — 仓库根目录路径（用于定位包与诊断代码）
# 输出：单行 JSON 到 stdout，由 Runtime 解析为 JuliaEnvelope。
# ==============================================================================

using JSON3
using MetricaBase
using MetricaLinear

include(joinpath(String(ARGS[2]), "packages", "MetricaDiagnostics.jl", "src", "MetricaDiagnostics.jl"))
using .MetricaDiagnostics

# 加载面板模块
include(joinpath(String(ARGS[2]), "packages", "MetricaPanel.jl", "src", "MetricaPanel.jl"))
using .MetricaPanel

request = JSON3.read(ARGS[1])
action = String(request.action)
dataset_path = String(request.dataset_ref.path)
payload = if action == "inspect_dataset"
    inspect_dataset(dataset_path)
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
    else
        # OLS/WLS 模型拟合
        vcov_type = String(request.model_spec.vcov.type)
        vcov_symbol = if vcov_type == "HC1"
            :HC1
        elseif vcov_type == "cluster"
            :cluster
        else
            :classical
        end
        has_weights = haskey(request.model_spec, :weights) && !isnothing(request.model_spec.weights)
        has_cluster = haskey(request.model_spec, :cluster_column) && !isnothing(request.model_spec.cluster_column)
        result = if has_weights && has_cluster
            fit_ols_file(dataset_path, formula; weights=Symbol(String(request.model_spec.weights)), vcov=vcov_symbol, cluster=Symbol(String(request.model_spec.cluster_column)))
        elseif has_weights
            fit_ols_file(dataset_path, formula; weights=Symbol(String(request.model_spec.weights)), vcov=vcov_symbol)
        elseif has_cluster
            fit_ols_file(dataset_path, formula; vcov=vcov_symbol, cluster=Symbol(String(request.model_spec.cluster_column)))
        else
            fit_ols_file(dataset_path, formula; vcov=vcov_symbol)
        end
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        payload = MetricaLinear.result_to_payload(result; include_augment=include_augment)
        if result isa OLSFitResult
            payload["result_payload"]["diagnostics"] = diagnostics_to_dict(result)
        end
        payload
    end
end
println(JSON3.write(payload))
