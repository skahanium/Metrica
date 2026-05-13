# unitroot.jl - 单位根检验模块
# 实现 ADF、Phillips-Perron、KPSS 三种单位根检验

# === 结果类型 =============================================================

"""
    UnitRootResult

单位根检验结果。
"""
struct UnitRootResult
    test_name::String
    test_statistic::Float64
    p_value::Float64
    lags_used::Int
    critical_values::Dict{Float64, Float64}
    conclusion::String  # "reject" 或 "fail_to_reject"
end

"""
    UnitRootFitResult <: AbstractTSFitResult

单位根检验拟合结果，包含多个检验的结果。
"""
struct UnitRootFitResult <: AbstractTSFitResult
    variable_name::String
    adf::Union{UnitRootResult, Nothing}
    pp::Union{UnitRootResult, Nothing}
    kpss::Union{UnitRootResult, Nothing}
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    warnings::Vector{MetricaBase.ModelWarning}
end

"""
    UnitRootModel <: AbstractTimeSeriesModel

单位根检验模型规格。
"""
struct UnitRootModel <: AbstractTimeSeriesModel
    variable::Symbol
    time_column::Symbol
    deterministic::Symbol  # :constant, :trend, :none
    lag_method::Symbol     # :auto, :aic, :bic
    max_lags::Int
end

"""
    UnitRootModel(; variable, time_column, deterministic=:constant, lag_method=:auto, max_lags=0)

构造单位根检验模型规格。

# 参数
- `variable`: 检验变量列名
- `time_column`: 时间列名
- `deterministic`: 确定性成分 (:constant, :trend, :none)
- `lag_method`: 滞后选择方法 (:auto, :aic, :bic)
- `max_lags`: 最大滞后阶数（0 表示自动选择）
"""
function UnitRootModel(; variable::Symbol, time_column::Symbol,
                       deterministic::Symbol=:constant,
                       lag_method::Symbol=:auto,
                       max_lags::Int=0)
    return UnitRootModel(variable, time_column, deterministic, lag_method, max_lags)
end

# === ADF 检验 =============================================================

"""
    select_adf_lags(y, max_lags; method=:aic) -> Int

选择 ADF 检验的滞后阶数。

# 参数
- `y`: 时间序列
- `max_lags`: 最大滞后阶数
- `method`: 选择方法 (:aic, :bic)

# 返回
- 最优滞后阶数
"""
function select_adf_lags(y::Vector{Float64}, max_lags::Int; method::Symbol=:aic)
    n = length(y)
    best_criterion = Inf
    best_lag = 0

    # 构建差分序列和滞后矩阵
    dy = diff(y)
    y_lag = y[1:end-1]
    n_reg = length(dy)

    for p in 0:max_lags
        if p == 0
            # 无滞后项
            X = hcat(ones(n_reg), y_lag)
        else
            # 添加滞后差分项
            if n_reg - p <= 0
                continue
            end
            dy_lags = zeros(n_reg - p, p)
            for j in 1:p
                dy_lags[:, j] = dy[p-j+1:n_reg-j]
            end
            X = hcat(ones(n_reg - p), y_lag[p+1:end], dy_lags)
            dy_use = dy[p+1:end]
        end

        if p == 0
            dy_use = dy
        end

        # OLS 估计
        beta = X \ dy_use
        residuals = dy_use - X * beta
        n_params = size(X, 2)
        n_obs = length(dy_use)

        # 计算信息准则
        sigma2 = sum(residuals .^ 2) / n_obs
        if method === :aic
            criterion = n_obs * log(sigma2) + 2 * n_params
        else  # :bic
            criterion = n_obs * log(sigma2) + n_params * log(n_obs)
        end

        if criterion < best_criterion
            best_criterion = criterion
            best_lag = p
        end
    end

    return best_lag
end

"""
    adf_test(y; deterministic=:constant, lag=:auto, max_lags=nothing) -> UnitRootResult

Augmented Dickey-Fuller 单位根检验。

# 参数
- `y`: 时间序列数据
- `deterministic`: 确定性成分 (:constant, :trend, :none)
- `lag`: 滞后选择方法 (:auto, :aic, :bic 或具体整数)
- `max_lags`: 最大滞后阶数（仅当 lag=:auto/:aic/:bic 时使用）

# 返回
- `UnitRootResult`: 检验结果
"""
function adf_test(y::Vector{Float64}; deterministic::Symbol=:constant,
                  lag=:auto, max_lags=nothing)
    n = length(y)

    # 确定最大滞后阶数
    if isnothing(max_lags)
        max_lags = Int(ceil(12 * (n / 100)^0.25))
    end

    # 选择滞后阶数
    if lag === :auto || lag === :aic
        lag = select_adf_lags(y, max_lags, method=:aic)
    elseif lag === :bic
        lag = select_adf_lags(y, max_lags, method=:bic)
    end

    # 使用 HypothesisTests.jl 的 ADFTest
    test = HypothesisTests.ADFTest(y, deterministic, lag)

    # 获取检验统计量和 p 值
    test_stat = test.stat
    p_value = HypothesisTests.pvalue(test)

    # 临界值（MacKinnon 2010）
    critical_values = if deterministic === :constant
        Dict(0.01 => -3.43, 0.05 => -2.86, 0.10 => -2.57)
    elseif deterministic === :trend
        Dict(0.01 => -3.96, 0.05 => -3.41, 0.10 => -3.13)
    else
        Dict(0.01 => -2.58, 0.05 => -1.94, 0.10 => -1.62)
    end

    # 判断结论
    conclusion = p_value < 0.05 ? "reject" : "fail_to_reject"

    return UnitRootResult(
        "ADF",
        test_stat,
        p_value,
        lag,
        critical_values,
        conclusion
    )
end

# === Phillips-Perron 检验 =================================================

"""
    pp_test(y; deterministic=:constant, lags=:auto) -> UnitRootResult

Phillips-Perron 单位根检验（非参数修正）。

# 参数
- `y`: 时间序列数据
- `deterministic`: 确定性成分 (:constant, :trend, :none)
- `lags`: 截断滞后阶数 (:auto 或具体整数)

# 返回
- `UnitRootResult`: 检验结果
"""
function pp_test(y::Vector{Float64}; deterministic::Symbol=:constant, lags=:auto)
    n = length(y)

    # 自动选择截断滞后阶数
    if lags === :auto
        lags = Int(ceil(4 * (n / 100)^0.25))
    end

    # 构建回归矩阵
    y_lag = y[1:end-1]
    y_curr = y[2:end]
    n_reg = length(y_curr)

    if deterministic === :constant
        X = hcat(ones(n_reg), y_lag)
    elseif deterministic === :trend
        X = hcat(ones(n_reg), collect(1:n_reg), y_lag)
    else
        X = reshape(y_lag, n_reg, 1)
    end

    # OLS 估计
    beta = X \ y_curr
    residuals = y_curr - X * beta
    rho = beta[end]

    # 计算长期方差（Newey-West 估计）
    gamma_0 = sum(residuals .^ 2) / n_reg
    gamma_sum = 0.0
    for j in 1:lags
        gamma_j = sum(residuals[j+1:end] .* residuals[1:end-j]) / n_reg
        gamma_sum += 2 * (1 - j / (lags + 1)) * gamma_j
    end
    lambda_sq = gamma_0 + gamma_sum

    # 计算 rho 的标准误
    y_lag_demean = y_lag .- mean(y_lag)
    se_rho = sqrt(gamma_0 / sum(y_lag_demean .^ 2))

    # t 统计量
    t_stat = (rho - 1) / se_rho

    # PP 修正
    sigma_sq = sum(residuals .^ 2) / (n_reg - size(X, 2))
    correction = (n_reg * se_rho / (2 * sqrt(sigma_sq))) * (lambda_sq - gamma_0)
    pp_stat = t_stat - correction

    # 临界值（与 ADF 相同）
    critical_values = if deterministic === :constant
        Dict(0.01 => -3.43, 0.05 => -2.86, 0.10 => -2.57)
    elseif deterministic === :trend
        Dict(0.01 => -3.96, 0.05 => -3.41, 0.10 => -3.13)
    else
        Dict(0.01 => -2.58, 0.05 => -1.94, 0.10 => -1.62)
    end

    # PP 统计量与 ADF 统计量服从相同的渐近 Dickey-Fuller 分布
    # 使用 MacKinnon (1994) 响应面计算 p 值（复用 HypothesisTests 的辅助函数）
    z = HypothesisTests.adf_pv_aux(pp_stat, deterministic)
    p_value = cdf(Normal(0, 1), z)
    conclusion = p_value < 0.05 ? "reject" : "fail_to_reject"

    return UnitRootResult(
        "Phillips-Perron",
        pp_stat,
        p_value,
        lags,
        critical_values,
        conclusion
    )
end

# === KPSS 检验 ============================================================

"""
    kpss_test(y; deterministic=:constant, lags=:auto) -> UnitRootResult

KPSS 单位根检验（零假设为平稳）。

# 参数
- `y`: 时间序列数据
- `deterministic`: 确定性成分 (:constant, :trend)
- `lags`: 截断滞后阶数 (:auto 或具体整数)

# 返回
- `UnitRootResult`: 检验结果
"""
function kpss_test(y::Vector{Float64}; deterministic::Symbol=:constant, lags=:auto)
    n = length(y)

    # 自动选择截断滞后阶数
    if lags === :auto
        lags = Int(ceil(4 * (n / 100)^0.25))
    end

    # 计算残差
    if deterministic === :constant
        mu = mean(y)
        residuals = y .- mu
    else  # :trend
        t = collect(1:n)
        X = hcat(ones(n), t)
        beta = X \ y
        residuals = y - X * beta
    end

    # 计算累积和
    cumsum_residuals = cumsum(residuals)

    # 计算长期方差估计（Newey-West）
    gamma_0 = sum(residuals .^ 2) / n
    gamma_sum = 0.0
    for j in 1:lags
        gamma_j = sum(residuals[j+1:end] .* residuals[1:end-j]) / n
        gamma_sum += 2 * (1 - j / (lags + 1)) * gamma_j
    end
    s_sq = gamma_0 + gamma_sum

    # KPSS 统计量
    eta = sum(cumsum_residuals .^ 2) / (n^2 * s_sq)

    # 临界值（Kwiatkowski et al. 1992 表 1）
    critical_values = if deterministic === :constant
        Dict(0.01 => 0.739, 0.05 => 0.463, 0.10 => 0.347)
    else  # :trend
        Dict(0.01 => 0.216, 0.05 => 0.146, 0.10 => 0.119)
    end

    # KPSS 的 p 值（使用近似）
    # 注意：KPSS 的零假设是平稳，所以拒绝零假设意味着非平稳
    p_value = if eta > critical_values[0.01]
        0.001
    elseif eta > critical_values[0.05]
        0.01
    elseif eta > critical_values[0.10]
        0.05
    else
        0.10
    end

    # KPSS 拒绝零假设意味着非平稳
    conclusion = p_value < 0.05 ? "reject" : "fail_to_reject"

    return UnitRootResult(
        "KPSS",
        eta,
        p_value,
        lags,
        critical_values,
        conclusion
    )
end

# === fit 方法 =============================================================

"""
    fit(model::UnitRootModel, data::DataFrame) -> UnitRootFitResult

执行单位根检验。

# 参数
- `model`: 单位根检验模型规格
- `data`: 包含时间序列数据的 DataFrame

# 返回
- `UnitRootFitResult`: 包含 ADF、PP、KPSS 检验结果
"""
function MetricaBase.fit(model::UnitRootModel, data::DataFrame)
    # 排序数据
    data_sorted = sort_by_time(data, model.time_column)

    # 提取序列
    y = Float64.(data_sorted[!, model.variable])
    n = length(y)

    # 确定最大滞后阶数
    max_lags = model.max_lags > 0 ? model.max_lags : nothing

    # 执行三种检验
    adf_result = adf_test(y, deterministic=model.deterministic,
                          lag=model.lag_method, max_lags=max_lags)
    pp_result = pp_test(y, deterministic=model.deterministic)
    kpss_result = kpss_test(y, deterministic=model.deterministic)

    # 构建 glance 表
    glance_metrics = Dict{Symbol, MetricaBase.MetricValue}(
        :adf_statistic => adf_result.test_statistic,
        :adf_pvalue => adf_result.p_value,
        :pp_statistic => pp_result.test_statistic,
        :pp_pvalue => pp_result.p_value,
        :kpss_statistic => kpss_result.test_statistic,
        :kpss_pvalue => kpss_result.p_value,
        :nobs => n,
    )

    glance_table = MetricaBase.ModelGlance(
        :UnitRootTest,
        n,
        0,  # dof 不适用
        glance_metrics,
        MetricaBase.ModelWarning[]
    )

    # 构建 tidy 表
    coef_rows = MetricaBase.CoefRow[]

    # ADF 结果行
    push!(coef_rows, MetricaBase.CoefRow(
        :adf,
        adf_result.test_statistic,
        adf_result.critical_values[0.05],  # 使用 5% 临界值作为参考
        nothing,  # t 统计量不适用
        adf_result.p_value,
        nothing, nothing,
    ))

    # PP 结果行
    push!(coef_rows, MetricaBase.CoefRow(
        :pp,
        pp_result.test_statistic,
        pp_result.critical_values[0.05],
        nothing,
        pp_result.p_value,
        nothing, nothing,
    ))

    # KPSS 结果行
    push!(coef_rows, MetricaBase.CoefRow(
        :kpss,
        kpss_result.test_statistic,
        kpss_result.critical_values[0.05],
        nothing,
        kpss_result.p_value,
        nothing, nothing,
    ))

    tidy_table = MetricaBase.TidyTable(
        coef_rows,
        "critical_value_5pct"
    )

    # 构建警告
    warnings = MetricaBase.ModelWarning[]

    # ADF 和 KPSS 结论不一致时发出警告
    if adf_result.conclusion != kpss_result.conclusion
        push!(warnings, MetricaBase.ModelWarning(
            :unitroot_conflict,
            "单位根检验结论不一致",
            "ADF 检验结论为 $(adf_result.conclusion)，KPSS 检验结论为 $(kpss_result.conclusion)",
            "建议进一步检查序列的平稳性特征，考虑使用差分或趋势分解",
            MetricaBase.warning
        ))
    end

    # ADF 和 PP 结论不一致时发出警告
    if adf_result.conclusion != pp_result.conclusion
        push!(warnings, MetricaBase.ModelWarning(
            :pp_adf_conflict,
            "ADF 与 Phillips-Perron 结论不一致",
            "ADF 结论为 $(adf_result.conclusion)，PP 结论为 $(pp_result.conclusion)",
            "可能存在异方差或序列相关问题",
            MetricaBase.info
        ))
    end

    return UnitRootFitResult(
        string(model.variable),
        adf_result,
        pp_result,
        kpss_result,
        glance_table,
        tidy_table,
        warnings
    )
end

# === 协议方法 =============================================================

function MetricaBase.glance(result::UnitRootFitResult)
    return result.glance_table
end

function MetricaBase.tidy(result::UnitRootFitResult)
    return result.tidy_table
end

function MetricaBase.nobs(result::UnitRootFitResult)
    return result.glance_table.nobs
end

function MetricaBase.coef(result::UnitRootFitResult)
    v = Float64[]
    if !isnothing(result.adf)
        push!(v, result.adf.test_statistic)
    end
    if !isnothing(result.pp)
        push!(v, result.pp.test_statistic)
    end
    if !isnothing(result.kpss)
        push!(v, result.kpss.test_statistic)
    end
    return v
end

function MetricaBase.augment(result::UnitRootFitResult)
    n = result.glance_table.nobs
    cols = Dict{Symbol, Any}(
        :observation => collect(1.0:n),
    )
    return MetricaBase.AugmentTable(cols, n)
end

# === 序列化支持 ===========================================================

function result_to_payload(result::UnitRootFitResult; include_augment::Bool=true)
    payload = Dict{String, Any}(
        "model_type" => "unitroot",
        "variable" => result.variable_name,
        "nobs" => result.glance_table.nobs,
    )

    # 添加各检验结果
    if !isnothing(result.adf)
        payload["adf"] = Dict(
            "test_statistic" => result.adf.test_statistic,
            "p_value" => result.adf.p_value,
            "lags_used" => result.adf.lags_used,
            "critical_values" => Dict(string(k) => v for (k, v) in result.adf.critical_values),
            "conclusion" => result.adf.conclusion
        )
    end

    if !isnothing(result.pp)
        payload["pp"] = Dict(
            "test_statistic" => result.pp.test_statistic,
            "p_value" => result.pp.p_value,
            "lags_used" => result.pp.lags_used,
            "critical_values" => Dict(string(k) => v for (k, v) in result.pp.critical_values),
            "conclusion" => result.pp.conclusion
        )
    end

    if !isnothing(result.kpss)
        payload["kpss"] = Dict(
            "test_statistic" => result.kpss.test_statistic,
            "p_value" => result.kpss.p_value,
            "lags_used" => result.kpss.lags_used,
            "critical_values" => Dict(string(k) => v for (k, v) in result.kpss.critical_values),
            "conclusion" => result.kpss.conclusion
        )
    end

    # 添加 glance 指标
    payload["glance"] = Dict(
        "model" => string(result.glance_table.model),
        "nobs" => result.glance_table.nobs,
        "metrics" => Dict(string(k) => v for (k, v) in result.glance_table.metrics)
    )

    # 添加警告
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
