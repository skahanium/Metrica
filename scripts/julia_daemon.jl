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
using MetricaGMM
using MetricaQuantile
using MetricaNonlinear
using MetricaOutput
using MetricaDiscrete
using MetricaCausal
using MetricaDiagnostics
using MetricaPanel
using MetricaSpatial
using MetricaDuration
using MetricaBayes
using MetricaData
using MetricaSurvey
using MetricaSystem
using MetricaTimeSeries
using LinearAlgebra: I

# Runtime 通过环境变量 `METRICA_REPO_ROOT` 传入仓库根（见 `julia_session.rs`）。
# `julia -e` 内联执行时 `@__DIR__` 为进程 cwd，不可用于定位 `scripts/daemon`。
const METRICA_REPO_ROOT = let
    r = get(ENV, "METRICA_REPO_ROOT", "")
    root = !isempty(strip(r)) ? String(strip(r)) : nothing
    if root !== nothing
        root
    else
        cand = abspath(joinpath(@__DIR__, ".."))
        isfile(joinpath(cand, "AGENTS.md")) ||
            error("无法解析 Metrica 仓库根目录：请设置环境变量 METRICA_REPO_ROOT。")
        cand
    end
end

# 加载共享工具模块
include(joinpath(METRICA_REPO_ROOT, "scripts", "daemon", "src", "MetricaDaemon.jl"))
using .MetricaDaemon

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

            if model_type in ("arima", "var", "unitroot", "cointegration", "arch", "garch", "gjr_garch", "egarch")
                # 时间序列不在 MODEL_REGISTRY 中，必须先于注册表分支处理。
                data = CSV.read(dataset_path, DataFrame)
                model = MetricaTimeSeries.build_time_series_model(model_type, params)
                result = MetricaBase.fit(model, data)
                payload = runtime_fit_envelope(
                    MetricaTimeSeries.result_to_payload(result; include_augment=include_augment),
                )
            elseif model_type in ("spatial_lag", "spatial_error", "spatial_slx",
                                  "spatial_sdm", "spatial_sdem", "spatial_sac", "spatial_probit")
                data = CSV.read(dataset_path, DataFrame)
                wd = String(get(params, "working_dir", ""))
                spec = Dict{String, Any}(
                    "spatial_weights_path" => String(get(params, "spatial_weights_path", "")),
                    "spatial_id_column" => String(get(params, "spatial_id_column", "")),
                )
                if haskey(params, "spatial_row_standardize") && params["spatial_row_standardize"] !== nothing
                    spec["spatial_row_standardize"] = Bool(params["spatial_row_standardize"])
                end
                if haskey(params, "vcov") && params["vcov"] !== nothing
                    spec["vcov"] = String(params["vcov"])
                end
                result = MetricaSpatial.fit_spatial(model_type, formula, data, spec, wd)
                payload = if result isa MetricaBase.ModelError
                    MetricaSpatial.error_to_payload(result)
                else
                    MetricaSpatial.result_to_payload(result; include_augment=include_augment)
                end
            elseif model_type == "duration_cox"
                data = CSV.read(dataset_path, DataFrame)
                tc = String(get(params, "duration_time_column", ""))
                ec = String(get(params, "duration_event_column", ""))
                result = MetricaDuration.fit_duration_cox(data, formula, tc, ec)
                payload = if result isa MetricaBase.ModelError
                    MetricaDuration.error_to_payload(result)
                else
                    MetricaDuration.result_to_payload(result; include_augment=include_augment)
                end
            elseif model_type in ("aft_weibull", "aft_exponential", "aft_lognormal", "aft_loglogistic")
                data = CSV.read(dataset_path, DataFrame)
                tc = String(get(params, "duration_time_column", "time"))
                ec = String(get(params, "duration_event_column", "fail"))
                dist = model_type == "aft_weibull" ? "weibull" :
                       model_type == "aft_exponential" ? "exponential" :
                       model_type == "aft_lognormal" ? "lognormal" : "loglogistic"
                result = MetricaDuration.fit_aft(data, formula, tc, ec; dist=dist)
                include_augment = get(params, "return_augment", false)
                payload = if result isa MetricaBase.ModelError
                    MetricaDuration.error_to_payload(result)
                else
                    MetricaDuration.result_to_payload(result; include_augment=include_augment)
                end
            elseif model_type in ("bayes_linear", "bayes_logistic", "bayes_probit", "bayes_hierarchical")
                data = CSV.read(dataset_path, DataFrame)
                bayes_seed = get(params, "bayes_seed", nothing)
                result = if model_type == "bayes_linear"
                    MetricaBayes.fit_bayes_linear(data, formula;
                        bayes_seed=bayes_seed,
                        bayes_prior_scale=Float64(get(params, "bayes_prior_scale", 1.0)),
                        bayes_sigma2_known=Bool(get(params, "bayes_sigma2_known", false)),
                        bayes_sigma2_value=Float64(get(params, "bayes_sigma2_value", NaN)),
                        bayes_ig_alpha=Float64(get(params, "bayes_ig_alpha", 2.0)),
                        bayes_ig_beta=Float64(get(params, "bayes_ig_beta", 1.0)))
                elseif model_type == "bayes_logistic"
                    MetricaBayes.fit_bayes_logistic(data, formula;
                        bayes_seed=bayes_seed,
                        bayes_prior_scale=Float64(get(params, "bayes_prior_scale", 5.0)),
                        bayes_iter=Int(get(params, "bayes_iter", 3000)),
                        bayes_warmup=Int(get(params, "bayes_warmup", 750)),
                        bayes_chains=Int(get(params, "bayes_chains", 1)))
                elseif model_type == "bayes_probit"
                    MetricaBayes.fit_bayes_probit(data, formula;
                        bayes_seed=bayes_seed,
                        bayes_prior_scale=Float64(get(params, "bayes_prior_scale", 5.0)),
                        bayes_iter=Int(get(params, "bayes_iter", 3000)),
                        bayes_warmup=Int(get(params, "bayes_warmup", 750)),
                        bayes_chains=Int(get(params, "bayes_chains", 1)))
                else
                    group_col = String(get(params, "bayes_group_column", ""))
                    isempty(group_col) ? MetricaBase.ModelError(
                        :bayes_missing_group_column,
                        "层级贝叶斯模型需要 bayes_group_column",
                        "",
                        "请在 model_spec 中提供 bayes_group_column。",
                    ) : MetricaBayes.fit_bayes_hierarchical(data, formula, Symbol(group_col);
                        bayes_seed=bayes_seed,
                        bayes_prior_scale=Float64(get(params, "bayes_prior_scale", 10.0)),
                        bayes_iter=Int(get(params, "bayes_iter", 3000)),
                        bayes_warmup=Int(get(params, "bayes_warmup", 750)),
                        bayes_chains=Int(get(params, "bayes_chains", 1)))
                end
                include_augment = get(params, "return_augment", false)
                payload = if result isa MetricaBase.ModelError
                    MetricaBayes.error_to_payload(result)
                else
                    MetricaBayes.result_to_payload(result; include_augment=include_augment)
                end
            elseif haskey(MetricaBase.MODEL_REGISTRY, model_type)
                ModelT = MetricaBase.MODEL_REGISTRY[model_type]

                # 构造 kwargs
                kwargs = Dict{Symbol, Any}()
                # IPW / AIPW / PSM 的 fit 不接受 vcov、weights、cluster 等线性族关键字。
                if !(model_type in ("ipw", "aipw", "psm", "gmm_linear", "dynamic_panel_gmm", "sur", "system_2sls", "system_3sls", "quantile", "nls", "threshold"))
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
                if model_type in ("panel", "panel_iv", "did", "event_study", "dynamic_panel_gmm")
                    kwargs[:panel_id] = Symbol(params["panel_id"])
                    kwargs[:panel_time] = Symbol(params["panel_time"])
                    kwargs[:panel_method] = Symbol(get(params, "panel_method", "fe"))
                    if haskey(params, "fe_spec")
                        kwargs[:fe_spec] = Symbol.(params["fe_spec"])
                    end
                end

                # IV / GMM 特有参数
                if model_type in ("iv", "gmm_linear")
                    kwargs[:instruments] = String.(params["instruments"])
                    kwargs[:endog] = String.(params["endog_columns"])
                end
                if model_type == "gmm_linear"
                    kwargs[:gmm_weight] = String(get(params, "gmm_weight", "two_step"))
                end
                if model_type == "quantile"
                    kwargs[:quantile_tau] = Float64(get(params, "quantile_tau", 0.5))
                end
                if model_type == "nls"
                    kwargs[:nls_family] = String(get(params, "nls_family", "exp_growth"))
                    kwargs[:nls_start] = Float64.(collect(params["nls_start"]))
                    if haskey(params, "nls_max_iter") && params["nls_max_iter"] !== nothing
                        kwargs[:nls_max_iter] = Int(params["nls_max_iter"])
                    end
                    if haskey(params, "nls_tol") && params["nls_tol"] !== nothing
                        kwargs[:nls_tol] = Float64(params["nls_tol"])
                    end
                end
                if model_type == "threshold"
                    kwargs[:threshold_variable] = String(params["threshold_variable"])
                    kwargs[:threshold_grid] = Float64.(collect(params["threshold_grid"]))
                    if haskey(params, "threshold_trim_frac") && params["threshold_trim_frac"] !== nothing
                        kwargs[:threshold_trim_frac] = Float64(params["threshold_trim_frac"])
                    end
                end
                if model_type == "dynamic_panel_gmm"
                    raw_il = get(params, "instrument_lags", Any[2, 4])
                    kwargs[:instrument_lags] = (Int(raw_il[1]), Int(raw_il[2]))
                    kwargs[:gmm_weight] = String(get(params, "gmm_weight", "two_step"))
                    kwargs[:dpgmm_style] = String(get(params, "dpgmm_style", "difference"))
                    kwargs[:collapse_instruments] = Bool(get(params, "collapse_instruments", false))
                end
                if model_type == "panel_iv"
                    kwargs[:instruments] = String.(params["instruments"])
                    kwargs[:endog] = String.(params["endog_columns"])
                elseif model_type == "gls"
                    kwargs[:omega_fn] = function (residuals)
                        n = length(residuals)
                        Ω = zeros(Float64, n, n)
                        @inbounds for i in 1:n
                            Ω[i, i] = 1.0
                        end
                        return Ω
                    end
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

                if model_type in ("sur", "system_2sls", "system_3sls")
                    raw_eq = get(params, "equations", nothing)
                    kwargs[:equations] = raw_eq === nothing ? String[] : String.(collect(raw_eq))
                    if model_type != "sur"
                        raw_se = get(params, "system_endogenous", nothing)
                        raw_si = get(params, "system_instruments", nothing)
                        kwargs[:system_endogenous] = [
                            String.(collect(row)) for row in (raw_se === nothing ? [] : collect(raw_se))
                        ]
                        kwargs[:system_instruments] = [
                            String.(collect(row)) for row in (raw_si === nothing ? [] : collect(raw_si))
                        ]
                    end
                    if model_type == "sur"
                        if haskey(params, "sur_max_iter") && params["sur_max_iter"] !== nothing
                            kwargs[:sur_max_iter] = Int(params["sur_max_iter"])
                        end
                        if haskey(params, "sur_tol") && params["sur_tol"] !== nothing
                            kwargs[:sur_tol] = Float64(params["sur_tol"])
                        end
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
                elseif result isa MetricaGMM.GMMLinearFitResult
                    payload = MetricaGMM.result_to_payload(result; include_augment=include_augment)
                elseif result isa MetricaQuantile.QuantileFitResult
                    payload = MetricaQuantile.result_to_payload(result; include_augment=include_augment)
                elseif result isa MetricaNonlinear.NLSFitResult || result isa MetricaNonlinear.ThresholdFitResult
                    payload = MetricaNonlinear.result_to_payload(result; include_augment=include_augment)
                elseif result isa MetricaSystem.SystemEquationsFitResult
                    payload = MetricaSystem.result_to_payload(result; include_augment=include_augment)
                elseif result isa MetricaPanel.DynamicPanelGMMFitResult
                    payload = MetricaPanel.result_to_payload(result; include_augment=include_augment)
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
