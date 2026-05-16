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
using MetricaGMM
using MetricaQuantile
using MetricaNonlinear
using MetricaOutput
using MetricaPanel
using MetricaSpatial
using MetricaDuration
using MetricaSurvey
using MetricaSystem
using MetricaTimeSeries

# 通过环境依赖加载，确保 `Distributions` 等传递依赖在 LOAD_PATH 中可用。
using MetricaDiagnostics

# Runtime 通过 `julia -e '...'` 内联本脚本时，`@__DIR__` 为进程 cwd（常为 `runtime/metrica-runtime`），
# 不能用于定位 `scripts/daemon`。优先使用第二参数（仓库根）；否则回退为「本文件所在目录的上一级」。
const METRICA_REPO_ROOT = let
    root = if length(ARGS) >= 2
        s = String(ARGS[2])
        !isempty(strip(s)) ? s : nothing
    else
        nothing
    end
    if root !== nothing
        root
    else
        cand = abspath(joinpath(@__DIR__, ".."))
        isfile(joinpath(cand, "AGENTS.md")) ||
            error("无法解析 Metrica 仓库根目录：Runtime 桥接应传入第二参数（仓库根）。")
        cand
    end
end

# 加载共享工具模块
include(joinpath(METRICA_REPO_ROOT, "scripts", "daemon", "src", "MetricaDaemon.jl"))
using .MetricaDaemon

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
        "messages" => Any[],
        "result_payload" => Dict(
            "content" => content,
            "format" => format,
        ),
        "artifacts" => Any[],
    )
else
    formula = String(request.model_spec.formula)
    model_type = String(request.model_spec.model_type)

    if model_type in ("arima", "var", "unitroot", "cointegration", "arch", "garch")
        # 时间序列模型：构造结构体 + DataFrame 拟合
        using CSV, DataFrames
        data = CSV.read(dataset_path, DataFrame)
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment

        # 将 JSON3 对象转换为 Dict 供 build_time_series_model 使用
        params = Dict{String, Any}()
        for key in keys(request.model_spec)
            params[String(key)] = request.model_spec[key]
        end
        model = MetricaTimeSeries.build_time_series_model(model_type, params)

        result = MetricaBase.fit(model, data)
        runtime_fit_envelope(MetricaTimeSeries.result_to_payload(result; include_augment=include_augment))
    elseif model_type in ("panel", "panel_iv", "dynamic_panel_gmm")
        # 面板模型拟合（含差分动态面板 GMM）
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
        elseif model_type == "dynamic_panel_gmm"
            raw_il = get(request.model_spec, :instrument_lags, Any[2, 4])
            il = (Int(raw_il[1]), Int(raw_il[2]))
            collapse = Bool(get(request.model_spec, :collapse_instruments, false))
            dpstyle = String(get(request.model_spec, :dpgmm_style, "difference"))
            gw = String(get(request.model_spec, :gmm_weight, "two_step"))
            MetricaBase.fit(
                DynamicPanelGMMModel,
                formula,
                dataset_path;
                panel_id=panel_id,
                panel_time=panel_time,
                instrument_lags=il,
                gmm_weight=gw,
                dpgmm_style=dpstyle,
                collapse_instruments=collapse,
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
    elseif model_type in ("spatial_lag", "spatial_error", "spatial_slx")
        using CSV, DataFrames
        df = CSV.read(dataset_path, DataFrame)
        wd = ""
        if haskey(request, :project_context) && !isnothing(request.project_context)
            pc = request.project_context
            if haskey(pc, :working_dir) && !isnothing(pc.working_dir)
                wd = String(pc.working_dir)
            end
        end
        spec = Dict{String, Any}(
            "spatial_weights_path" => String(request.model_spec.spatial_weights_path),
            "spatial_id_column" => String(request.model_spec.spatial_id_column),
        )
        if haskey(request.model_spec, :spatial_row_standardize) && !isnothing(request.model_spec.spatial_row_standardize)
            spec["spatial_row_standardize"] = Bool(request.model_spec.spatial_row_standardize)
        end
        if haskey(request.model_spec, :vcov) && !isnothing(request.model_spec.vcov) && haskey(request.model_spec.vcov, :type) && !isnothing(request.model_spec.vcov.type)
            spec["vcov"] = String(request.model_spec.vcov.type)
        end
        result = MetricaSpatial.fit_spatial(model_type, formula, df, spec, wd)
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        if result isa MetricaBase.ModelError
            MetricaLinear.error_to_payload(result)
        else
            MetricaSpatial.result_to_payload(result; include_augment=include_augment)
        end
    elseif model_type == "duration_cox"
        using CSV, DataFrames
        df = CSV.read(dataset_path, DataFrame)
        tc = String(request.model_spec.duration_time_column)
        ec = String(request.model_spec.duration_event_column)
        result = MetricaDuration.fit_duration_cox(df, formula, tc, ec)
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        if result isa MetricaBase.ModelError
            MetricaDuration.error_to_payload(result)
        else
            MetricaDuration.result_to_payload(result; include_augment=include_augment)
        end
    else
        # 通过 MODEL_REGISTRY 统一派发
        kwargs = Dict{Symbol, Any}()
        # IPW / AIPW / PSM 的 fit 不接受 vcov、weights、cluster 等线性族关键字，避免 MethodError。
        if !(model_type in ("ipw", "aipw", "psm", "gmm_linear", "dynamic_panel_gmm", "sur", "system_2sls", "system_3sls", "quantile", "nls", "threshold"))
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
        if model_type in ("iv", "gmm_linear")
            kwargs[:instruments] = String.(collect(request.model_spec.instruments))
            kwargs[:endog] = String.(collect(request.model_spec.endog_columns))
        end
        if model_type == "gmm_linear"
            gw = haskey(request.model_spec, :gmm_weight) && !isnothing(request.model_spec.gmm_weight) ?
                 String(request.model_spec.gmm_weight) : "two_step"
            kwargs[:gmm_weight] = gw
        end
        if model_type == "quantile"
            τ = if haskey(request.model_spec, :quantile_tau) && !isnothing(request.model_spec.quantile_tau)
                Float64(request.model_spec.quantile_tau)
            else
                0.5
            end
            kwargs[:quantile_tau] = τ
        end
        if model_type == "nls"
            fam = if haskey(request.model_spec, :nls_family) && !isnothing(request.model_spec.nls_family)
                String(request.model_spec.nls_family)
            else
                "exp_growth"
            end
            kwargs[:nls_family] = fam
            raw_start = request.model_spec.nls_start
            kwargs[:nls_start] = Float64.(collect(raw_start))
            if haskey(request.model_spec, :nls_max_iter) && !isnothing(request.model_spec.nls_max_iter)
                kwargs[:nls_max_iter] = Int(request.model_spec.nls_max_iter)
            end
            if haskey(request.model_spec, :nls_tol) && !isnothing(request.model_spec.nls_tol)
                kwargs[:nls_tol] = Float64(request.model_spec.nls_tol)
            end
        end
        if model_type == "threshold"
            kwargs[:threshold_variable] = String(request.model_spec.threshold_variable)
            kwargs[:threshold_grid] = Float64.(collect(request.model_spec.threshold_grid))
            if haskey(request.model_spec, :threshold_trim_frac) && !isnothing(request.model_spec.threshold_trim_frac)
                kwargs[:threshold_trim_frac] = Float64(request.model_spec.threshold_trim_frac)
            end
        end
        if model_type in ("sur", "system_2sls", "system_3sls")
            raw_eq = get(request.model_spec, :equations, nothing)
            kwargs[:equations] = raw_eq === nothing ? String[] : String.(collect(raw_eq))
            if model_type != "sur"
                raw_se = get(request.model_spec, :system_endogenous, nothing)
                raw_si = get(request.model_spec, :system_instruments, nothing)
                kwargs[:system_endogenous] = [
                    String.(collect(row)) for row in (raw_se === nothing ? [] : collect(raw_se))
                ]
                kwargs[:system_instruments] = [
                    String.(collect(row)) for row in (raw_si === nothing ? [] : collect(raw_si))
                ]
            end
            if model_type == "sur"
                if haskey(request.model_spec, :sur_max_iter) && !isnothing(request.model_spec.sur_max_iter)
                    kwargs[:sur_max_iter] = Int(request.model_spec.sur_max_iter)
                end
                if haskey(request.model_spec, :sur_tol) && !isnothing(request.model_spec.sur_tol)
                    kwargs[:sur_tol] = Float64(request.model_spec.sur_tol)
                end
            end
        end
        ModelT = MetricaBase.MODEL_REGISTRY[model_type]
        result = MetricaBase.fit(ModelT, formula, dataset_path; kwargs...)
        include_augment = haskey(request.options, :return_augment) && request.options.return_augment
        _payload = if result isa MetricaCausal.AbstractCausalFitResult
            MetricaCausal.result_to_payload(result; include_augment=include_augment)
        elseif result isa MetricaDiscrete.AbstractDiscreteFitResult
            MetricaDiscrete.result_to_payload(result; include_augment=include_augment)
        elseif result isa MetricaGMM.GMMLinearFitResult
            MetricaGMM.result_to_payload(result; include_augment=include_augment)
        elseif result isa MetricaQuantile.QuantileFitResult
            MetricaQuantile.result_to_payload(result; include_augment=include_augment)
        elseif result isa MetricaNonlinear.NLSFitResult || result isa MetricaNonlinear.ThresholdFitResult
            MetricaNonlinear.result_to_payload(result; include_augment=include_augment)
        elseif result isa MetricaSystem.SystemEquationsFitResult
            MetricaSystem.result_to_payload(result; include_augment=include_augment)
        else
            MetricaLinear.result_to_payload(result; include_augment=include_augment)
        end
        if result isa MetricaLinear.OLSFitResult
            _payload["result_payload"]["diagnostics"] = diagnostics_to_dict(result)
        end
        _payload
    end
end
println(JSON3.write(sanitize_json_floats(payload)))
