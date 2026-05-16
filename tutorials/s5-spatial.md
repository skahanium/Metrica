# S5.7 空间计量（SAR / SEM）CLI 与协议速览

本教程对应 **`MetricaSpatial.jl`**、`model_type` 为 **`spatial_lag`**（空间滞后 / SAR）或 **`spatial_error`**（空间误差 / SEM）。完整字段表见 [`docs/architecture/runtime-protocol.md`](../docs/architecture/runtime-protocol.md) 中 **`spatial_lag` / `spatial_error`** 专节。

## 1. 权重不是普通回归权重

- **边表 CSV** 三列固定：**`id_i`、`id_j`、`w`**（有向边允许；重复边由 Core 聚合规则处理，见执行计划 J0）。
- 主数据须提供与边表对齐的 **截面 ID 列**（`spatial_id_column`），**禁止**仅靠行序隐式对齐权重矩阵。
- 首期权重在 Julia 侧为 **稠密** \(W\)，样本量须满足 **`n ≤ 5000`**；大样本请拆区或二期稀疏化路径。

## 2. 演示数据

- 截面数据：`datasets/demo/spatial_demo.csv`
- 边表：`datasets/demo/spatial_demo_W.csv`

将项目 **`working_dir`** 设为仓库根（或包含上述相对路径的目录），以便 Runtime 解析 **`spatial_weights_path`**。

## 3. App CLI 示例（`spreg`）

**SAR（`spatial_lag`）：**

```text
spreg y x1, spatial_weights("datasets/demo/spatial_demo_W.csv") id(region) model(lag)
```

**SEM（`spatial_error`）：**

```text
spreg y x1, weights("datasets/demo/spatial_demo_W.csv") id(region) model(error)
```

说明：

- **`weights("...")`** 与 **`spatial_weights("...")`** 等价，均映射到协议字段 **`spatial_weights_path`**（与调查设计的抽样权重 **不是**同一概念）。
- **`model(lag)`** → `spatial_lag`；**`model(error)`** → `spatial_error`。
- **`id(列名)`** 或 **`spatial_id(列名)`** → **`spatial_id_column`**。
- 可选 **`rowstd(false)`** → **`spatial_row_standardize: false`**（省略时默认行标准化）。
- 可选 **`robust`** → SAR 的 **`vcov: HC1`**（与 OLS 族 CLI 习惯一致）。

## 4. 结构化结果中看什么

拟合成功后，在 **`result_payload.diagnostics`** 中至少应看到：

- **`row_standardized_report`**：是否应用行标准化及行和范围（禁止仅靠一句自然语言）。
- **`moran_i`** 等：残差全局 Moran（首期 **`moran_var` / `moran_z`** 可为 `null`）。
- **`spatial_weights_basename`**：仅文件名，避免在 JSON 中泄露敏感绝对路径。
- **`rho`**（SAR）或 **`lambda`**（SEM）。
- **`direct_effects` / `indirect_effects` / `total_effects`**：首期可为 **`null`**，表示二期再填充分解，避免半套数字误导。

## 5. 常见错误路径（须为结构化 `messages`）

- ID 在主数据中重复、与边表无法对齐、缺失权重文件、\(n\) 或边表规模超限等，应返回带 **`code`** 的结构化错误；请勿依赖仅文本摘要驱动下游逻辑。
