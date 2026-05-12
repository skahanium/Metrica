# === 双向固定效应吸收算法 (TWFE) =============================================
# 交替投影法：Entity-demean → Time-demean → 迭代至收敛

function fit_twfe(X::Matrix{Float64}, y::Vector{Float64},
                   id::Vector, time::Vector;
                   max_iter::Int=10, tol::Float64=1e-8,
                   has_intercept::Bool=true)
    # 移除截距列（TWFE 会吸收它）
    X_work = has_intercept ? X[:, 2:end] : X
    nobs, p = size(X_work)
    unique_ids = unique(id)
    unique_times = unique(time)
    n_id = length(unique_ids)
    n_time = length(unique_times)

    # 初始化
    y_demeaned = copy(y)
    X_demeaned = copy(X_work)

    for iter in 1:max_iter
        y_prev = copy(y_demeaned)
        X_prev = copy(X_demeaned)

        # Step 1: Entity-demean
        for gid in unique_ids
            mask = id .== gid
            y_demeaned[mask] .-= mean(y_demeaned[mask])
            for j in 1:p
                X_demeaned[mask, j] .-= mean(X_demeaned[mask, j])
            end
        end

        # Step 2: Time-demean
        for t in unique_times
            mask = time .== t
            y_demeaned[mask] .-= mean(y_demeaned[mask])
            for j in 1:p
                X_demeaned[mask, j] .-= mean(X_demeaned[mask, j])
            end
        end

        # 收敛判定
        change = norm(y_demeaned - y_prev) + norm(X_demeaned - X_prev)
        if change < tol * (norm(y) + norm(X_work) + 1.0)
            break
        end
    end

    # OLS on demeaned data
    coefficients = X_demeaned \ y_demeaned
    fitted = X_demeaned * coefficients
    residuals = y_demeaned - fitted

    # 自由度校正
    dof_absorbed = (n_id - 1) + (n_time - 1)
    dof = nobs - p - dof_absorbed
    dof = max(dof, 1)

    sigma2 = sum(abs2, residuals) / dof
    XtX = X_demeaned' * X_demeaned
    XtX_inv = try inv(XtX) catch; pinv(XtX) end
    vcov = sigma2 * XtX_inv
    vcov = (vcov + vcov') ./ 2
    stderror = sqrt.(max.(diag(vcov), 0.0))

    return (coefficients=coefficients, fitted=fitted, residuals=residuals,
            vcov=vcov, stderror=stderror, dof=dof, nobs=nobs,
            X_demeaned=X_demeaned, XtX_inv=XtX_inv)
end
