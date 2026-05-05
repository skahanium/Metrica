# === SurveyDesign 构造器与 Taylor 线性化 Sandwich 方差估计 =====================

function SurveyDesign(
    data::DataFrame,
    weights_column::Symbol;
    strata_column::Union{Nothing, Symbol}=nothing,
    psu_column::Union{Nothing, Symbol}=nothing,
    fpc_column::Union{Nothing, Symbol}=nothing,
)
    wc_str = String(weights_column)
    if !(wc_str in names(data))
        return MetricaBase.ModelError(
            :missing_weight_column,
            "抽样权重列不存在",
            "DataFrame 中找不到权重列 :$(weights_column)。",
            "请检查列名是否正确。可用列：$(names(data))。",
        )
    end

    w = data[!, weights_column]
    if any(<(0), w)
        return MetricaBase.ModelError(
            :negative_weights,
            "抽样权重包含负值",
            "权重列 :$(weights_column) 中存在 $(sum(w .< 0)) 个负值。",
            "抽样权重必须为非负数。请检查数据源。",
        )
    end
    if all(iszero, w)
        return MetricaBase.ModelError(
            :zero_weights,
            "抽样权重全为零",
            "权重列 :$weights_column 的所有值均为零。",
            "抽样权重不能全部为零。请检查数据源。",
        )
    end

    if !isnothing(strata_column) && !(String(strata_column) in names(data))
        return MetricaBase.ModelError(
            :missing_strata_column,
            "分层变量列不存在",
            "DataFrame 中找不到分层列 :$(strata_column)。",
            "请检查列名或设为 nothing。",
        )
    end

    if !isnothing(psu_column) && !(String(psu_column) in names(data))
        return MetricaBase.ModelError(
            :missing_psu_column,
            "PSU 列不存在",
            "DataFrame 中找不到 PSU 列 :$(psu_column)。",
            "请检查列名或设为 nothing。",
        )
    end

    if !isnothing(fpc_column) && !(String(fpc_column) in names(data))
        return MetricaBase.ModelError(
            :missing_fpc_column,
            "FPC 列不存在",
            "DataFrame 中找不到 FPC 列 :$(fpc_column)。",
            "请检查列名或设为 nothing。",
        )
    end

    SurveyDesign(data, weights_column, strata_column, psu_column, fpc_column)
end

# === Taylor 线性化 Sandwich 方差估计器 ===========================================

function taylor_linearization_vcov(
    X::Matrix{Float64},
    residuals::Vector{Float64},
    weights::Vector{Float64},
    design::SurveyDesign,
)
    nobs, ncoef = size(X)
    w = weights[1:nobs]

    # 计算每个观测的得分贡献: s_j = x_j * w_j * r_j  (k×1 向量)
    score_matrix = X .* (w .* residuals)  # n×k, 每行是 s_j

    strata_col = design.strata_column
    psu_col = design.psu_column
    fpc_col = design.fpc_column

    # 根据抽样设计结构计算 Var_hat(S)
    if !isnothing(strata_col) && !isnothing(psu_col)
        Var_S = strata_psu_variance(score_matrix, design, nobs)
    elseif !isnothing(strata_col)
        # 有分层无 PSU：每观测即一 PSU
        Var_S = strata_only_variance(score_matrix, design, nobs)
    elseif !isnothing(psu_col)
        # 无分层有 PSU：单层内 PSU 聚合
        Var_S = psu_only_variance(score_matrix, design, nobs)
    else
        # 无分层无 PSU：简单稳健方差
        s_bar = mean(score_matrix, dims=1)
        centered = score_matrix .- s_bar
        Var_S = (nobs / (nobs - 1)) * (centered' * centered)
    end

    # 有限总体修正 (FPC): (1 - n/N)
    if !isnothing(fpc_col)
        fpc_values = design.data[1:nobs, fpc_col]
        sampling_fraction = nobs ./ fpc_values
        fpc_factor = max.(1.0 .- sampling_fraction, 0.0)
        # 对抽样比 > 5% 的观测应用 FPC，取中位数因子
        if any(sampling_fraction .> 0.05)
            Var_S = Var_S .* median(fpc_factor[sampling_fraction .> 0.05])
        end
    end

    # Bread 矩阵: B = (X'WX)^{-1}
    XtWX = X' * Diagonal(w) * X
    bread = try
        inv(Symmetric(XtWX))
    catch
        pinv(XtWX)
    end

    # Sandwich: Var(β) = B * Var_S * B
    survey_vcov = bread * Var_S * bread

    # 确保数值稳定性：对称化并强制对角线非负
    survey_vcov = Symmetric(survey_vcov)
    d = diag(survey_vcov)
    if any(<(0), d)
        d_fixed = max.(d, 0.0)
        survey_vcov = survey_vcov + Diagonal(d_fixed - d)
    end

    return Matrix(survey_vcov)
end

# === 分层 + PSU 方差估计 ========================================================

function strata_psu_variance(
    score_matrix::Matrix{Float64},
    design::SurveyDesign,
    nobs::Int,
)
    strata = design.data[1:nobs, design.strata_column]
    psu = design.data[1:nobs, design.psu_column]
    unique_strata = sort(unique(strata))
    ncoef = size(score_matrix, 2)
    Var_S = zeros(ncoef, ncoef)

    for h in unique_strata
        in_h = strata .== h
        psu_in_h = psu[in_h]
        unique_psu = sort(unique(psu_in_h))
        n_h = length(unique_psu)

        if n_h < 2
            # 单 PSU 层：跳过，发出警告（通过返回的方差体现）
            continue
        end

        # 计算每 PSU 的得分总和 s_hi
        psu_scores = zeros(n_h, ncoef)
        for (i_idx, p) in enumerate(unique_psu)
            in_psu = in_h .& (psu .== p)
            psu_scores[i_idx, :] = vec(sum(score_matrix[in_psu, :], dims=1))
        end

        # 层内 PSU 得分均值
        s_bar_h = mean(psu_scores, dims=1)

        # 层内 PSU 间方差: n_h/(n_h-1) * Σ_i (s_hi - s̄_h)(s_hi - s̄_h)'
        centered = psu_scores .- s_bar_h
        V_h = (n_h / (n_h - 1)) * (centered' * centered)

        Var_S += V_h
    end

    return Var_S
end

# === 仅分层（无 PSU）方差估计 ====================================================

function strata_only_variance(
    score_matrix::Matrix{Float64},
    design::SurveyDesign,
    nobs::Int,
)
    strata = design.data[1:nobs, design.strata_column]
    unique_strata = sort(unique(strata))
    ncoef = size(score_matrix, 2)
    Var_S = zeros(ncoef, ncoef)

    for h in unique_strata
        in_h = strata .== h
        n_h = sum(in_h)

        if n_h < 2
            continue
        end

        s_h = score_matrix[in_h, :]
        s_bar_h = mean(s_h, dims=1)
        centered = s_h .- s_bar_h
        V_h = (n_h / (n_h - 1)) * (centered' * centered)
        Var_S += V_h
    end

    return Var_S
end

# === 仅 PSU（无分层）方差估计 ====================================================

function psu_only_variance(
    score_matrix::Matrix{Float64},
    design::SurveyDesign,
    nobs::Int,
)
    psu = design.data[1:nobs, design.psu_column]
    unique_psu = sort(unique(psu))
    n_psu = length(unique_psu)
    ncoef = size(score_matrix, 2)

    if n_psu < 2
        return zeros(ncoef, ncoef)
    end

    psu_scores = zeros(n_psu, ncoef)
    for (i_idx, p) in enumerate(unique_psu)
        in_psu = psu .== p
        psu_scores[i_idx, :] = vec(sum(score_matrix[in_psu, :], dims=1))
    end

    s_bar = mean(psu_scores, dims=1)
    centered = psu_scores .- s_bar
    return (n_psu / (n_psu - 1)) * (centered' * centered)
end

# === 设计效应计算 ================================================================

function compute_deff(survey_vcov::Matrix{Float64}, srs_vcov::Matrix{Float64}, nobs::Int)
    d_survey = diag(survey_vcov)
    d_srs = diag(srs_vcov)

    deff = zeros(length(d_survey))
    n_eff = zeros(length(d_survey))

    for i in eachindex(d_survey)
        if d_srs[i] > 1e-16
            deff[i] = d_survey[i] / d_srs[i]
            n_eff[i] = nobs / deff[i]
        else
            deff[i] = 1.0
            n_eff[i] = Float64(nobs)
        end
    end

    return deff, n_eff
end
