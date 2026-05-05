# cointegration.jl - 协整检验模块
# 实现 Engle-Granger 和 Johansen 协整检验

# === 类型定义 =============================================================

"""
    CointegrationModel <: AbstractTimeSeriesModel

协整检验模型规格。
"""
struct CointegrationModel <: AbstractTimeSeriesModel
    variables::Vector{Symbol}
    time_column::Symbol
    method::Symbol  # :engle_granger 或 :johansen
    lags::Int
    deterministic::Symbol  # :constant, :trend, :none
end

"""
    CointegrationFitResult <: AbstractTSFitResult

协整检验拟合结果。
"""
struct CointegrationFitResult <: AbstractTSFitResult
    variable_names::Vector{String}
    method::Symbol
    test_statistic::Float64
    p_value::Float64
    critical_values::Dict{Float64, Float64}
    cointegrating_vector::Union{Vector{Float64}, Nothing}
    n_cointegrating_relations::Int
    residuals::Union{Vector{Float64}, Nothing}
    eigenvalues::Union{Vector{Float64}, Nothing}
    trace_stats::Union{Vector{Float64}, Nothing}
    max_eigen_stats::Union{Vector{Float64}, Nothing}
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    warnings::Vector{MetricaBase.ModelWarning}
end

"""
    CointegrationModel(; variables, time_column, method=:engle_granger, lags=1, deterministic=:constant)

构造协整检验模型规格。
"""
function CointegrationModel(; variables::Vector{Symbol}, time_column::Symbol,
                           method::Symbol=:engle_granger, lags::Int=1,
                           deterministic::Symbol=:constant)
    if length(variables) < 2
        error("协整检验至少需要 2 个变量")
    end
    return CointegrationModel(variables, time_column, method, lags, deterministic)
end

# === Engle-Granger 检验 ===================================================

"""
    engle_granger_test(y, X; deterministic=:constant, lags=:auto) -> NamedTuple

Engle-Granger 两步法协整检验。
"""
function engle_granger_test(y::Vector{Float64}, X::Matrix{Float64};
                           deterministic::Symbol=:constant, lags=:auto)
    n = length(y)

    # 第一步：OLS 回归 y = Xβ + ε
    if deterministic === :constant
        X_aug = hcat(ones(n), X)
    elseif deterministic === :trend
        X_aug = hcat(ones(n), collect(1:n), X)
    else
        X_aug = X
    end

    beta = X_aug \ y
    residuals = y - X_aug * beta

    # 第二步：对残差进行 ADF 检验
    adf_result = adf_test(residuals, deterministic=deterministic, lag=lags)

    # Engle-Granger 临界值（MacKinnon 2010）
    n_vars = size(X, 2) + 1
    critical_values = if n_vars == 2
        Dict(0.01 => -3.90, 0.05 => -3.34, 0.10 => -3.04)
    elseif n_vars == 3
        Dict(0.01 => -4.30, 0.05 => -3.74, 0.10 => -3.45)
    else
        Dict(0.01 => -4.70, 0.05 => -4.14, 0.10 => -3.85)
    end

    # 协整向量
    cointegrating_vector = [1.0; -beta[2:end]]

    return (
        test_statistic=adf_result.test_statistic,
        p_value=adf_result.p_value,
        critical_values=critical_values,
        cointegrating_vector=cointegrating_vector,
        residuals=residuals
    )
end

# === Johansen 检验 =========================================================

"""
    johansen_test(data; lags=1, deterministic=:constant) -> NamedTuple

Johansen 协整检验。
"""
function johansen_test(data::Matrix{Float64}; lags::Int=1, deterministic::Symbol=:constant)
    n, k = size(data)

    # 构建差分序列
    dy = diff(data, dims=1)  # (n-1) × k

    # 有效样本量
    n_eff = size(dy, 1) - lags  # n - 1 - lags

    # 因变量 Y0: Δy_{t} for t = lags+1, ..., n-1
    Y0 = dy[lags+1:end, :]  # n_eff × k

    # 解释变量 Y1: y_{t} for t = lags+1, ..., n-1
    # 对应原始数据中的索引 lags+1 到 n-1
    Y1 = data[lags+1:end-1, :]  # n_eff × k

    # 差分滞后项: Δy_{t-1}, ..., Δy_{t-lags}
    X_lags = zeros(n_eff, k * lags)
    for i in 1:lags
        X_lags[:, (i-1)*k+1:i*k] = dy[lags+1-i:end-i, :]
    end

    # 构建回归矩阵
    if deterministic === :constant
        ones_col = ones(n_eff)
        X_other = hcat(X_lags, ones_col)
    elseif deterministic === :trend
        trend_col = collect(1.0:n_eff)
        ones_col = ones(n_eff)
        X_other = hcat(X_lags, trend_col, ones_col)
    else
        X_other = X_lags
    end

    # 第一步：回归 Y0 对 X_other
    B0 = X_other \ Y0
    R0 = Y0 - X_other * B0

    # 第二步：回归 Y1 对 X_other
    B1 = X_other \ Y1
    R1 = Y1 - X_other * B1

    # 计算 S 矩阵
    S00 = (R0' * R0) / n_eff
    S11 = (R1' * R1) / n_eff
    S01 = (R0' * R1) / n_eff
    S10 = S01'

    # 求解广义特征值问题
    S11_inv = inv(S11)
    M = S11_inv * S10 * inv(S00) * S01

    eigenvalues = real.(eigvals(M))
    eigenvectors = real.(eigvecs(M))

    # 按特征值降序排序
    sorted_indices = sortperm(eigenvalues, rev=true)
    eigenvalues = eigenvalues[sorted_indices]
    eigenvectors = eigenvectors[:, sorted_indices]

    # 确保特征值在 [0, 1) 范围内
    eigenvalues = clamp.(eigenvalues, 0.0, 1.0 - 1e-10)

    # 计算迹统计量和最大特征值统计量
    trace_stats = zeros(k)
    max_eigen_stats = zeros(k)

    for i in 1:k
        trace_stats[i] = -n_eff * sum(log.(1 .- eigenvalues[i:end]))
        max_eigen_stats[i] = -n_eff * log(1 - eigenvalues[i])
    end

    # 临界值（Osterwald-Lenum 1992 表）
    critical_values_trace = Dict(
        0.01 => [20.04, 15.41, 3.84],
        0.05 => [15.41, 9.42, 3.84],
        0.10 => [13.33, 7.56, 2.71]
    )

    critical_values_max = Dict(
        0.01 => [20.04, 15.41, 3.84],
        0.05 => [15.41, 9.42, 3.84],
        0.10 => [13.33, 7.56, 2.71]
    )

    return (
        trace_stats=trace_stats,
        max_eigen_stats=max_eigen_stats,
        critical_values_trace=critical_values_trace,
        critical_values_max=critical_values_max,
        eigenvectors=eigenvectors,
        eigenvalues=eigenvalues
    )
end

# === fit 方法 =============================================================

"""
    fit(model::CointegrationModel, data::DataFrame) -> CointegrationFitResult

执行协整检验。
"""
function MetricaBase.fit(model::CointegrationModel, data::DataFrame)
    # 排序数据
    data_sorted = sort_by_time(data, model.time_column)

    # 提取变量
    n_vars = length(model.variables)
    Y = Matrix{Float64}(data_sorted[!, model.variables])
    n = size(Y, 1)

    warnings = MetricaBase.ModelWarning[]

    if model.method === :engle_granger
        # Engle-Granger 两步法
        y = Y[:, 1]
        X = Y[:, 2:end]

        result = engle_granger_test(y, X, deterministic=model.deterministic, lags=model.lags)

        # 判断协整关系数
        n_cointegrating = result.p_value < 0.05 ? 1 : 0

        # 构建 glance 表
        glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
            :test_statistic => result.test_statistic,
            :p_value => result.p_value,
            :n_cointegrating => n_cointegrating,
            :nobs => n,
        )

        glance_table = MetricaBase.ModelGlance(
            Symbol("Engle-Granger"),
            n,
            0,
            glance_metrics,
            MetricaBase.ModelWarning[]
        )

        # 构建 tidy 表
        coef_rows = MetricaBase.CoefRow[]
        if !isnothing(result.cointegrating_vector)
            for (i, var_name) in enumerate(model.variables)
                push!(coef_rows, MetricaBase.CoefRow(
                    Symbol(var_name),
                    result.cointegrating_vector[i],
                    nothing, nothing, nothing
                ))
            end
        end

        tidy_table = MetricaBase.TidyTable(coef_rows, "cointegrating_vector")

        return CointegrationFitResult(
            string.(model.variables),
            model.method,
            result.test_statistic,
            result.p_value,
            result.critical_values,
            result.cointegrating_vector,
            n_cointegrating,
            result.residuals,
            nothing, nothing, nothing,
            glance_table,
            tidy_table,
            warnings
        )

    elseif model.method === :johansen
        # Johansen 检验
        result = johansen_test(Y, lags=model.lags, deterministic=model.deterministic)

        # 判断协整关系数（迹检验）
        n_cointegrating = 0
        for i in 1:n_vars
            cv_idx = min(i, length(result.critical_values_trace[0.05]))
            cv = result.critical_values_trace[0.05][cv_idx]
            if result.trace_stats[i] > cv
                n_cointegrating += 1
            else
                break
            end
        end

        # 构建 glance 表
        glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
            :trace_stat_1 => result.trace_stats[1],
            :max_eigen_stat_1 => result.max_eigen_stats[1],
            :n_cointegrating => n_cointegrating,
            :nobs => n,
        )

        glance_table = MetricaBase.ModelGlance(
            Symbol("Johansen"),
            n,
            0,
            glance_metrics,
            MetricaBase.ModelWarning[]
        )

        # 构建 tidy 表（特征向量）
        coef_rows = MetricaBase.CoefRow[]
        for (i, var_name) in enumerate(model.variables)
            for j in 1:n_vars
                push!(coef_rows, MetricaBase.CoefRow(
                    Symbol("$(var_name)_vec$j"),
                    result.eigenvectors[i, j],
                    nothing, nothing, nothing
                ))
            end
        end

        tidy_table = MetricaBase.TidyTable(coef_rows, "eigenvectors")

        return CointegrationFitResult(
            string.(model.variables),
            model.method,
            result.trace_stats[1],
            0.0,
            Dict{Float64, Float64}(),
            result.eigenvectors[:, 1],
            n_cointegrating,
            nothing,
            result.eigenvalues,
            result.trace_stats,
            result.max_eigen_stats,
            glance_table,
            tidy_table,
            warnings
        )

    else
        error("未知的协整检验方法: $(model.method)")
    end
end

# === 协议方法 =============================================================

function MetricaBase.glance(result::CointegrationFitResult)
    return result.glance_table
end

function MetricaBase.tidy(result::CointegrationFitResult)
    return result.tidy_table
end

function MetricaBase.nobs(result::CointegrationFitResult)
    return result.glance_table.nobs
end

function MetricaBase.coef(result::CointegrationFitResult)
    if !isnothing(result.cointegrating_vector)
        return result.cointegrating_vector
    end
    return Float64[]
end

function MetricaBase.augment(result::CointegrationFitResult)
    if isnothing(result.residuals)
        return MetricaBase.AugmentTable(Dict{Symbol, Any}(), 0)
    end

    n = length(result.residuals)
    return MetricaBase.AugmentTable(
        Dict(
            :observation => collect(1.0:n),
            :residual => result.residuals,
        ),
        n
    )
end

# === 序列化支持 ===========================================================

function result_to_payload(result::CointegrationFitResult; include_augment::Bool=true)
    payload = Dict{String, Any}(
        "model_type" => "cointegration",
        "variables" => result.variable_names,
        "method" => string(result.method),
        "test_statistic" => result.test_statistic,
        "p_value" => result.p_value,
        "critical_values" => Dict(string(k) => v for (k, v) in result.critical_values),
        "n_cointegrating_relations" => result.n_cointegrating_relations,
    )

    if !isnothing(result.cointegrating_vector)
        payload["cointegrating_vector"] = result.cointegrating_vector
    end

    if !isnothing(result.eigenvalues)
        payload["eigenvalues"] = result.eigenvalues
    end

    if !isnothing(result.trace_stats)
        payload["trace_stats"] = result.trace_stats
    end

    if !isnothing(result.max_eigen_stats)
        payload["max_eigen_stats"] = result.max_eigen_stats
    end

    payload["glance"] = Dict(
        "model" => string(result.glance_table.model),
        "nobs" => result.glance_table.nobs,
        "metrics" => Dict(string(k) => v for (k, v) in result.glance_table.metrics)
    )

    if !isempty(result.warnings)
        payload["warnings"] = [
            Dict(
                "code" => string(w.code),
                "title" => w.title,
                "detail" => w.detail,
                "hint" => w.hint,
                "severity" => string(w.severity)
            )
            for w in result.warnings
        ]
    end

    if include_augment
        at = MetricaBase.augment(result)
        max_preview = 50
        payload["augment_preview"] = Dict(
            String(k) => v[1:min(length(v), max_preview)]
            for (k, v) in at.columns
        )
    end

    return payload
end
