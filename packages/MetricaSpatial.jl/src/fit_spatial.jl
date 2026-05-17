# === 对外入口：读数据、对齐 W、拟合 SAR 或 SEM =============================

function fit_spatial(
    model_type::AbstractString,
    formula::AbstractString,
    df::DataFrame,
    spec::AbstractDict{String, <:Any},
    working_dir::AbstractString,
)::Union{SpatialFitResult, MetricaBase.ModelError}
    idcol = String(get(spec, "spatial_id_column", ""))
    isempty(strip(idcol)) &&
        return MetricaBase.ModelError(
            :spatial_missing_id_column,
            "缺少 spatial_id_column",
            "空间模型必须在主数据中指定与边表对齐的 ID 列名。",
            "请在 model_spec 中设置 spatial_id_column。",
        )
    wpath_raw = String(get(spec, "spatial_weights_path", ""))
    isempty(strip(wpath_raw)) &&
        return MetricaBase.ModelError(
            :spatial_missing_weights,
            "缺少 spatial_weights_path",
            "必须提供边表 CSV 路径。",
            "请设置 spatial_weights_path。",
        )
    wpath = resolve_weights_path(wpath_raw, String(working_dir))
    !isfile(wpath) &&
        return MetricaBase.ModelError(
            :spatial_weights_not_found,
            "空间权重文件不存在",
            wpath,
            "请检查 spatial_weights_path 与 working_dir。",
        )
    row_std = Bool(get(spec, "spatial_row_standardize", true))

    parsed = MetricaBase.parse_metrica_formula(formula)
    parsed isa MetricaBase.ModelError && return parsed
    yname, xnames = parsed
    needcols = unique(vcat([yname], xnames, [idcol]))
    missingcols = setdiff(needcols, names(df))
    !isempty(missingcols) &&
        return MetricaBase.ModelError(
            :spatial_missing_columns,
            "数据缺少列",
            join(missingcols, ", "),
            "请检查公式与 spatial_id_column。",
        )
    sub = select(df, needcols)
    subcc = dropmissing(sub)
    nrow(subcc) == 0 &&
        return MetricaBase.ModelError(:spatial_empty_sample, "有效样本为空", "complete cases 为 0。", "请检查缺失值。")

    id_sym = Symbol(idcol)
    idg = combine(groupby(subcc, id_sym), nrow => :_n)
    maximum(idg._n) > 1 &&
        return MetricaBase.ModelError(
            :spatial_duplicate_id,
            "空间 ID 在主数据中重复",
            "每个 spatial_id 必须唯一对应一行截面观测。",
            "请先聚合数据或清洗重复 id。",
        )

    sub_u = sort(combine(groupby(subcc, id_sym), first), id_sym)
    ids = string.(sub_u[!, id_sym])
    n = length(ids)
    n > 5000 &&
        return MetricaBase.ModelError(
            :spatial_n_too_large,
            "样本量超过首期上界",
            "当前空间模型要求 n ≤ 5000。",
            "请抽样或拆分区域。",
        )

    edges = read_edges_csv(wpath)
    edges isa MetricaBase.ModelError && return edges
    nrow(edges) > 200_000 &&
        return MetricaBase.ModelError(
            :spatial_edges_too_many,
            "边表行数超过上界",
            "边表行数须 ≤ 200000。",
            "请使用稀疏化后的邻接表。",
        )

    wbuilt = edges_to_weight_matrix(edges, ids; row_standardize=row_std)
    wbuilt isa MetricaBase.ModelError && return wbuilt
    W, wrep = wbuilt

    ys = Vector{Float64}(undef, n)
    Xs = zeros(Float64, n, 1 + length(xnames))
    x_colnames = Vector{Symbol}(undef, 1 + length(xnames))
    x_colnames[1] = :intercept
    for (j, xn) in enumerate(xnames)
        x_colnames[j + 1] = Symbol(xn)
    end
    for (ri, r) in enumerate(eachrow(sub_u))
        ys[ri] = Float64(r[Symbol(yname)])
        Xs[ri, 1] = 1.0
        for (j, xn) in enumerate(xnames)
            Xs[ri, j + 1] = Float64(r[Symbol(xn)])
        end
    end

    vcov_key = lowercase(String(get(spec, "vcov", "classical")))
    vcov_sym = vcov_key == "hc1" ? :HC1 : :classical
    vcov_label = vcov_sym == :HC1 ? "HC1（简化三明治，SAR）" : "2SLS 渐近（同方差）"

    basename = basename_split(wpath)
    diag = Dict{Symbol, Any}(
        :n_obs => n,
        :n_nonzero_links => wrep[:nnz_stored],
        :symmetry_hint => wrep[:symmetry_hint],
        :id_join_unique => true,
        :id_join_missing_count => 0,
        :spatial_weights_basename => basename,
        :row_standardized_report => Dict{Symbol, Any}(
            :requested => wrep[:row_standardize_requested],
            :applied => wrep[:row_standardize_applied],
            :row_sums_min => wrep[:row_sums_min],
            :row_sums_max => wrep[:row_sums_max],
        ),
        :direct_effects => nothing,
        :indirect_effects => nothing,
        :total_effects => nothing,
        :effects_method => nothing,
    )

    warnings = MetricaBase.ModelWarning[]

    # OLS 残差用于 LM 检验（Anselin 1988）
    e_ols = ys - Xs * (Xs \ ys)
    diag[:lm_lag] = lm_lag_test(e_ols, Xs, W)
    diag[:lm_error] = lm_error_test(e_ols, Xs, W)
    diag[:robust_lm_lag] = robust_lm_lag_test(e_ols, Xs, W)
    diag[:robust_lm_error] = robust_lm_error_test(e_ols, Xs, W)

    if model_type == "spatial_lag"
        out = fit_sar_2sls(ys, Xs, W, x_colnames; vcov_kind=vcov_sym == :HC1 ? :HC1 : :classical)
        out isa MetricaBase.ModelError && return out
        pairs, se, fitted, resid, ρ = out
        mor = moran_residuals(resid, W)
        merge!(diag, mor)
        diag[:rho] = ρ
        eff = sar_effects(ρ, pairs, W, x_colnames)
        eff isa MetricaBase.ModelError && return eff
        direct, indirect, total, method = eff
        diag[:direct_effects] = direct
        diag[:indirect_effects] = indirect
        diag[:total_effects] = total
        diag[:effects_method] = method
        dof = max(1, n - length(pairs))
        return SpatialFitResult(
            :spatial_lag,
            pairs,
            se,
            vcov_label,
            resid,
            fitted,
            n,
            dof,
            ρ,
            :rho,
            diag,
            warnings,
            nothing,
        )
    elseif model_type == "spatial_error"
        out = fit_sem_ml(ys, Xs, W, x_colnames)
        out isa MetricaBase.ModelError && return out
        pairs, se, fitted, resid, λ, ll = out
        mor = moran_residuals(resid, W)
        merge!(diag, mor)
        diag[:lambda] = λ
        dof = max(1, n - length(pairs))
        return SpatialFitResult(
            :spatial_error,
            pairs,
            se,
            "Gaussian ML（SEM）",
            resid,
            fitted,
            n,
            dof,
            λ,
            :lambda,
            diag,
            warnings,
            ll,
        )
    elseif model_type == "spatial_slx"
        out = fit_slx_ols(ys, Xs, W, x_colnames)
        out isa MetricaBase.ModelError && return out
        pairs, se, fitted, resid = out
        mor = moran_residuals(resid, W)
        merge!(diag, mor)
        direct, indirect, total, method = slx_effects(pairs, x_colnames)
        diag[:direct_effects] = direct
        diag[:indirect_effects] = indirect
        diag[:total_effects] = total
        diag[:effects_method] = method
        dof = max(1, n - length(pairs))
        return SpatialFitResult(
            :spatial_slx,
            pairs,
            se,
            "OLS（SLX，含 WX）",
            resid,
            fitted,
            n,
            dof,
            0.0,
            :none,
            diag,
            warnings,
            nothing,
        )
    elseif model_type == "spatial_sdm"
        out = fit_sdm_2sls(ys, Xs, W, x_colnames; vcov_kind=vcov_sym == :HC1 ? :HC1 : :classical)
        out isa MetricaBase.ModelError && return out
        pairs, se, fitted, resid, rho, theta = out
        mor = moran_residuals(resid, W)
        merge!(diag, mor)
        diag[:rho] = rho
        theta_dict = Dict{String, Float64}()
        for (k, cn) in enumerate(x_colnames[2:end])
            theta_dict[String(cn)] = k <= length(theta) ? theta[k] : 0.0
        end
        eff = sdm_effects(rho, theta_dict, W, x_colnames[2:end])
        if !(eff isa MetricaBase.ModelError)
            direct_eff, indirect_eff, total_eff, method_eff = eff
            diag[:direct_effects] = direct_eff
            diag[:indirect_effects] = indirect_eff
            diag[:total_effects] = total_eff
            diag[:effects_method] = method_eff
        end
        dof = max(1, n - length(pairs))
        return SpatialFitResult(:spatial_sdm, pairs, se, vcov_label,
                               resid, fitted, n, dof, rho, :rho, diag, warnings, nothing)
    elseif model_type == "spatial_sdem"
        out = fit_sdem_ml(ys, Xs, W, x_colnames)
        out isa MetricaBase.ModelError && return out
        pairs, se, fitted, resid, lambda, ll = out
        mor = moran_residuals(resid, W)
        merge!(diag, mor)
        diag[:lambda] = lambda
        dof = max(1, n - length(pairs))
        return SpatialFitResult(:spatial_sdem, pairs, se,
            "Gaussian ML（SDEM）", resid, fitted, n, dof,
            lambda, :lambda, diag, warnings, ll)
    elseif model_type == "spatial_sac"
        out = fit_sac_gs2sls(ys, Xs, W, x_colnames)
        out isa MetricaBase.ModelError && return out
        pairs, se, fitted, resid, rho, lambda = out
        mor = moran_residuals(resid, W)
        merge!(diag, mor)
        diag[:rho] = rho
        diag[:lambda] = lambda
        eff = sar_effects(rho, pairs, W, x_colnames)
        if !(eff isa MetricaBase.ModelError)
            direct_eff, indirect_eff, total_eff, method_eff = eff
            diag[:direct_effects] = direct_eff
            diag[:indirect_effects] = indirect_eff
            diag[:total_effects] = total_eff
            diag[:effects_method] = method_eff
        end
        dof = max(1, n - length(pairs))
        return SpatialFitResult(:spatial_sac, pairs, se,
            "GS2SLS（SAC）", resid, fitted, n, dof,
            rho, :rho, diag, warnings, nothing)
    else
        return MetricaBase.ModelError(
            :spatial_unknown_model,
            "未知空间模型类型",
            model_type,
            "支持 spatial_lag、spatial_error、spatial_slx、spatial_sdm、spatial_sdem、spatial_sac。",
        )
    end
end

function basename_split(path::AbstractString)::String
    p = replace(String(path), '\\' => '/')
    parts = split(p, '/')
    return String(parts[end])
end
