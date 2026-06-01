# === GLS 估计器 ================================================================

"""
广义最小二乘模型规格。`omega_fn` 接受残差向量，返回 n×n 协方差矩阵 Ω。
"""
struct GLSModel <: MetricaBase.AbstractLinearModel
    formula::String
    omega_fn::Function
end

"""
GLS 拟合结果。
"""
struct GLSFitResult <: MetricaBase.AbstractLinearFitResult
    formula::String
    glance_table::MetricaBase.ModelGlance
    tidy_table::MetricaBase.TidyTable
    coefficient_names::Vector{Symbol}
    coef_values::Vector{Float64}
    vcov_matrix::Matrix{Float64}
    stderror_values::Vector{Float64}
    design_matrix::Matrix{Float64}
    design_matrix_gls::Matrix{Float64}
    response_vector::Vector{Float64}
    fitted_values::Vector{Float64}
    residual_vector::Vector{Float64}
    omega::Matrix{Float64}
end

MetricaBase.glance(result::GLSFitResult) = result.glance_table
MetricaBase.tidy(result::GLSFitResult) = result.tidy_table
MetricaBase.coef(result::GLSFitResult) = result.coefficient_names .=> result.coef_values
MetricaBase.vcov(result::GLSFitResult) = result.vcov_matrix
MetricaBase.stderror(result::GLSFitResult) = result.stderror_values
MetricaBase.nobs(result::GLSFitResult) = length(result.response_vector)
MetricaBase.dof(result::GLSFitResult) = length(result.response_vector) - length(result.coefficient_names)
MetricaBase.r2(result::GLSFitResult) = result.glance_table.metrics[:r2]
MetricaBase.fitted(result::GLSFitResult) = result.fitted_values
MetricaBase.residuals(result::GLSFitResult) = result.residual_vector

function MetricaBase.augment(result::GLSFitResult)
    nobs_val = length(result.response_vector)
    X = result.design_matrix
    X_gls = result.design_matrix_gls
    residuals = result.residual_vector

    sigma = sqrt(sum(abs2, residuals) / (nobs_val - size(X, 2)))
    std_residuals = sigma > 0 ? residuals ./ sigma : zeros(nobs_val)

    XtX_gls_inv = inv(cholesky(Symmetric(X_gls' * X_gls)))
    leverage = [dot(X[i, :], XtX_gls_inv * X[i, :]) for i in 1:nobs_val]

    k = size(X, 2)
    cooks_d = fill(NaN, nobs_val)
    for i in 1:nobs_val
        if leverage[i] < 1.0 && sigma > 0
            cooks_d[i] = (std_residuals[i]^2 * leverage[i]) / (k * (1.0 - leverage[i])^2)
        end
    end

    return MetricaBase.AugmentTable(Dict(
        :observation => collect(1.0:nobs_val),
        :fitted => result.fitted_values,
        :residual => residuals,
        :std_residual => std_residuals,
        :leverage => leverage,
        :cooks_d => cooks_d,
    ), nobs_val)
end

function MetricaBase.predict(result::GLSFitResult;
                             newdata::Union{Nothing,Matrix{Float64}}=nothing,
                             interval::Symbol=:none, level::Float64=0.95)
    X = isnothing(newdata) ? result.design_matrix : newdata
    predictions = X * result.coef_values
    interval === :none && return predictions

    n = length(result.response_vector)
    k = length(result.coefficient_names)
    dof_val = n - k
    t_crit = quantile(TDist(dof_val), 1 - (1 - level) / 2)
    sigma = result.glance_table.metrics[:sigma]
    XtX_gls_inv = inv(cholesky(Symmetric(result.design_matrix_gls' * result.design_matrix_gls)))

    se_pred = if interval === :confidence
        [sqrt(sigma^2 * dot(X[i, :], XtX_gls_inv * X[i, :])) for i in 1:size(X, 1)]
    else
        [sqrt(sigma^2 * (1 + dot(X[i, :], XtX_gls_inv * X[i, :]))) for i in 1:size(X, 1)]
    end

    return (predictions=predictions, lower=predictions .- t_crit .* se_pred, upper=predictions .+ t_crit .* se_pred)
end

"""
    fit(GLSModel, formula, data; omega_fn, vcov)

使用统一接口拟合 GLS 模型。`omega_fn` 接受残差向量，返回 n×n 协方差矩阵 Ω。
"""
function MetricaBase.fit(::Type{GLSModel}, formula::AbstractString, data;
                         omega_fn::Function,
                         vcov::Symbol=:classical)
    dataset = if data isa AbstractString
        loaded = load_dataset(data)
        loaded isa MetricaBase.ModelError && return loaded
        loaded
    else
        data
    end

    model_formula = parse_formula_term(formula)
    model_formula isa MetricaBase.ModelError && return model_formula

    model_columns = collect_term_symbols(model_formula)
    err = validate_model_columns(dataset, model_columns, nothing, nothing)
    err isa MetricaBase.ModelError && return err

    prepared = prepare_model_data(dataset, model_formula, model_columns, nothing, nothing)
    prepared isa MetricaBase.ModelError && return prepared

    (_, model_frame, _, X, y, _, _, n_total, n_effective) = prepared
    nobs = length(y)
    ncoef = size(X, 2)

    err = validate_design(X, ncoef, nobs)
    err isa MetricaBase.ModelError && return err

    dof_val = nobs - ncoef

    # OLS 拟合得到初始残差
    ols_coef = X \ y
    ols_residuals = y - X * ols_coef

    # 调用 omega_fn
    omega = try
        omega_fn(ols_residuals)
    catch e
        return MetricaBase.ModelError(:omega_fn_failed, "协方差函数调用失败",
            "omega_fn 执行出错：$(sprint(showerror, e))",
            "请检查 omega_fn 的实现，它应接受残差向量并返回 n×n 协方差矩阵。")
    end

    size(omega) == (nobs, nobs) || return MetricaBase.ModelError(
        :omega_dimension_mismatch, "协方差矩阵维度不匹配",
        "omega_fn 返回的矩阵维度为 $(size(omega))，期望 ($nobs, $nobs)。",
        "请确保 omega_fn 返回 n×n 的协方差矩阵。")

    omega_chol = try
        cholesky(Symmetric(omega))
    catch e
        return MetricaBase.ModelError(:omega_not_positive_definite, "协方差矩阵非正定",
            "omega_fn 返回的矩阵不是正定矩阵：$(sprint(showerror, e))",
            "请确保 omega_fn 返回的矩阵是正定的。")
    end

    L_inv = Matrix(omega_chol.L) \ I
    X_gls = L_inv * X
    y_gls = L_inv * y

    coefficients = X_gls \ y_gls
    fitted = X * coefficients
    residuals = y - fitted
    residuals_gls = y_gls - X_gls * coefficients

    vcov_result = compute_vcov(X_gls, residuals_gls, nobs, dof_val, vcov, nothing)
    vcov_result isa MetricaBase.ModelError && return vcov_result
    vcov_mat, stderror = vcov_result

    rss = sum(abs2, residuals_gls)
    tss = sum(abs2, y_gls .- mean(y_gls))
    r2_val = iszero(tss) ? 1.0 : 1 - rss / tss
    adj_r2 = iszero(tss) ? 1.0 : 1 - (rss / dof_val) / (tss / (nobs - 1))
    sigma = sqrt(rss / dof_val)

    coefficient_names = Symbol.(coefnames(model_frame))

    warnings = MetricaBase.ModelWarning[]
    dropped_rows = n_total - n_effective
    dropped_rows > 0 && push!(warnings, build_rows_dropped_warning(dropped_rows))

    # Wald 检验（系数联合显著性）
    model_ss = tss - rss
    model_df = ncoef - 1
    wald_stat = (model_ss / model_df) / (rss / dof_val)
    wald_pvalue = 1 - cdf(FDist(model_df, dof_val), wald_stat)

    glance_table = MetricaBase.ModelGlance(:gls, nobs, dof_val,
        Dict{Symbol, MetricaBase.MetricValue}(:r2 => r2_val, :adj_r2 => adj_r2, :rss => rss, :tss => tss, :sigma => sigma,
            :wald_stat => wald_stat, :wald_pvalue => wald_pvalue),
        warnings)

    tidy_table = assemble_tidy_table(coefficients, stderror, coefficient_names, dof_val, vcov)

    return GLSFitResult(String(formula), glance_table, tidy_table,
        coefficient_names, coefficients, vcov_mat, stderror,
        Matrix{Float64}(X), Matrix{Float64}(X_gls), copy(y), fitted, residuals,
        Matrix{Float64}(omega))
end
