# 空间计量模型族全量成熟化 — 设计文档

> 对照 `S5-模型族全量成熟化施工方案.md` §2，将 `MetricaSpatial.jl` 从 SAR/SEM/SLX 基础实现扩展为完整空间横截面模型族。

## 1. Context

当前 `MetricaSpatial.jl` (v0.1.0) 提供：
- 3 个模型：SAR (2SLS)、SEM (Gaussian profile ML)、SLX (OLS)
- 1 个诊断：Moran I（残差空间自相关）
- 1 种权重输入：稠密边表 CSV（`id_i, id_j, w`）
- 效应分解：SAR/SLX 有 direct/indirect/total effects；SEM 无

施工方案 §2 要求扩展为包含 SDM、SDEM、SAC/SARAR、空间 Probit、GWR、GTWR、LM 检验、kNN/distance-band 权重构造的完整模型族。整体当前成熟度约 25%，目标达到 90%+。

## 2. Architecture

```
packages/MetricaSpatial.jl/src/
├── MetricaSpatial.jl        ← 模块主文件（扩展 export + include）
├── types.jl                 ← 扩展 SpatialFitResult、新增 GWR/Probit 结果类型
├── weights_io.jl            ← [修改] 新增 kNN/distance-band 构造
├── weights_knn.jl           ← [新建] kNN 权重构造
├── weights_distance.jl      ← [新建] distance-band 权重构造
├── moran.jl                 ← 不变
├── lm_tests.jl              ← [新建] LM-Lag/Error/Robust 检验
├── sar_fit.jl               ← 不变
├── sem_fit.jl               ← 不变
├── slx_fit.jl               ← 不变
├── sdm_fit.jl               ← [新建] 空间杜宾模型
├── sdem_fit.jl              ← [新建] 空间杜宾误差模型
├── sac_fit.jl               ← [新建] SAC/SARAR
├── gwr_fit.jl               ← [新建] 地理加权回归
├── gtwr_fit.jl              ← [新建] 地理时空加权回归
├── spatial_probit.jl        ← [新建] 空间 Probit (Bayesian MCMC)
├── effects.jl               ← [修改] 新增 SDM/SAC 效应分解
├── interfaces.jl            ← [修改] 扩展 glance/tidy/capabilities
├── fit_spatial.jl           ← [修改] 新增模型派发
└── serialize.jl             ← [修改] 扩展 result_to_payload
```

Cross-layer data flow:
```
App CLI → commandParser → runtimeClient → Runtime (axum HTTP)
  → julia_bridge_entry.jl / julia_daemon.jl
  → MetricaSpatial.fit_spatial(model_type, formula, df, spec, working_dir)
  → SpatialFitResult / GWRFitResult / ProbitFitResult
  → result_to_payload → JSON → Runtime → App ResultBlock
```

### 2.1 独立权重体系：W-based vs Coordinate-based

| 模型族 | 权重输入 | 来源 |
|--------|---------|------|
| SAR / SEM / SLX / SDM / SDEM / SAC / Probit | `spatial_weights_path` (边表 CSV) | 现有 |
| GWR / GTWR | `spatial_coord_columns` (坐标列) + 核函数 | 新建 |

两者完全独立：GWR/GTWR 不使用 `spatial_weights_path`，SAR/SDM 不使用坐标。Runtime 校验据此分派。

## 3. Phase A — 诊断与权重基础设施

### A1. LM 检验 (`lm_tests.jl`)

四函数均接受 OLS 残差向量 `e`、设计矩阵 `X`（含截距）、权重矩阵 `W`：

```julia
function lm_lag_test(e::Vector{Float64}, X::Matrix{Float64}, W::Matrix{Float64})
    # LM-Lag = (n / J_rho_beta) * (e'We / e'e)^2, J = something like tr(W^2 + W'W)...
    # 返回 Dict(:statistic => LM, :pvalue => pchisq(LM, 1, lower.tail=FALSE), :dof => 1)
end
```

完全参考 Anselin (1988) / R `spdep::lm.LMtests` 的经典公式。四个键名：`:lm_lag`、`:lm_error`、`:robust_lm_lag`、`:robust_lm_error`。每个都是一个 `Dict{Symbol, Any}` 含 `:statistic`、`:pvalue`、`:dof`。

插桩位置：`fit_spatial.jl` 第 13 步之后（设计矩阵和权重矩阵就绪后）即计算 OLS 残差 → 跑全部四个 LM → 存入 `diagnostics` dict。

### A2. 权重构造 (`weights_knn.jl`, `weights_distance.jl`)

**kNN 权重：**
```julia
function build_knn_weights(coords::Matrix{Float64}, k::Int; distance_metric=:euclidean, row_standardize=true)
    # 返回 (edges::DataFrame, meta::Dict)
    # edges: id_i (1:n), id_j (knn neighbor), w (=1 after row-standardize if enabled)
    # meta: :method => "knn", :k => k, :distance_metric, :coord_columns, :crs (if provided)
end
```

**Distance-band 权重：**
```julia
function build_distance_band_weights(coords::Matrix{Float64}, threshold::Float64; distance_metric=:euclidean, row_standardize=true)
    # 返回 (edges::DataFrame, meta::Dict)
    # 检查无孤立单元
end
```

**距离函数：** `euclidean_distance(x1,y1,x2,y2)`、`haversine_distance(lon1,lat1,lon2,lat2)`。

Runtime 新增可选字段：`spatial_weight_method`（`"edge_csv"` 默认、`"knn"`、`"distance_band"`）、`spatial_weight_k`、`spatial_weight_threshold`、`spatial_coord_columns`（供权重构造和 GWR 共用）、`spatial_distance`（`euclidean`/`haversine`/`projected`）、`spatial_crs`。

### A3. 效应分解扩展 (`effects.jl`)

新增函数 `sdm_effects(rho, theta_dict, W, x_colnames)`，公式为 `S = (I-ρW)^(-1)`，对每个变量 k：`direct = mean(diag(S)) * β_k + mean(diag(S * W)) * θ_k`（其中 θ_k 是 Wx_k 的系数），以此类推 indirect 和 total。

`SAC` 的效应分解首期可用近似法（或标记为 `nothing` + `:effects_unavailable`）。

## 4. Phase B — 核心模型扩展

### B1. SDM (`sdm_fit.jl`)

方程：`y = ρWy + Xβ + WX̃θ + ε`。X̃ = X[:, 2:end]（不含截距列，因为 W·1 = 1）。

估计器复用 SAR 2SLS 框架，增广内生变量为 `[Wy, X]`，工具为 `[X, WX, W²X]`（剔除共线列）。系数顺序：`[rho, β_intercept, β_x1, ..., θ_x1, θ_x2, ...]`。

model_type: `"spatial_sdm"`。

### B2. SDEM (`sdem_fit.jl`)

方程：`y = Xβ + WX̃θ + u, u = λWu + ε`。

估计器：剖面 ML（在 λ 上优化），集中 β、θ、σ²。自变量为 `[X, WX̃]`。与 SEM 共用 `logabsdet(I-λW)` 路径。

model_type: `"spatial_sdem"`。

### B3. SAC/SARAR (`sac_fit.jl`)

方程：`y = ρWy + Xβ + u, u = λWu + ε`（首期限制 W₁ = W₂ = W）。

估计器：**GS2SLS (Generalized Spatial Two-Stage Least Squares)**：
1. 第一步 2SLS → 得 β̂、ρ̂ 和残差 û
2. 第二步从 û 用 GMM 矩条件估计 λ̂（Û'WÛ、Û'W²Û 等）
3. 第三步 FGLS 变换 `y* = y - λ̂Wy`、`X* = X - λ̂WX` → 得最终 β̂ 和 ρ̂

model_type: `"spatial_sac"`。

## 5. Phase C — GWR / GTWR

### C1. GWR (`gwr_fit.jl`)

每个观测点 i 执行局部 WLS：

```
β̂_i = (X' W(i) X)^(-1) X' W(i) y
W(i) = diag(K(d_i1/h), ..., K(d_in/h))  (adaptive 时 h = d_i(k))
```

核函数：
- Gaussian: `K(d) = exp(-(d/h)² / 2)`
- Bisquare: `K(d) = (1 - (d/h)²)²` for `d < h`, else 0

带宽选择：CV 评分 `Σ(y_i - ŷ_{-i})²` 和 AICc 评分通过 Golden-section 搜索优化 `h`。

**新结果类型：** `GWRFitResult`（字段见施工方案 §2.1）。与 `SpatialFitResult` 分离。

### C2. GTWR (`gtwr_fit.jl`)

时空距离：`d_ij^ST = sqrt(d_ij_space² + τ * d_ij_time²)`。τ 为时间尺度参数，`auto` 时在 CV 中搜索。

与 GWR 的差异：仅距离计算公式不同 + 需要时间尺度优化。其余相同。

**新结果类型：** `GTWRFitResult`（在 GWR 基础上扩展 `time_scale`、`spatiotemporal_distance_summary`）。

### C3. Protocol 独立设计

GWR/GTWR 的 ModelSpec **不使用** `spatial_weights_path`。新增 GWR 专用字段：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `spatial_coord_columns` | `string[2]` | 是 | `["lon", "lat"]` 或 `["x", "y"]` |
| `spatial_distance` | 字符串 | 否（默认 euclidean） | `euclidean` / `haversine` / `projected` |
| `spatial_crs` | 字符串 | 否 | CRS 说明；经纬度时 warning |
| `gwr_kernel` | 字符串 | 否（默认 gaussian） | `gaussian` / `bisquare` |
| `gwr_bandwidth` | 数 | 条件 | 与 `gwr_bandwidth_selection` 互斥 |
| `gwr_bandwidth_selection` | 字符串 | 条件 | `cv` / `aicc` |
| `gwr_adaptive` | 布尔 | 否（默认 false） | true → 相邻点数带宽 |
| `gtwr_time_column` | 字符串 | gtwr 必填 | 时间列名 |
| `gtwr_time_scale` | 数或 auto | 否 | 时空平衡参数 |

## 6. Phase D — 空间 Probit (`spatial_probit.jl`)

### D1. Bayesian Gibbs 采样

模型：`y* = ρWy* + Xβ + ε, ε ~ N(0, I_n)`，观测 `y_i = 1(y*_i > 0)`。

Gibbs 采样器（手写，不依赖 Turing.jl）：
1. **潜变量 `y*`**：从截断正态采样 — `y*_i | β, ρ, y_i ~ TN(Xβ_i + ρ(Wy*)_i, 1, lower=0)` if `y_i=1`, else upper=0
2. **β**：从多元正态后验采样 — `β | y*, ρ ~ N((X'X + τ⁻²I)^(-1)X'(y*-ρWy*), (X'X + τ⁻²I)^(-1))`
3. **ρ**：Metropolis-Hastings 步 — 提议 `ρ* ~ N(ρ, σ_proposal)`，接受比基于 `|I-ρW| * prior`

输出：`posterior_mean`、`posterior_sd`、`credible_interval`（95% HPD）、`rhat`（若 chains ≥ 2）、`ess`。

model_type: `"spatial_probit"`。要求 `n ≤ 1000`（Gibbs 采样 + 稠密 W 开销大）。

**约束：** 本文档不引入的新依赖。采样器仅依赖 `Distributions`（已在仓库中通过 `MetricaBase` 间接依赖）、`LinearAlgebra`、`Random`、`Statistics`。

## 7. Phase E — 跨层贯通

### E1. Runtime (`lib.rs`)

**新增 `model_required_fields()`：**
- `"spatial_sdm"` → `["spatial_weights_path", "spatial_id_column"]`
- `"spatial_sdem"` → `["spatial_weights_path", "spatial_id_column"]`
- `"spatial_sac"` → `["spatial_weights_path", "spatial_id_column"]`
- `"spatial_gwr"` → `["spatial_coord_columns"]`
- `"spatial_gtwr"` → `["spatial_coord_columns", "gtwr_time_column"]`
- `"spatial_probit"` → `["spatial_weights_path", "spatial_id_column"]`

**新增 `ModelSpec` 字段：** `spatial_coord_columns`（`Vec<String>`）、`spatial_distance`（`String`）、`spatial_crs`（`String`）、`gwr_kernel`（`String`）、`gwr_bandwidth`（`f64`）、`gwr_bandwidth_selection`（`String`）、`gwr_adaptive`（`bool`）、`gtwr_time_column`（`String`）、`gtwr_time_scale`（`Value` — 数或 `"auto"`）。

**新增校验：** GWR kernel 枚举 (`gaussian`/`bisquare`)、bandwidth 与 bandwidth_selection 互斥、coord_columns 长度=2。

### E2. App CLI

**`spreg` 扩展：** `model()` 新增 `sdm`、`sdem`、`sac`。

**新动词：**
- `gwr y x1 x2, coords(lon lat) kernel(gaussian) bandwidth(cv) adaptive(true)`
- `gtwr y x1 x2, coords(lon lat) time(year) kernel(bisquare) bandwidth(cv)`
- `spprobit y x1 x2, weights("W.csv") id(region)`

**新 TS 类型 (`protocol.ts`)：**
- `GWRLocalCoefficients` — 局部系数表行类型
- `GWRDiagnostics` — 带宽、核、CV/AICc 得分、hat diag
- `SpatialProbitDiagnostics` — posterior mean/sd、credible interval、rhat、ess

**新面板组件：**
- `SpatialDiagnosticsPanel.tsx` — 新增「LM 检验」区块
- `GWRDiagnosticsPanel.tsx` — 局部系数摘要表 + 带宽/核选择结果
- `SpatialProbitPanel.tsx` — 后验摘要 + MCMC 诊断

### E3. Demo Data

新增 demo 数据集：
- `datasets/demo/spatial_demo_coords.csv` — 30 观测、含 lon/lat 坐标列、y/x1/x2（供 GWR/GTWR）
- `datasets/demo/spatial_probit_demo.csv` — 30 观测、含 W、0/1 因变量（供空间 Probit）
- 扩展现有 `spatial_demo_W.csv` 的观测数和边数以支持 SDM/SAC 测试

### E3. 协议文档 (`runtime-protocol.md`)

为每个新 `model_type` 新增专节，与现有 `spatial_lag`/`spatial_error`/`spatial_slx` 格式一致。

### E4. model_capabilities 更新 (`interfaces.jl`)

各新模型类型需实现 `MetricaBase.model_capabilities()`，更新 `supported_models` 和 `diagnostics_available`：

| 模型 | supported_models | 新增 diagnostics_available |
|------|-----------------|---------------------------|
| SDM | `[:spatial_lag, :spatial_error, :spatial_slx, :spatial_sdm]` | `:lm_lag, :lm_error, :robust_lm_lag, :robust_lm_error` |
| SDEM | 同上 + `:spatial_sdem` | 同上 |
| SAC | 同上 + `:spatial_sac` | 同上 |
| GWR | `[:spatial_gwr]` | 独立 diagnostics（带宽、CV 等） |
| GTWR | `[:spatial_gwr, :spatial_gtwr]` | 同上 + 时空诊断 |
| Probit | `[:spatial_probit]` | posterior_mean, credible_interval |

注意：现有 `SpatialFitResult` 的 model_capabilities 需更新 `diagnostics_available` 以包含 LM 检验键（当阶段 A 完成后）。

### E5. 序列化扩展 (`serialize.jl`)

- `SpatialFitResult` 的 `result_to_payload` — 在此路径上扩展 LM 检验键
- `GWRFitResult` / `GTWRFitResult` — 新增独立 `result_to_payload` 方法
- `ProbitFitResult` — 新增独立 `result_to_payload` 方法

### E6. 测试

每模型至少包含：
1. 成功路径（小样本 demo 数据）
2. 失败路径（孤立单元、不当参数、超大 n）
3. diagnostics 键名存在性断言
4. model_capabilities 与实现一致

Golden value 对齐：
- SDM ↔ R `spatialreg::lagsarlm(..., Durbin=TRUE)`
- SAC ↔ R `spatialreg::sacsarlm(...)`
- GWR ↔ R `GWmodel::gwr.basic(...)`
- Probit ↔ 小样本手算 Gibbs 结果

## 8. Risk Mitigation

| 风险 | 缓解 |
|------|------|
| SAC 两步估计 GMM 矩条件推导复杂 | 参考 Kelejian & Prucha (1998) GS2SLS 标准文献，首期限制 W₁=W₂ |
| SEM/SDEM `logabsdet(I-λW)` 数值不稳 | 复用已有 SEM 的 λ 搜索 (-0.99, 0.99)，加入复数特征值 warning |
| GWR 大 n 留一 CV 计算量 O(n²) | 首期限 n ≤ 2000 for GWR，后续可引入 hat matrix 快速 CV |
| 空间 Probit Gibbs 混合慢 | 首期限 n ≤ 500 for MCMC，使用 Adaptive M-H proposal |
| 新 ModelSpec 字段过多，协议复杂 | 按模型族分派：W-based 族用 spatial_weights_path，Coord-based 族忽略它 |
