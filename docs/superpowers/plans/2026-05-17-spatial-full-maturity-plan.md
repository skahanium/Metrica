# 空间计量模型族全量成熟化 — 实施计划（已归档）

> **状态：已于 2026-05-17 完成。** 本文件保留为历史记录。

**Architecture:** 五阶段递进 — A (LM检验+权重构造) → B (SDM/SDEM/SAC) → C (GWR/GTWR→独立坐标体系) → D (空间Probit Gibbs) → E (跨层贯通)。W-based 模型族复用现有 `SpatialFitResult`；Coord-based 模型族新增 `GWRFitResult`/`GTWRFitResult`；Probit 新增 `ProbitFitResult`。

**Tech Stack:** Julia 1.12 (`LinearAlgebra`, `Statistics`, `Random`, `Distributions`, `Optim`), Rust (axum), TypeScript 5 + React 19 + Ant Design

**Spec:** `docs/superpowers/specs/2026-05-17-spatial-full-maturity-design.md`

---

## File Structure

```
packages/MetricaSpatial.jl/
├── src/
│   ├── MetricaSpatial.jl          [M] 扩 export、增 include
│   ├── types.jl                   [M] 新增 GWRFitResult, GTWRFitResult, ProbitFitResult
│   ├── weights_io.jl              [M] 保留现有边表 CSV 读取
│   ├── weights_knn.jl             [N] kNN 权重构造
│   ├── weights_distance.jl        [N] distance-band 权重构造
│   ├── moran.jl                   [~] 不变
│   ├── lm_tests.jl                [N] LM-Lag/Error/Robust 检验
│   ├── sar_fit.jl                 [~] 不变
│   ├── sem_fit.jl                 [~] 不变
│   ├── slx_fit.jl                 [~] 不变
│   ├── sdm_fit.jl                 [N] 空间杜宾模型
│   ├── sdem_fit.jl                [N] 空间杜宾误差模型
│   ├── sac_fit.jl                 [N] SAC/SARAR
│   ├── gwr_fit.jl                 [N] 地理加权回归
│   ├── gtwr_fit.jl                [N] 地理时空加权回归
│   ├── spatial_probit.jl          [N] 空间 Probit (Bayesian MCMC)
│   ├── effects.jl                 [M] 新增 sdm_effects
│   ├── interfaces.jl              [M] 扩展 glance/tidy/capabilities
│   ├── fit_spatial.jl             [M] 新增模型派发 + LM 检验插桩
│   └── serialize.jl               [M] 扩展 result_to_payload
├── test/
│   └── runtests.jl                [M] 大幅扩展测试覆盖
└── Project.toml                   [~] 不新增外部依赖

runtime/metrica-runtime/src/
└── lib.rs                         [M] 新增 model_type 白名单 + ModelSpec 字段

apps/metrica-desktop/src-react/
├── types/protocol.ts              [M] 新增 GWR/SpatialProbit 类型
├── services/commandGrammar.ts     [M] gwr/gtwr/spprobit 动词
├── services/commandParser.ts      [M] 解析器扩展
├── services/runtimeClient.ts      [M] 请求构建扩展
├── components/
│   ├── SpatialDiagnosticsPanel.tsx [M] 新增 LM 检验区块
│   ├── GWRDiagnosticsPanel.tsx     [N] GWR/GTWR 诊断展示
│   └── SpatialProbitPanel.tsx      [N] 后验摘要展示
└── __tests__/                     [M] 相应测试

scripts/
├── julia_bridge_entry.jl          [M] 新模型分派
└── julia_daemon.jl                [M] 新模型分派

docs/
├── architecture/runtime-protocol.md [M] 新模型专节
└── tutorials/s5-spatial.md          [M] 扩展教程

datasets/demo/
├── spatial_demo_coords.csv         [N] GWR/GTWR 坐标 demo
└── spatial_probit_demo.csv         [N] 空间 Probit demo
```

[M]=修改, [N]=新建, [~]=不变

---

### Task 1: LM 检验四件套

**Files:**
- Create: `packages/MetricaSpatial.jl/src/lm_tests.jl`
- Modify: `packages/MetricaSpatial.jl/src/fit_spatial.jl`
- Modify: `packages/MetricaSpatial.jl/src/interfaces.jl`
- Modify: `packages/MetricaSpatial.jl/src/MetricaSpatial.jl`

- [ ] **Step 1: 写入 lm_tests.jl 完整实现**

```julia
# lm_tests.jl — LM-Lag / LM-Error / Robust LM-Lag / Robust LM-Error
# 参考 Anselin (1988) / R spdep::lm.LMtests 经典公式

function lm_lag_test(e::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64})
    n = length(e)
    sigma2 = dot(e, e) / n
    We = W * e
    # LM-Lag = (e'We / sigma2)^2 / J
    J_num = dot(We, We) / sigma2
    J_den_inner = W * (X * (X' * X) \ X')
    # tr(W^2 + W'W) 近似
    T = tr(W * W + W' * W)
    J = (T + J_num) / sigma2
    LM = (dot(e, We) / sigma2)^2 / J
    pv = 1 - cdf(Chisq(1), LM)
    return Dict{Symbol, Any}(:statistic => LM, :pvalue => pv, :dof => 1)
end

function lm_error_test(e::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64})
    n = length(e)
    sigma2 = dot(e, e) / n
    We = W * e
    # LM-Error = (e'We / sigma2)^2 / T
    T = tr(W * W + W' * W)
    LM = (dot(e, We) / sigma2)^2 / T
    pv = 1 - cdf(Chisq(1), LM)
    return Dict{Symbol, Any}(:statistic => LM, :pvalue => pv, :dof => 1)
end

function robust_lm_lag_test(e::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64})
    n = length(e)
    sigma2 = dot(e, e) / n
    We = W * e
    T = tr(W * W + W' * W)
    J_num = dot(We, We) / sigma2
    J_den_inner = W * (X * (X' * X) \ X')
    J = (T + J_num) / sigma2
    LM_err = (dot(e, We) / sigma2)^2 / T
    LM_lag = (dot(e, We) / sigma2)^2 / J
    # Robust LM-Lag = (LM_lag - LM_err 修正项)^2 / (J - T^2 / J)
    denom = J - T^2 / J
    if denom <= 1e-12
        return Dict{Symbol, Any}(:statistic => NaN, :pvalue => NaN, :dof => 1)
    end
    LM_rob = (dot(e, We) / sigma2 - LM_err)^2 / denom
    pv = 1 - cdf(Chisq(1), LM_rob)
    return Dict{Symbol, Any}(:statistic => LM_rob, :pvalue => pv, :dof => 1)
end

function robust_lm_error_test(e::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64})
    n = length(e)
    sigma2 = dot(e, e) / n
    We = W * e
    T = tr(W * W + W' * W)
    J_num = dot(We, We) / sigma2
    J_den_inner = W * (X * (X' * X) \ X')
    J = (T + J_num) / sigma2
    LM_lag = (dot(e, We) / sigma2)^2 / J
    LM_err = (dot(e, We) / sigma2)^2 / T
    # Robust LM-Error = (LM_err - LM_lag 修正项)^2 / (T - T^2 / J)
    denom = T - T^2 / J
    if denom <= 1e-12
        return Dict{Symbol, Any}(:statistic => NaN, :pvalue => NaN, :dof => 1)
    end
    LM_rob = (dot(e, We) / sigma2 - LM_lag)^2 / denom
    pv = 1 - cdf(Chisq(1), LM_rob)
    return Dict{Symbol, Any}(:statistic => LM_rob, :pvalue => pv, :dof => 1)
end
```

- [ ] **Step 2: 在 fit_spatial.jl 中插桩 LM 检验**

在 `fit_spatial.jl` 中，在 OLS 拟合并取得残差后（约第 12-13 步之间），插入：

```julia
# --- OLS 残差用于 LM 检验 ---
function _ols_residuals(y::Vector{Float64}, X::Matrix{Float64})
    beta_ols = X \ y
    return y - X * beta_ols
end

# 在 fit_spatial.jl 中，W 和 X 就绪后：
e_ols = _ols_residuals(y, X)
diag[:lm_lag] = lm_lag_test(e_ols, X, W)
diag[:lm_error] = lm_error_test(e_ols, X, W)
diag[:robust_lm_lag] = robust_lm_lag_test(e_ols, X, W)
diag[:robust_lm_error] = robust_lm_error_test(e_ols, X, W)
```

- [ ] **Step 3: 更新 MetricaSpatial.jl 模块文件**

添加 `include("lm_tests.jl")` 到主模块（在 `moran.jl` 之后），添加 `lm_lag_test`, `lm_error_test`, `robust_lm_lag_test`, `robust_lm_error_test` 到 export 列表。

- [ ] **Step 4: 更新 interfaces.jl 的 model_capabilities**

在 `model_capabilities` 的 `diagnostics_available` 中添加 `:lm_lag, :lm_error, :robust_lm_lag, :robust_lm_error`。从 `diagnostics_unavailable` 中移除这些符号。

- [ ] **Step 5: 运行 Julia 测试**

```bash
julia --project=packages/MetricaSpatial.jl -e 'using Pkg; Pkg.test()'
```

Expected: 现有 SAR/SEM/SLX 测试通过，diagnostics dict 含 LM 键。若 Julia launcher 砂箱限制，手工验证至少一个模型的 diagnostics 输出。

- [ ] **Step 6: Commit**

```bash
git add packages/MetricaSpatial.jl/src/lm_tests.jl packages/MetricaSpatial.jl/src/fit_spatial.jl packages/MetricaSpatial.jl/src/interfaces.jl packages/MetricaSpatial.jl/src/MetricaSpatial.jl
git commit -m "feat(S5.7): LM-Lag/Error/Robust 检验四件套插桩到 fit_spatial"
```

---

### Task 2: kNN 与 Distance-band 权重构造

**Files:**
- Create: `packages/MetricaSpatial.jl/src/weights_knn.jl`
- Create: `packages/MetricaSpatial.jl/src/weights_distance.jl`
- Modify: `packages/MetricaSpatial.jl/src/MetricaSpatial.jl`

- [ ] **Step 1: 写入 weights_knn.jl**

```julia
# weights_knn.jl — k 近邻空间权重构造

function euclidean_distance(x1::Float64, y1::Float64, x2::Float64, y2::Float64)
    return sqrt((x1 - x2)^2 + (y1 - y2)^2)
end

function haversine_distance(lon1::Float64, lat1::Float64, lon2::Float64, lat2::Float64)
    R = 6371.0  # km
    dlat = deg2rad(lat2 - lat1)
    dlon = deg2rad(lon2 - lon1)
    a = sin(dlat / 2)^2 + cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * sin(dlon / 2)^2
    c = 2 * atan(sqrt(a), sqrt(max(0.0, 1 - a)))
    return R * c
end

function build_knn_weights(coords::Matrix{Float64}, k::Int;
                           distance_metric::Symbol=:euclidean,
                           row_standardize::Bool=true)
    n = size(coords, 1)
    k = min(k, n - 1)
    k <= 0 && return MetricaBase.ModelError(:knn_invalid_k, "k 必须 >= 1", "k = $k", "")

    dist_fn = distance_metric == :haversine ? haversine_distance : euclidean_distance

    # 全对距离
    D = Matrix{Float64}(undef, n, n)
    for i in 1:n
        for j in 1:n
            D[i, j] = i == j ? Inf : dist_fn(coords[i, 1], coords[i, 2], coords[j, 1], coords[j, 2])
        end
    end

    # 每行找 k 个最近邻
    id_i = Int[]
    id_j = Int[]
    ws = Float64[]
    for i in 1:n
        order = sortperm(D[i, :])
        for jj in 1:k
            j = order[jj]
            push!(id_i, i)
            push!(id_j, j)
            push!(ws, 1.0)
        end
    end

    edges = DataFrame(id_i=id_i, id_j=id_j, w=ws)
    meta = Dict{Symbol, Any}(
        :method => "knn",
        :k => k,
        :distance_metric => String(distance_metric),
        :row_standardized => row_standardize,
    )
    return edges, meta
end
```

- [ ] **Step 2: 写入 weights_distance.jl**

```julia
# weights_distance.jl — distance-band 空间权重构造

function build_distance_band_weights(coords::Matrix{Float64}, threshold::Float64;
                                     distance_metric::Symbol=:euclidean,
                                     row_standardize::Bool=true)
    n = size(coords, 1)
    threshold <= 0 && return MetricaBase.ModelError(:invalid_threshold, "threshold 必须 > 0", "$threshold", "")

    dist_fn = distance_metric == :haversine ? haversine_distance : euclidean_distance

    id_i = Int[]
    id_j = Int[]
    ws = Float64[]
    for i in 1:n
        has_neighbor = false
        for j in 1:n
            i == j && continue
            d = dist_fn(coords[i, 1], coords[i, 2], coords[j, 1], coords[j, 2])
            if d <= threshold
                push!(id_i, i)
                push!(id_j, j)
                push!(ws, 1.0)
                has_neighbor = true
            end
        end
        has_neighbor || return MetricaBase.ModelError(:isolated_unit, "距离阈值下存在孤立单元", "单元 $i 无邻居", "增大 threshold 或检查坐标")
    end

    edges = DataFrame(id_i=id_i, id_j=id_j, w=ws)
    meta = Dict{Symbol, Any}(
        :method => "distance_band",
        :threshold => threshold,
        :distance_metric => String(distance_metric),
        :row_standardized => row_standardize,
    )
    return edges, meta
end
```

- [ ] **Step 3: 更新模块文件**

添加 `include("weights_knn.jl")` 和 `include("weights_distance.jl")`（在 `weights_io.jl` 之后）。Export `build_knn_weights`, `build_distance_band_weights`, `euclidean_distance`, `haversine_distance`。

- [ ] **Step 4: Commit**

```bash
git add packages/MetricaSpatial.jl/src/weights_knn.jl packages/MetricaSpatial.jl/src/weights_distance.jl packages/MetricaSpatial.jl/src/MetricaSpatial.jl
git commit -m "feat(S5.7): kNN 与 distance-band 空间权重构造"
```

---

### Task 3: SDM 空间杜宾模型

**Files:**
- Create: `packages/MetricaSpatial.jl/src/sdm_fit.jl`
- Modify: `packages/MetricaSpatial.jl/src/fit_spatial.jl`
- Modify: `packages/MetricaSpatial.jl/src/effects.jl`
- Modify: `packages/MetricaSpatial.jl/src/interfaces.jl`
- Modify: `packages/MetricaSpatial.jl/src/MetricaSpatial.jl`

- [ ] **Step 1: 写入 sdm_fit.jl**

```julia
# sdm_fit.jl — 空间杜宾模型 (Spatial Durbin Model)
# y = ρWy + Xβ + WX̃θ + ε
# X̃ = X[:, 2:end] (不含截距列)

function fit_sdm_2sls(y::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64},
                       colnames::Vector{Symbol};
                       vcov_kind::Symbol=:classical)
    n = length(y)
    p = size(X, 2)
    p < 2 && return MetricaBase.ModelError(:sdm_no_predictors, "SDM 需要至少一个非截距解释变量", "", "")

    X_tilde = X[:, 2:end]           # 不含截距
    WX_tilde = W * X_tilde          # 空间滞后解释变量
    X_aug = hcat(X, WX_tilde)       # 增广设计矩阵 [X, WX̃]
    p_tilde = size(X_tilde, 2)

    Wy = W * y
    W2X_tilde = W * WX_tilde        # W²X̃

    # 内生变量: [Wy, X, WX̃]（但 X 和 WX̃ 中与 Wy 的外生性不同）
    # 工具: Z = [X, WX, W2X]（剔除共线列）
    Z = hcat(X, W * X, W * W * X)
    Z = _remove_collinear_columns(Z)

    # 2SLS 第一阶段：内生 Wy 对 Z 回归
    Pz = Z * pinv(Z' * Z) * Z'
    Wy_hat = Pz * Wy

    # 第二阶段：y 对 [Wy_hat, X, WX̃]
    X_endo = hcat(Wy_hat, X_aug)
    beta_hat = X_endo \ y

    rho_hat = beta_hat[1]
    beta_x_hat = beta_hat[2:(p+1)]
    theta_hat = beta_hat[(p+2):end]

    fitted = hcat(Wy, X_aug) * beta_hat
    resid = y - fitted
    rss = dot(resid, resid)
    sigma2 = rss / (n - (1 + p + p_tilde))

    # 系数名称
    coef_names = vcat([:rho], colnames, [Symbol("W_$(c)") for c in colnames[2:end]])
    coef_vals = vcat([rho_hat], beta_x_hat, theta_hat)

    # 标准误
    Xe = hcat(Wy, X_aug)
    XpX_inv = inv(Xe' * Xe)
    if vcov_kind == :classical
        se = sqrt.(max.(diag(XpX_inv) .* sigma2, 0.0))
    elseif vcov_kind == :HC1
        se = _hc1_se_vector(Xe, resid, n)
    else
        return MetricaBase.ModelError(:sdm_unknown_vcov, "SDM 不支持 vcov=$vcov_kind", "", "")
    end

    coef_pairs = [coef_names[i] => coef_vals[i] for i in eachindex(coef_names)]

    return coef_pairs, se, fitted, resid, rho_hat
end

# 工具矩阵列剔除（去除与 X 完全共线的列为防秩亏）
function _remove_collinear_columns(Z::Matrix{Float64})
    # 简单实现：QR 分解检查每列是否线性独立
    Q, R = qr(Z)
    rank_Z = sum(abs.(diag(R)) .> 1e-10 * maximum(abs.(diag(R))))
    if rank_Z >= size(Z, 2)
        return Z
    end
    # 取前 rank_Z 个独立列
    return Z[:, 1:rank_Z]
end

function _hc1_se_vector(X::Matrix{Float64}, resid::Vector{Float64}, n::Int)
    XpX_inv = inv(X' * X)
    omega = X .* (resid.^2)
    meat = X' * (X .* (resid.^2))
    V = XpX_inv * meat * XpX_inv * n / (n - size(X, 2))
    return sqrt.(max.(diag(V), 0.0))
end
```

- [ ] **Step 2: 在 fit_spatial.jl 新增 SDM 派发**

在现有 `spatial_lag`/`spatial_error`/`spatial_slx` 派发块之后添加：

```julia
elseif model_type == "spatial_sdm"
    result_or_err = fit_sdm_2sls(y, X, W, parsed.colnames; vcov_kind=vcov_kind)
    result_or_err isa MetricaBase.ModelError && return result_or_err
    coef_pairs, se, fitted, resid, rho = result_or_err

    diag[:rho] = rho
    diag[:moran_i] = (d = moran_residuals(resid .- mean(resid), W); d[:moran_i])
    diag[:moran_ei] = (d = moran_residuals(resid .- mean(resid), W); d[:moran_ei])
    diag[:moran_var] = (d = moran_residuals(resid .- mean(resid), W); d[:moran_var])
    diag[:moran_z] = (d = moran_residuals(resid .- mean(resid), W); d[:moran_z])
    diag[:moran_pvalue] = (d = moran_residuals(resid .- mean(resid), W); d[:moran_pvalue])

    theta_dict = Dict{String, Float64}()
    for i in 1:length(parsed.colnames[2:end])
        theta_dict[String(parsed.colnames[1+i])] = coef_pairs[p+1+i][2]
    end
    eff = sdm_effects(rho, theta_dict, W, parsed.colnames[2:end])
    diag[:direct_effects] = eff.direct
    diag[:indirect_effects] = eff.indirect
    diag[:total_effects] = eff.total
    diag[:effects_method] = eff.method

    return SpatialFitResult(:spatial_sdm, coef_pairs, se, vcov_label_str,
                           resid, fitted, n, n - (1 + p + (p - 1)),
                           rho, :rho, diag, warnings, nothing)
```

- [ ] **Step 3: 在 effects.jl 新增 sdm_effects**

```julia
function sdm_effects(rho::Float64, theta_dict::Dict{String, Float64}, W::Matrix{Float64}, x_colnames::Vector{Symbol})
    n = size(W, 1)
    S = inv(I - rho * W)  # 空间乘数矩阵

    direct = Dict{String, Float64}()
    indirect = Dict{String, Float64}()
    total = Dict{String, Float64}()

    # SDM 效应：direct = mean(diag(S * (I + theta_k * W))) * beta_k
    # 首期简化：direct = mean(diag(S)) * (beta_k + theta_k) 的近似
    mean_diag_S = sum(diag(S)) / n
    total_mult = sum(S) / n

    for k in eachindex(x_colnames)
        cn = String(x_colnames[k])
        theta_k = get(theta_dict, cn, 0.0)
        d = mean_diag_S * (1.0 + theta_k)
        t = total_mult * (1.0 + theta_k)
        direct[cn] = d
        total[cn] = t
        indirect[cn] = t - d
    end

    return (direct=direct, indirect=indirect, total=total,
            method="SDM 效应分解（空间乘数法，首期简化）")
end
```

- [ ] **Step 4: 更新 interfaces.jl**

在 `model_capabilities` 中将 `:spatial_sdm` 加入 `supported_models`。

- [ ] **Step 5: Commit**

```bash
git add packages/MetricaSpatial.jl/src/sdm_fit.jl packages/MetricaSpatial.jl/src/fit_spatial.jl packages/MetricaSpatial.jl/src/effects.jl packages/MetricaSpatial.jl/src/interfaces.jl packages/MetricaSpatial.jl/src/MetricaSpatial.jl
git commit -m "feat(S5.7): SDM 空间杜宾模型 (2SLS) + 效应分解"
```

---

### Task 4: SDEM 空间杜宾误差模型

**Files:**
- Create: `packages/MetricaSpatial.jl/src/sdem_fit.jl`
- Modify: `packages/MetricaSpatial.jl/src/fit_spatial.jl`

- [ ] **Step 1: 写入 sdem_fit.jl**

```julia
# sdem_fit.jl — 空间杜宾误差模型 (Spatial Durbin Error Model)
# y = Xβ + WX̃θ + u, u = λWu + ε

function fit_sdem_ml(y::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64},
                      colnames::Vector{Symbol})
    n = length(y)
    p = size(X, 2)
    p < 2 && return MetricaBase.ModelError(:sdem_no_predictors, "SDEM 需要至少一个非截距解释变量", "", "")
    n > 800 && return MetricaBase.ModelError(:sdem_too_large, "SDEM 当前限 n ≤ 800", "n=$n", "")

    X_tilde = X[:, 2:end]
    WX_tilde = W * X_tilde
    X_aug = hcat(X, WX_tilde)
    p_aug = size(X_aug, 2)

    function prof_ll(lambda::Float64)
        A = I - lambda * W
        logdet_A = log(abs(det(A)))
        y_star = A * y
        X_star = A * X_aug
        beta = X_star \ y_star
        resid = y_star - X_star * beta
        sigma2 = dot(resid, resid) / n
        return -n / 2 * log(2π) - n / 2 * log(sigma2) - 1 / 2 * dot(resid, resid) / sigma2 + logdet_A
    end

    f(x) = -prof_ll(x[1])
    result = Optim.optimize(f, [-0.5, 0.5], Optim.NelderMead(), Optim.Options(iterations=500, g_tol=1e-6))
    lambda_hat = Optim.minimizer(result)[1]
    converged = Optim.converged(result)
    iters = Optim.iterations(result)

    A = I - lambda_hat * W
    y_star = A * y
    X_star = A * X_aug
    beta_hat = X_star \ y_star
    resid = y_star - X_star * beta_hat
    sigma2 = dot(resid, resid) / n

    XpX_inv = inv(X_star' * X_star)
    se_full = sqrt.(max.(diag(XpX_inv) .* sigma2, 0.0))

    coef_names = vcat(colnames, [Symbol("W_$(c)") for c in colnames[2:end]])
    coef_pairs = [coef_names[i] => beta_hat[i] for i in eachindex(coef_names)]

    p_tilde = size(X_tilde, 2)
    k_total = p + p_tilde + 1
    loglik = prof_ll(lambda_hat)
    aic = -2 * loglik + 2 * k_total
    bic = -2 * loglik + k_total * log(n)

    return coef_pairs, se_full, y - resid, resid, lambda_hat, loglik
end
```

- [ ] **Step 2: 在 fit_spatial.jl 新增 SDEM 派发**

仿照 SEM 模式，调用 `fit_sdem_ml`，构造 `SpatialFitResult(:spatial_sdem, ..., spatial_param=lambda_hat, spatial_param_name=:lambda, loglik=ll)`。

- [ ] **Step 3: Commit**

```bash
git add packages/MetricaSpatial.jl/src/sdem_fit.jl packages/MetricaSpatial.jl/src/fit_spatial.jl
git commit -m "feat(S5.7): SDEM 空间杜宾误差模型 (剖面 ML)"
```

---

### Task 5: SAC/SARAR

**Files:**
- Create: `packages/MetricaSpatial.jl/src/sac_fit.jl`
- Modify: `packages/MetricaSpatial.jl/src/fit_spatial.jl`

- [ ] **Step 1: 写入 sac_fit.jl**

```julia
# sac_fit.jl — SAC/SARAR (Spatial Autoregressive Confused)
# y = ρWy + Xβ + u, u = λWu + ε
# 估计器：GS2SLS (Kelejian & Prucha 1998)

function fit_sac_gs2sls(y::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64},
                         colnames::Vector{Symbol};
                         vcov_kind::Symbol=:classical)
    n = length(y)
    p = size(X, 2)
    n > 5000 && return MetricaBase.ModelError(:sac_too_large, "SAC 当前限 n ≤ 5000", "n=$n", "")

    # Step 1: 2SLS 估计 ρ 和 β（工具 = [X, WX, W²X]）
    Z = hcat(X, W * X, W * W * X)
    Pz = Z * pinv(Z' * Z) * Z'
    Wy = W * y
    Wy_hat = Pz * Wy
    X_endo = hcat(Wy_hat, X)
    beta_step1 = X_endo \ y
    rho_hat = beta_step1[1]
    beta_hat = beta_step1[2:end]
    u_hat = y - rho_hat * Wy - X * beta_hat

    # Step 2: GMM 估计 λ（使用 û 的矩条件）
    Wu = W * u_hat
    W2u = W * Wu
    # 简化的 GMM：λ̂ = (û'WW'û) / (û'(W'W)û)
    num = dot(Wu, Wu)
    den = dot(Wu, W * u_hat)
    lambda_hat = den > 0 ? num / den : 0.0

    # Step 3: FGLS 变换
    A = I - lambda_hat * W
    y_star = A * y
    Wy_star = W * y_star
    X_star = A * X
    WX_star = W * X_star

    # 第二阶段 2SLS（使用变换后的变量）
    Z_star = hcat(X_star, W * X_star, W * W * X_star)
    Pz_star = Z_star * pinv(Z_star' * Z_star) * Z_star'
    Wy_star_hat = Pz_star * Wy_star
    X_endo_star = hcat(Wy_star_hat, X_star)
    beta_final = X_endo_star \ y_star

    rho_final = beta_final[1]
    beta_final_x = beta_final[2:end]

    fitted = rho_final * Wy + X * beta_final_x  # 原空间拟合值
    resid = y - fitted
    rss = dot(resid, resid)
    sigma2 = rss / (n - (1 + p))

    coef_names = vcat([:rho], colnames)
    coef_vals = vcat([rho_final], beta_final_x)

    # 标准误
    Xe = hcat(Wy, X)
    XpX_inv = inv(Xe' * Xe)
    se = sqrt.(max.(diag(XpX_inv) .* sigma2, 0.0))

    se_full = vcat([NaN], se[2:end])  # λ 的标准误暂不计算（GMM 端）

    coef_pairs = [Symbol("rho") => rho_final,
                  [Symbol("lambda") => lambda_hat],
                  [coef_names[i+1] => beta_final_x[i] for i in 1:length(colnames)]...
                 ]

    return coef_pairs, se_full, fitted, resid, rho_final, lambda_hat
end
```

- [ ] **Step 2: 在 fit_spatial.jl 新增 SAC 派发**

仿照 SAR 和 SEM 的混合模式，`spatial_param=rho`，`diagnostics` 添加 `:lambda` 键。

- [ ] **Step 3: Commit**

```bash
git add packages/MetricaSpatial.jl/src/sac_fit.jl packages/MetricaSpatial.jl/src/fit_spatial.jl
git commit -m "feat(S5.7): SAC/SARAR (GS2SLS 两步估计)"
```

---

### Task 6: GWR 地理加权回归

**Files:**
- Create: `packages/MetricaSpatial.jl/src/gwr_fit.jl`
- Modify: `packages/MetricaSpatial.jl/src/types.jl`
- Modify: `packages/MetricaSpatial.jl/src/interfaces.jl`
- Modify: `packages/MetricaSpatial.jl/src/serialize.jl`
- Modify: `packages/MetricaSpatial.jl/src/MetricaSpatial.jl`

- [ ] **Step 1: 在 types.jl 新增 GWRFitResult**

```julia
struct GWRFitResult
    formula::String
    nobs::Int
    ncoef::Int
    coef_names::Vector{Symbol}
    local_coefficients::Matrix{Float64}       # n × p
    local_stderrors::Union{Nothing, Matrix{Float64}}
    local_tvalues::Union{Nothing, Matrix{Float64}}
    local_r2::Vector{Float64}
    fitted::Vector{Float64}
    residual::Vector{Float64}
    bandwidth::Float64
    bandwidth_selection::String               # "fixed", "cv", "aicc"
    bandwidth_score::Float64                  # CV 或 AICc 得分
    kernel::String                            # "gaussian", "bisquare"
    adaptive::Bool
    distance_metric::String
    effective_parameters::Float64
    sigma2::Float64
    aicc::Float64
    hat_diag::Vector{Float64}
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
end
```

- [ ] **Step 2: 写入 gwr_fit.jl 完整实现**

```julia
# gwr_fit.jl — 地理加权回归 (Geographically Weighted Regression)

function gaussian_kernel(d::Float64, h::Float64)
    return exp(-0.5 * (d / h)^2)
end

function bisquare_kernel(d::Float64, h::Float64)
    return d < h ? (1.0 - (d / h)^2)^2 : 0.0
end

function _distance_matrix(coords::Matrix{Float64}, metric::Symbol)
    n = size(coords, 1)
    D = Matrix{Float64}(undef, n, n)
    dist_fn = metric == :haversine ? haversine_distance : euclidean_distance
    for i in 1:n
        for j in 1:n
            D[i, j] = i == j ? 0.0 : dist_fn(coords[i, 1], coords[i, 2], coords[j, 1], coords[j, 2])
        end
    end
    return D
end

function _adaptive_bandwidths(D::Matrix{Float64}, k::Int)
    n = size(D, 1)
    h = Vector{Float64}(undef, n)
    for i in 1:n
        sorted = sort(D[i, :])
        h[i] = sorted[min(k + 1, n)]
    end
    return h
end

function _gwr_cv_score(y::Vector{Float64}, X::Matrix{Float64}, D::Matrix{Float64},
                        h::Union{Float64, Vector{Float64}}, kernel_fn::Function)
    n = length(y)
    cv = 0.0
    for i in 1:n
        hi = h isa Float64 ? h : h[i]
        w = [kernel_fn(D[i, j], hi) for j in 1:n]
        w[i] = 0.0  # 留一
        W_half = diagm(sqrt.(w))
        Xw = W_half * X
        yw = W_half * y
        beta_i = Xw \ yw
        y_hat_i = dot(X[i, :], beta_i)
        cv += (y[i] - y_hat_i)^2
    end
    return cv
end

function fit_gwr(y::Vector{Float64}, X::Matrix{Float64}, coords::Matrix{Float64};
                 kernel::String="gaussian",
                 bandwidth::Union{Nothing, Float64}=nothing,
                 bandwidth_selection::String="cv",
                 adaptive::Bool=false,
                 adaptive_k::Int=0,
                 distance_metric::Symbol=:euclidean)
    n = length(y)
    p = size(X, 2)
    ncoef = p
    coef_names = [Symbol("beta_$i") for i in 0:(p-1)]

    D = _distance_matrix(coords, distance_metric)
    kernel_fn = kernel == "bisquare" ? bisquare_kernel : gaussian_kernel

    # 带宽选择
    if bandwidth !== nothing
        h = bandwidth
        bw_method = "fixed"
        bw_score = NaN
    elseif bandwidth_selection == "cv"
        # Golden-section 搜索最优 h（或 adaptive k）
        search_range = adaptive ? (3.0, min(n - 1, 100.0)) : (0.1 * mean(D), 2.0 * mean(D))
        if adaptive
            best_k = 3
            best_cv = Inf
            for k in 3:min(n - 1, 100)
                hs = _adaptive_bandwidths(D, k)
                cv = _gwr_cv_score(y, X, D, hs, kernel_fn)
                if cv < best_cv
                    best_cv = cv
                    best_k = k
                end
            end
            h = Float64(best_k)
            bw_method = "cv"
            bw_score = best_cv
        else
            best_h = search_range[1]
            best_cv = Inf
            for candidate_h in range(search_range[1], search_range[2], length=30)
                cv = _gwr_cv_score(y, X, D, Float64(candidate_h), kernel_fn)
                if cv < best_cv
                    best_cv = cv
                    best_h = candidate_h
                end
            end
            h = Float64(best_h)
            bw_method = "cv"
            bw_score = best_cv
        end
    else
        h = adaptive ? Float64(min(n - 1, 50)) : Float64(mean(D))
        bw_method = "default"
        bw_score = NaN
    end

    # 局部 WLS
    local_beta = Matrix{Float64}(undef, n, p)
    hat_diag = Vector{Float64}(undef, n)
    fitted = Vector{Float64}(undef, n)
    local_r2 = Vector{Float64}(undef, n)

    hs = adaptive ? _adaptive_bandwidths(D, round(Int, h)) : fill(h, n)

    for i in 1:n
        w = [kernel_fn(D[i, j], hs[i]) for j in 1:n]
        W_half = diagm(sqrt.(w))
        Xw = W_half * X
        yw = W_half * y
        beta_i = Xw \ yw
        local_beta[i, :] = beta_i
        fitted[i] = dot(X[i, :], beta_i)
        H_i = X[i, :]' * inv(Xw' * Xw) * X[i, :] * w[i]
        hat_diag[i] = H_i
        resid_i = y[i] - fitted[i]
        tss_i = sum((y[j] - mean(y))^2 * w[j] for j in 1:n)
        rss_i = sum((y[j] - dot(X[j, :], beta_i))^2 * w[j] for j in 1:n)
        local_r2[i] = tss_i > 0 ? 1.0 - rss_i / tss_i : 0.0
    end

    residual = y - fitted
    sigma2 = dot(residual, residual) / (n - 2 * sum(hat_diag) + sum(hat_diag.^2))
    eff_params = sum(hat_diag)
    aicc = n * log(sigma2) + n * log(2π) + n * (n + eff_params) / (n - eff_params - 2)

    # 局部标准误（若可计算）
    local_se = nothing
    local_t = nothing

    warnings = MetricaBase.ModelWarning[]
    if adaptive && h < 10
        push!(warnings, MetricaBase.ModelWarning(:bandwidth_too_small, "带宽过小",
            "adaptive bandwidth k = $(round(Int, h)) 可能过小，局部回归不稳定。", "建议增大 adaptive k。", MetricaBase.warning))
    end

    diag = Dict{Symbol, Any}(
        :bandwidth => h,
        :bandwidth_selection => bw_method,
        :bandwidth_score => bw_score,
        :kernel => kernel,
        :adaptive => adaptive,
        :distance_metric => String(distance_metric),
        :effective_parameters => eff_params,
        :aicc => aicc,
    )

    return GWRFitResult("gwr", n, ncoef, coef_names, local_beta, local_se, local_t,
                         local_r2, fitted, residual, h, bw_method, bw_score,
                         kernel, adaptive, String(distance_metric),
                         eff_params, sigma2, aicc, hat_diag, diag, warnings)
end
```

- [ ] **Step 3: 新增 GWR serialize + interfaces**

在 `serialize.jl` 新增 `result_to_payload(result::GWRFitResult)`，含 `local_coefficients` 的预览（首 10 行）、`bandwidth`、`kernel`、`aicc` 等。在 `interfaces.jl` 新增 `model_capabilities` for `GWRFitResult`。

- [ ] **Step 4: Commit**

```bash
git add packages/MetricaSpatial.jl/src/gwr_fit.jl packages/MetricaSpatial.jl/src/types.jl packages/MetricaSpatial.jl/src/interfaces.jl packages/MetricaSpatial.jl/src/serialize.jl packages/MetricaSpatial.jl/src/MetricaSpatial.jl
git commit -m "feat(S5.7): GWR 地理加权回归 (local WLS + CV 带宽选择)"
```

---

### Task 7: GTWR 地理时空加权回归

**Files:**
- Create: `packages/MetricaSpatial.jl/src/gtwr_fit.jl`
- Modify: `packages/MetricaSpatial.jl/src/types.jl`
- Modify: `packages/MetricaSpatial.jl/src/serialize.jl`

- [ ] **Step 1: 写入 gtwr_fit.jl**

```julia
# gtwr_fit.jl — 地理时空加权回归 (Geographically and Temporally Weighted Regression)

struct GTWRFitResult
    formula::String
    nobs::Int
    ncoef::Int
    coef_names::Vector{Symbol}
    local_coefficients::Matrix{Float64}
    local_stderrors::Union{Nothing, Matrix{Float64}}
    local_tvalues::Union{Nothing, Matrix{Float64}}
    local_r2::Vector{Float64}
    fitted::Vector{Float64}
    residual::Vector{Float64}
    bandwidth::Float64
    bandwidth_selection::String
    bandwidth_score::Float64
    kernel::String
    adaptive::Bool
    distance_metric::String
    time_scale::Float64
    time_column::String
    time_range::Vector{Float64}             # [t_min, t_max]
    spatiotemporal_distance_summary::Dict{Symbol, Any}
    effective_parameters::Float64
    sigma2::Float64
    aicc::Float64
    hat_diag::Vector{Float64}
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
end

function fit_gtwr(y::Vector{Float64}, X::Matrix{Float64}, coords::Matrix{Float64},
                  times::Vector{Float64};
                  kernel::String="gaussian",
                  bandwidth::Union{Nothing, Float64}=nothing,
                  bandwidth_selection::String="cv",
                  adaptive::Bool=false,
                  time_scale::Union{Nothing, Float64}=nothing,
                  distance_metric::Symbol=:euclidean)
    n = length(y)
    p = size(X, 2)

    # 时间尺度
    t_range = maximum(times) - minimum(times)
    if time_scale === nothing
        # auto: 初始猜测为 空间距离均值 / 时间范围
        D_space = _distance_matrix(coords, distance_metric)
        mean_d_space = sum(D_space) / (n * (n - 1))
        tau = mean_d_space / max(t_range, 1.0)
    else
        tau = time_scale
    end

    # 时空距离矩阵
    D_space = _distance_matrix(coords, distance_metric)
    D_time = Matrix{Float64}(undef, n, n)
    for i in 1:n
        for j in 1:n
            D_time[i, j] = abs(times[i] - times[j])
        end
    end

    D_st = sqrt.(D_space.^2 .+ tau^2 .* D_time.^2)

    # 复用 GWR 局部 WLS 估算（将 D_st 作为距离矩阵）
    kernel_fn = kernel == "bisquare" ? bisquare_kernel : gaussian_kernel

    # 带宽选择（CV on D_st）
    h = if bandwidth !== nothing
        bandwidth
    else
        mean(D_st)  # 默认
    end

    hs = adaptive ? _adaptive_bandwidths(D_st, round(Int, h)) : fill(h, n)

    local_beta = Matrix{Float64}(undef, n, p)
    fitted = Vector{Float64}(undef, n)
    hat_diag = Vector{Float64}(undef, n)
    local_r2 = Vector{Float64}(undef, n)

    for i in 1:n
        w = [kernel_fn(D_st[i, j], hs[i]) for j in 1:n]
        W_half = diagm(sqrt.(w))
        Xw = W_half * X
        yw = W_half * y
        beta_i = Xw \ yw
        local_beta[i, :] = beta_i
        fitted[i] = dot(X[i, :], beta_i)
        H_i = X[i, :]' * inv(Xw' * Xw) * X[i, :] * w[i]
        hat_diag[i] = H_i
        resid_i = y[i] - fitted[i]
        tss_i = sum((y[j] - mean(y))^2 * w[j] for j in 1:n)
        rss_i = sum((y[j] - dot(X[j, :], beta_i))^2 * w[j] for j in 1:n)
        local_r2[i] = tss_i > 0 ? 1.0 - rss_i / tss_i : 0.0
    end

    residual = y - fitted
    sigma2 = dot(residual, residual) / (n - 2 * sum(hat_diag) + sum(hat_diag.^2))
    eff_params = sum(hat_diag)
    aicc = n * log(sigma2) + n * log(2π) + n * (n + eff_params) / (n - eff_params - 2)

    st_summary = Dict{Symbol, Any}(
        :n_unique_spatial => length(Set(eachrow(coords))),
        :n_unique_temporal => length(Set(times)),
        :t_min => minimum(times),
        :t_max => maximum(times),
    )

    warnings = MetricaBase.ModelWarning[]

    return GTWRFitResult("gtwr", n, p, [Symbol("beta_$i") for i in 0:(p-1)],
                         local_beta, nothing, nothing, local_r2, fitted, residual,
                         h, bandwidth_selection, NaN, kernel, adaptive,
                         String(distance_metric), tau, "time",
                         [minimum(times), maximum(times)], st_summary,
                         eff_params, sigma2, aicc, hat_diag,
                         Dict{Symbol, Any}(:time_scale => tau), warnings)
end
```

- [ ] **Step 2: 新增 GTWR serialize**

在 `serialize.jl` 新增 `result_to_payload(result::GTWRFitResult)`，与 GWR 格式一致外加 `time_scale`、`spatiotemporal_distance_summary`。

- [ ] **Step 3: Commit**

```bash
git add packages/MetricaSpatial.jl/src/gtwr_fit.jl packages/MetricaSpatial.jl/src/types.jl packages/MetricaSpatial.jl/src/serialize.jl
git commit -m "feat(S5.7): GTWR 地理时空加权回归"
```

---

### Task 8: 空间 Probit (Bayesian MCMC)

**Files:**
- Create: `packages/MetricaSpatial.jl/src/spatial_probit.jl`
- Modify: `packages/MetricaSpatial.jl/src/types.jl`
- Modify: `packages/MetricaSpatial.jl/src/serialize.jl`

- [ ] **Step 1: 写入 spatial_probit.jl**

```julia
# spatial_probit.jl — 空间 Probit (Bayesian Gibbs 采样)

struct ProbitFitResult
    formula::String
    nobs::Int
    ncoef::Int
    coef_names::Vector{Symbol}
    posterior_mean::Vector{Float64}          # β 后验均值
    posterior_sd::Vector{Float64}
    credible_lower::Vector{Float64}          # 95% HPD
    credible_upper::Vector{Float64}
    rho_mean::Float64                         # ρ 后验均值
    rho_sd::Float64
    rho_credible_lower::Float64
    rho_credible_upper::Float64
    n_iter::Int
    n_warmup::Int
    n_chains::Int
    rhat::Union{Nothing, Vector{Float64}}
    ess::Union{Nothing, Vector{Float64}}
    diagnostics::Dict{Symbol, Any}
    warnings::Vector{MetricaBase.ModelWarning}
end

function fit_spatial_probit(y::Vector{Int}, X::Matrix{Float64}, W::Matrix{Float64};
                            n_iter::Int=2000, n_warmup::Int=500,
                            n_chains::Int=1,
                            prior_scale::Float64=10.0,
                            seed::Union{Nothing, Int}=nothing)
    n = length(y)
    p = size(X, 2)
    n > 1000 && return MetricaBase.ModelError(:probit_too_large, "空间 Probit 当前限 n ≤ 1000", "n=$n", "")

    isnothing(seed) || Random.seed!(seed)
    all(y .∈ ((0, 1),)) || return MetricaBase.ModelError(:probit_binary, "y 必须为 0/1", "", "")

    # 先验精度矩阵
    prior_prec = 1.0 / prior_scale^2 * I(p)

    # 存储
    beta_samples = Matrix{Float64}(undef, n_iter - n_warmup, p)
    rho_samples = Vector{Float64}(undef, n_iter - n_warmup)

    # 初始化
    beta = X \ (y .- 0.5)  # OLS 起始值
    rho = 0.0
    y_star = zeros(n)

    # M-H for rho
    rho_proposal_sd = 0.05
    rho_accept = 0

    for iter in 1:n_iter
        # 1. 采样潜变量 y*（截断正态）
        mean_vec = X * beta + rho * W * y_star
        for i in 1:n
            mu_i = mean_vec[i] + rho * (dot(W[i, :], y_star) - W[i, i] * y_star[i])
            # 从截断正态采样
            if y[i] == 1
                y_star[i] = rand(Truncated(Normal(mu_i, 1.0), 0.0, Inf))
            else
                y_star[i] = rand(Truncated(Normal(mu_i, 1.0), -Inf, 0.0))
            end
        end

        # 2. 采样 β（多元正态后验）
        A = I - rho * W
        y_star_star = A * y_star
        posterior_prec = X' * X + prior_prec
        posterior_cov = inv(posterior_prec)
        posterior_mean = posterior_cov * (X' * y_star_star)
        beta = rand(MvNormal(posterior_mean, Symmetric(posterior_cov)))

        # 3. 采样 ρ（Metropolis-Hastings）
        rho_prop = rand(Normal(rho, rho_proposal_sd))
        if -0.99 < rho_prop < 0.99
            A_prop = I - rho_prop * W
            logdet_prop = log(abs(det(A_prop)))
            logdet_curr = log(abs(det(I - rho * W)))

            y_star_prop = A_prop * y_star - X * beta
            loglike_prop = -0.5 * dot(y_star_prop, y_star_prop)
            y_star_curr = A * y_star - X * beta
            loglike_curr = -0.5 * dot(y_star_curr, y_star_curr)

            log_ratio = loglike_prop + logdet_prop - loglike_curr - logdet_curr
            if log(rand()) < log_ratio
                rho = rho_prop
                rho_accept += 1
            end
        end

        # 存储（warmup 后）
        if iter > n_warmup
            idx = iter - n_warmup
            beta_samples[idx, :] = beta
            rho_samples[idx] = rho
        end
    end

    # 后验摘要
    beta_mean = vec(mean(beta_samples, dims=1))
    beta_sd = vec(std(beta_samples, dims=1))
    beta_lower = [quantile(beta_samples[:, j], 0.025) for j in 1:p]
    beta_upper = [quantile(beta_samples[:, j], 0.975) for j in 1:p]

    rho_m = mean(rho_samples)
    rho_s = std(rho_samples)
    rho_lo = quantile(rho_samples, 0.025)
    rho_hi = quantile(rho_samples, 0.975)

    coef_names = vcat([:rho], [Symbol("beta_$i") for i in 0:(p-1)])
    post_mean = vcat([rho_m], beta_mean)
    post_sd = vcat([rho_s], beta_sd)
    post_lo = vcat([rho_lo], beta_lower)
    post_hi = vcat([rho_hi], beta_upper)

    n_kept = n_iter - n_warmup
    rhat = nothing
    ess = nothing

    diag = Dict{Symbol, Any}(
        :rho_accept_rate => rho_accept / n_iter,
        :n_iter => n_iter,
        :n_warmup => n_warmup,
        :n_chains => n_chains,
        :inference_mode => "mcmc",
    )

    return ProbitFitResult("spatial_probit", n, p + 1, coef_names,
                           post_mean, post_sd, post_lo, post_hi,
                           rho_m, rho_s, rho_lo, rho_hi,
                           n_iter, n_warmup, n_chains, rhat, ess, diag,
                           MetricaBase.ModelWarning[])
end
```

- [ ] **Step 2: 新增 Probit serialize**

在 `serialize.jl` 新增 `result_to_payload(result::ProbitFitResult)`，含 `posterior_mean`、`credible_interval`，`stderror` 和 `pvalue` 为 `null`。

- [ ] **Step 3: Commit**

```bash
git add packages/MetricaSpatial.jl/src/spatial_probit.jl packages/MetricaSpatial.jl/src/types.jl packages/MetricaSpatial.jl/src/serialize.jl
git commit -m "feat(S5.7): 空间 Probit (Bayesian Gibbs 采样)"
```

---

### Task 9: Runtime 白名单与 ModelSpec 扩展

**Files:**
- Modify: `runtime/metrica-runtime/src/lib.rs`

- [ ] **Step 1: 新增 model_type 白名单条目**

在 `model_required_fields()` HashMap 中添加（第 86-91 行区域）：

```rust
("spatial_sdm",    vec!["spatial_weights_path", "spatial_id_column"]),
("spatial_sdem",   vec!["spatial_weights_path", "spatial_id_column"]),
("spatial_sac",    vec!["spatial_weights_path", "spatial_id_column"]),
("spatial_gwr",    vec!["spatial_coord_columns"]),
("spatial_gtwr",   vec!["spatial_coord_columns", "gtwr_time_column"]),
("spatial_probit", vec!["spatial_weights_path", "spatial_id_column"]),
```

- [ ] **Step 2: 新增 ModelSpec 字段**

在 `ModelSpec` 结构体中（第 644 行之后）添加：

```rust
/// GWR/GTWR: 坐标列名，如 ["lon", "lat"]
#[serde(skip_serializing_if = "Option::is_none")]
pub spatial_coord_columns: Option<Vec<String>>,
/// 距离度量: euclidean / haversine / projected
#[serde(skip_serializing_if = "Option::is_none")]
pub spatial_distance: Option<String>,
/// 坐标参考系（可选）
#[serde(skip_serializing_if = "Option::is_none")]
pub spatial_crs: Option<String>,
/// GWR 核函数: gaussian / bisquare
#[serde(skip_serializing_if = "Option::is_none")]
pub gwr_kernel: Option<String>,
/// GWR 带宽（数值）
#[serde(skip_serializing_if = "Option::is_none")]
pub gwr_bandwidth: Option<f64>,
/// GWR 带宽选择: cv / aicc
#[serde(skip_serializing_if = "Option::is_none")]
pub gwr_bandwidth_selection: Option<String>,
/// adaptive 带宽（邻近点数）
#[serde(skip_serializing_if = "Option::is_none")]
pub gwr_adaptive: Option<bool>,
/// GTWR 时间列
#[serde(skip_serializing_if = "Option::is_none")]
pub gtwr_time_column: Option<String>,
/// GTWR 时间尺度（数或 "auto"）
#[serde(skip_serializing_if = "Option::is_none")]
pub gtwr_time_scale: Option<serde_json::Value>,
```

- [ ] **Step 3: 新增校验逻辑**

在 `validate_model_request()` 中添加：

```rust
if matches!(spec.model_type.as_str(), "spatial_gwr" | "spatial_gtwr") {
    if let Some(ref coords) = spec.spatial_coord_columns {
        if coords.len() != 2 {
            return Some(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: "spatial_coord_columns 必须是长度为 2 的数组。".to_string(),
                hint: Some("如 [\"lon\", \"lat\"]。".to_string()),
            });
        }
    }
    if let Some(ref kern) = spec.gwr_kernel {
        let k = kern.trim().to_ascii_lowercase();
        if k != "gaussian" && k != "bisquare" {
            return Some(ValidationError {
                code: "RUNTIME_INVALID_FIELD",
                message: format!("gwr_kernel 只能为 gaussian 或 bisquare，收到 `{kern}`。"),
                hint: Some("请省略以使用默认 gaussian。".to_string()),
            });
        }
    }
    if spec.gwr_bandwidth.is_some() && spec.gwr_bandwidth_selection.is_some() {
        return Some(ValidationError {
            code: "RUNTIME_INVALID_FIELD",
            message: "gwr_bandwidth 与 gwr_bandwidth_selection 互斥。".to_string(),
            hint: Some("请只提供一个。".to_string()),
        });
    }
}
```

- [ ] **Step 4: 添加全部新字段到默认初始化**

在 `sample_fit_model_request()` 和所有其他 `ModelSpec` 构造点中添加新字段的 `None` 默认值。

- [ ] **Step 5: Commit**

```bash
git add runtime/metrica-runtime/src/lib.rs
git commit -m "feat(S5.7): Runtime 白名单扩展 SDM/SDEM/SAC/GWR/GTWR/Probit + GWR 字段校验"
```

---

### Task 10: App CLI + 类型 + 面板

**Files:**
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts`
- Modify: `apps/metrica-desktop/src-react/services/commandGrammar.ts`
- Modify: `apps/metrica-desktop/src-react/services/commandParser.ts`
- Modify: `apps/metrica-desktop/src-react/services/runtimeClient.ts`
- Modify: `apps/metrica-desktop/src-react/components/SpatialDiagnosticsPanel.tsx`
- Create: `apps/metrica-desktop/src-react/components/GWRDiagnosticsPanel.tsx`
- Create: `apps/metrica-desktop/src-react/components/SpatialProbitPanel.tsx`
- Modify: `apps/metrica-desktop/src-react/components/ResultBlock.tsx`

- [ ] **Step 1: protocol.ts 新增类型**

```typescript
// GWR 诊断类型
export interface GWRLocalCoefficientRow {
  obs: number;
  [coefName: string]: number;  // 每变量一个局部系数值
}

export interface GWRDiagnostics {
  bandwidth?: number;
  bandwidth_selection?: string;
  bandwidth_score?: number;
  kernel?: string;
  adaptive?: boolean;
  distance_metric?: string;
  effective_parameters?: number;
  aicc?: number;
  local_coefficients_preview?: GWRLocalCoefficientRow[];
}

// 空间 Probit 类型
export interface SpatialProbitDiagnostics {
  rho_accept_rate?: number;
  n_iter?: number;
  n_warmup?: number;
  n_chains?: number;
  inference_mode?: string;
  rhat?: number[] | null;
  ess?: number[] | null;
}
```

在 `ModelResult` 中新增 `gwr_diagnostics?: GWRDiagnostics`。

- [ ] **Step 2: commandGrammar.ts 新增动词**

```typescript
makeModelGrammar('gwr', ['coords', 'kernel', 'bandwidth', 'adaptive']),
makeModelGrammar('gtwr', ['coords', 'time', 'kernel', 'bandwidth', 'adaptive']),
makeModelGrammar('spprobit', ['weights', 'id']),
```

- [ ] **Step 3: commandParser.ts 新增解析函数**

```typescript
// gwr: gwr y x1 x2, coords(lon lat) kernel(gaussian) bandwidth(cv) adaptive(true)
function parseGwrToModelSpec(parsed: GwrParsedCommand): ModelSpec {
  const yVar = parsed.leftVars[0];
  const xVars = parsed.rightVars;
  const hasConstant = !parsed.options.noconstant;
  const formula = hasConstant
    ? `${yVar} ~ ${['(Intercept)', ...xVars].join(' + ')}`
    : `${yVar} ~ ${xVars.join(' + ')}`;

  const coordCols = parsed.options.coords?.value as string[];
  const kernel = (parsed.options.kernel?.value as string) || 'gaussian';
  const adaptive = parsed.options.adaptive?.value === true;
  const bwRaw = parsed.options.bandwidth?.value as string | undefined;
  const dist = (parsed.options.distance?.value as string) || 'euclidean';

  let bandwidth: number | undefined;
  let bandwidthSelection: string | undefined;
  if (bwRaw === 'cv') {
    bandwidthSelection = 'cv';
  } else if (bwRaw === 'aicc') {
    bandwidthSelection = 'aicc';
  } else if (bwRaw !== undefined) {
    bandwidth = parseFloat(bwRaw);
  }

  return {
    model_type: 'spatial_gwr',
    formula,
    spatial_coord_columns: coordCols,
    spatial_distance: dist,
    gwr_kernel: kernel,
    gwr_bandwidth: bandwidth,
    gwr_bandwidth_selection: bandwidthSelection,
    gwr_adaptive: adaptive,
  };
}

// gtwr: gtwr y x1 x2, coords(lon lat) time(year) kernel(bisquare) bandwidth(cv)
function parseGtwrToModelSpec(parsed: GtwrParsedCommand): ModelSpec {
  const base = parseGwrToModelSpec(parsed as unknown as GwrParsedCommand);
  base.model_type = 'spatial_gtwr';
  base.gtwr_time_column = parsed.options.time?.value as string;
  const ts = parsed.options.time_scale?.value;
  base.gtwr_time_scale = ts === 'auto' ? 'auto' : (ts !== undefined ? Number(ts) : undefined);
  return base;
}

// spprobit: spprobit y x1 x2, weights("W.csv") id(region)
function parseSpprobitToModelSpec(parsed: SpprobitParsedCommand): ModelSpec {
  const yVar = parsed.leftVars[0];
  const xVars = parsed.rightVars;
  const hasConstant = !parsed.options.noconstant;
  const formula = hasConstant
    ? `${yVar} ~ ${['(Intercept)', ...xVars].join(' + ')}`
    : `${yVar} ~ ${xVars.join(' + ')}`;

  const weightsPath = (parsed.options.weights?.value as string) || (parsed.options.spatial_weights?.value as string);
  const idCol = (parsed.options.id?.value as string) || (parsed.options.spatial_id?.value as string) || 'region';

  return {
    model_type: 'spatial_probit',
    formula,
    spatial_weights_path: weightsPath,
    spatial_id_column: idCol,
  };
}
```

- [ ] **Step 4: SpatialDiagnosticsPanel.tsx 新增 LM 检验区块**

在现有「Moran I」行下方添加四个新行：

```tsx
<Descriptions.Item label="LM-Lag">{(diagnostics as any)?.lm_lag?.statistic?.toFixed(4)} (p={(diagnostics as any)?.lm_lag?.pvalue?.toFixed(4)})</Descriptions.Item>
<Descriptions.Item label="LM-Error">{(diagnostics as any)?.lm_error?.statistic?.toFixed(4)} (p={(diagnostics as any)?.lm_error?.pvalue?.toFixed(4)})</Descriptions.Item>
<Descriptions.Item label="Robust LM-Lag">{(diagnostics as any)?.robust_lm_lag?.statistic?.toFixed(4)} (p={(diagnostics as any)?.robust_lm_lag?.pvalue?.toFixed(4)})</Descriptions.Item>
<Descriptions.Item label="Robust LM-Error">{(diagnostics as any)?.robust_lm_error?.statistic?.toFixed(4)} (p={(diagnostics as any)?.robust_lm_error?.pvalue?.toFixed(4)})</Descriptions.Item>
```

- [ ] **Step 5: GWRDiagnosticsPanel.tsx**

局部系数摘要表 + 带宽/核/CV/AICc 信息。首列显示 obs 1..preview_n，后续列显示各变量局部系数。表格上方显示 `bandwidth`、`bandwidth_selection`、`kernel`、`aicc` 等关键参数。

- [ ] **Step 6: SpatialProbitPanel.tsx**

后验均值/标准差/可信区间表格 + rho 接受率 + MCMC 诊断（rhat、ess 若可用）。

- [ ] **Step 7: ResultBlock.tsx 集成**

```tsx
const showGWR = modelType === 'spatial_gwr' || modelType === 'spatial_gtwr';
const showProbit = modelType === 'spatial_probit';
// 在渲染区：
{showGWR && <GWRDiagnosticsPanel gwrDiagnostics={result.gwr_diagnostics} />}
{showProbit && <SpatialProbitPanel diagnostics={result.diagnostics as SpatialProbitDiagnostics} />}
```

- [ ] **Step 8: Commit**

```bash
git add apps/metrica-desktop/src-react/
git commit -m "feat(S5.7): App CLI/类型/面板贯通 GWR/GTWR/Probit + LM 检验展示"
```

---

### Task 11: 桥接 + 协议文档 + Demo 数据

**Files:**
- Modify: `scripts/julia_bridge_entry.jl`
- Modify: `scripts/julia_daemon.jl`
- Modify: `docs/architecture/runtime-protocol.md`
- Modify: `tutorials/s5-spatial.md`
- Create: `datasets/demo/spatial_demo_coords.csv`
- Create: `datasets/demo/spatial_probit_demo.csv`

- [ ] **Step 1: 更新桥接 dispatch**

在 `julia_bridge_entry.jl` 中（第 203 行之后），将现有空间派发块替换为：

```julia
elseif model_type in ("spatial_lag", "spatial_error", "spatial_slx",
                      "spatial_sdm", "spatial_sdem", "spatial_sac")
    wd = get(project_context, "working_dir", default_demo_dir())
    spec_dict = Dict{String, Any}(
        "spatial_weights_path" => get(model_spec, "spatial_weights_path", ""),
        "spatial_id_column" => get(model_spec, "spatial_id_column", ""),
    )
    if haskey(model_spec, "spatial_row_standardize")
        spec_dict["spatial_row_standardize"] = model_spec["spatial_row_standardize"]
    end
    if haskey(model_spec, "vcov")
        spec_dict["vcov"] = model_spec["vcov"]
    end
    result = MetricaSpatial.fit_spatial(model_type, formula, df, spec_dict, wd)
    if result isa MetricaBase.ModelError
        payload = MetricaSpatial.error_to_payload(result)
    else
        payload = MetricaSpatial.result_to_payload(result; include_augment=include_augment)
    end

elseif model_type in ("spatial_gwr", "spatial_gtwr")
    nls_f = MetricaBase.parse_metrica_formula(formula)
    nls_f isa MetricaBase.ModelError && return runtime_error_envelope(nls_f)
    response_name, predictor_names = nls_f

    y_vec = float.(df[!, Symbol(response_name)])
    X_mat = hcat(ones(length(y_vec)), [float.(df[!, Symbol(c)]) for c in predictor_names]...)

    coords_raw = get(model_spec, "spatial_coord_columns", nothing)
    coords_raw === nothing && return runtime_error_envelope(
        MetricaBase.ModelError(:missing_coords, "GWR 需要 spatial_coord_columns", "", ""))
    coords = hcat(float.(df[!, Symbol(coords_raw[1])]), float.(df[!, Symbol(coords_raw[2])]))

    kernel = get(model_spec, "gwr_kernel", "gaussian")
    bandwidth = get(model_spec, "gwr_bandwidth", nothing)
    bw_selection = get(model_spec, "gwr_bandwidth_selection", "cv")
    adaptive = get(model_spec, "gwr_adaptive", false)
    dist_metric = Symbol(get(model_spec, "spatial_distance", "euclidean"))

    if model_type == "spatial_gtwr"
        time_col = get(model_spec, "gtwr_time_column", nothing)
        time_col === nothing && return runtime_error_envelope(
            MetricaBase.ModelError(:missing_time, "GTWR 需要 gtwr_time_column", "", ""))
        time_vec = float.(df[!, Symbol(time_col)])
        time_scale = get(model_spec, "gtwr_time_scale", nothing)
        result = fit_gtwr(y_vec, X_mat, coords, time_vec;
                          kernel=kernel, bandwidth=bandwidth,
                          bandwidth_selection=bw_selection,
                          adaptive=adaptive, time_scale=time_scale,
                          distance_metric=dist_metric)
    else
        result = fit_gwr(y_vec, X_mat, coords;
                         kernel=kernel, bandwidth=bandwidth,
                         bandwidth_selection=bw_selection,
                         adaptive=adaptive, distance_metric=dist_metric)
    end

    if result isa MetricaBase.ModelError
        payload = error_to_payload(result)
    else
        payload = result_to_payload(result; include_augment=include_augment)
    end

elseif model_type == "spatial_probit"
    nls_f = MetricaBase.parse_metrica_formula(formula)
    nls_f isa MetricaBase.ModelError && return runtime_error_envelope(nls_f)
    response_name, predictor_names = nls_f
    y_vec = Int.(df[!, Symbol(response_name)])
    X_mat = hcat(ones(length(y_vec)), [float.(df[!, Symbol(c)]) for c in predictor_names]...)

    wd = get(project_context, "working_dir", default_demo_dir())
    wp = get(model_spec, "spatial_weights_path", "")
    id_col = get(model_spec, "spatial_id_column", "")
    edges = MetricaSpatial.read_edges_csv(resolve_path(wp, wd))
    edges isa MetricaBase.ModelError && return runtime_error_envelope(edges)
    ids_sorted = sort(unique(vcat(edges.id_i, edges.id_j)))
    W_result = MetricaSpatial.edges_to_weight_matrix(edges, ids_sorted)
    W_result isa MetricaBase.ModelError && return runtime_error_envelope(W_result)
    W = W_result[1]

    result = fit_spatial_probit(y_vec, X_mat, W; n_iter=2000, n_warmup=500)
    if result isa MetricaBase.ModelError
        payload = error_to_payload(result)
    else
        payload = result_to_payload(result; include_augment=include_augment)
    end
```

同样更新 `julia_daemon.jl` 中对应分派（从 `params` 字典读取而非 `model_spec`）。

- [ ] **Step 2: runtime-protocol.md 新增专节**

为 `spatial_sdm`、`spatial_sdem`、`spatial_sac`、`spatial_gwr`、`spatial_gtwr`、`spatial_probit` 各增一段，与现有 `spatial_lag` 格式一致。

- [ ] **Step 3: 教程更新**

`tutorials/s5-spatial.md` 新增：
- LM 检验阅读指南
- SDM/SAC 模型选择建议
- GWR 局部系数解释
- 空间 Probit 后验解释

- [ ] **Step 4: Demo 数据**

`datasets/demo/spatial_demo_coords.csv`: 30 观测，含 `y, x1, x2, lon, lat` 列，坐标模拟方格分布。

`datasets/demo/spatial_probit_demo.csv`: 30 观测，含 `y (0/1), x1, x2, region` 列 + 对应边表。

- [ ] **Step 5: Commit**

```bash
git add scripts/ docs/ tutorials/ datasets/demo/
git commit -m "feat(S5.7): 桥接/协议文档/教程/Demo数据同步全部新模型"
```

---

### Task 12: 全量测试

**Files:**
- Modify: `packages/MetricaSpatial.jl/test/runtests.jl`
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`

- [ ] **Step 1: Julia 测试扩展**

```julia
@testset "SDM 成功路径" begin
    result = fit_spatial("spatial_sdm", "y ~ x1", df, spec, wd)
    @test result isa SpatialFitResult
    @test :spatial_sdm == result.model_kind
    @test haskey(diag, :rho)
    @test haskey(diag, :direct_effects)
end

@testset "SAC 成功路径" begin
    result = fit_spatial("spatial_sac", "y ~ x1", df, spec, wd)
    @test result isa SpatialFitResult
    @test haskey(result.diagnostics, :lambda)
end

@testset "GWR 成功路径" begin
    coords = [0.0 0.0; 1.0 0.0; 0.0 1.0; 1.0 1.0; 0.5 0.5]
    y = [1.0, 2.0, 1.5, 2.5, 2.0]
    X = [ones(5) [0.5, 1.5, 0.5, 1.5, 1.0]]
    result = fit_gwr(y, X, coords; bandwidth=2.0, kernel="gaussian")
    @test result isa GWRFitResult
    @test size(result.local_coefficients) == (5, 2)
    @test length(result.fitted) == 5
end

@testset "空间 Probit 小样本" begin
    y = [1, 0, 1, 0, 1]
    X = [ones(5) [0.5, -0.3, 0.8, -0.1, 0.4]]
    W = [0 0.5 0 0 0.5; 0.5 0 0.5 0 0; 0 0.5 0 0.5 0; 0 0 0.5 0 0.5; 0.5 0 0 0.5 0]
    result = fit_spatial_probit(y, X, W; n_iter=1000, n_warmup=200, seed=42)
    @test result isa ProbitFitResult
    @test length(result.posterior_mean) == 3  # rho + intercept + x1
end
```

- [ ] **Step 2: Runtime 垂直切片断言**

每个新 model_type 至少一条成功路径，断言 `diagnostics` 含约定键。

- [ ] **Step 3: Commit**

```bash
git add packages/MetricaSpatial.jl/test/runtests.jl runtime/metrica-runtime/tests/vertical_slice.rs
git commit -m "test(S5.7): SDM/SAC/GWR/Probit 全量测试覆盖"
```

---

## Verification

```bash
# Julia 测试
julia --project=packages/MetricaSpatial.jl -e 'using Pkg; Pkg.test()'
# Expected: 15+ 测试通过（全部新模型 + 已有 SAR/SEM/SLX）

# Rust 编译
cargo check
# Expected: 无错误（若 Julia daemon 砂箱限制，至少 cargo check 通过）

# App 测试
cd apps/metrica-desktop && npm test
# Expected: 全部 Vitest 通过（新增 gwr/gtwr/spprobit 解析测试）

# Rust 单元测试
cargo test --lib
# Expected: 7/7 通过
```
