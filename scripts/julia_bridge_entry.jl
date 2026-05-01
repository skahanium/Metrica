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
    white = white_test(result)
    dw = durbin_watson(result)
    bg = breusch_godfrey(result; p=2)
    reset = reset_test(result)
    jb = jarque_bera(result)

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
        "white_test" => Dict(
            "statistic" => white.statistic,
            "pvalue" => white.pvalue,
            "dof" => white.dof,
        ),
        "durbin_watson" => Dict(
            "statistic" => dw.statistic,
            "pvalue" => dw.pvalue,
        ),
        "breusch_godfrey" => Dict(
            "statistic" => bg.statistic,
            "pvalue" => bg.pvalue,
            "dof" => bg.dof,
        ),
        "reset_test" => Dict(
            "statistic" => reset.statistic,
            "pvalue" => reset.pvalue,
            "df_num" => reset.df_num,
            "df_den" => reset.df_den,
        ),
        "jarque_bera" => Dict(
            "statistic" => jb.statistic,
            "pvalue" => jb.pvalue,
            "skewness" => jb.skewness,
            "kurtosis" => jb.kurtosis,
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
    payload = result_to_payload(result)
    if result isa OLSFitResult
        payload["result_payload"]["diagnostics"] = diagnostics_to_dict(result)
    end
    payload
end
println(JSON3.write(payload))
