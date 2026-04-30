# === Metrica Runtime Julia 桥接入口 ===========================================
# 本脚本由 Runtime 通过 `julia -e` 的方式调用，接受两个命令行参数：
#   ARGS[1] — 序列化为 JSON 的 TaskRequest
#   ARGS[2] — 仓库根目录路径（用于定位包与诊断代码）
# 输出：单行 JSON 到 stdout，由 Runtime 解析为 JuliaEnvelope。
# ==============================================================================

using JSON3
using MetricaLinear

include(joinpath(String(ARGS[2]), "packages", "MetricaTests.jl", "src", "MetricaTests.jl"))
using .MetricaTests

function diagnostics_to_dict(result)
    bp = breusch_pagan(result)
    return Dict(
        "vif" => [
            Dict(
                "name" => row.name,
                "vif" => row.vif,
            )
            for row in vif(result)
        ],
        "breusch_pagan" => Dict(
            "statistic" => bp.statistic,
            "pvalue" => bp.pvalue,
            "dof" => bp.dof,
        ),
    )
end

request = JSON3.read(ARGS[1])
action = String(request.action)
dataset_path = String(request.dataset_ref.path)
payload = if action == "inspect_dataset"
    inspect_dataset(dataset_path)
else
    formula = String(request.model_spec.formula)
    vcov_type = String(request.model_spec.vcov.type)
    vcov_symbol = vcov_type == "HC1" ? :HC1 : :classical
    has_weights = haskey(request.model_spec, :weights) && !isnothing(request.model_spec.weights)
    result = if has_weights
        fit_ols_file(dataset_path, formula; weights=Symbol(String(request.model_spec.weights)), vcov=vcov_symbol)
    else
        fit_ols_file(dataset_path, formula; vcov=vcov_symbol)
    end
    payload = result_to_payload(result)
    if result isa OLSFitResult
        payload["result_payload"]["diagnostics"] = diagnostics_to_dict(result)
    end
    payload
end
println(JSON3.write(payload))
