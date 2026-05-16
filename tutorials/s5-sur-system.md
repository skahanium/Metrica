# S5.3：SUR 与多方程 2SLS / 3SLS（CLI 与协议）

本教程假设 **Metrica Runtime** 已启动，且桌面应用或 HTTP 客户端指向默认端口；数据集为仓库内示例 CSV。

## 与单方程 OLS / IV 的区别

- **SUR（`sur`）**：多个因变量方程在同一组观测上估计，允许方程间相关误差；在 `MetricaSystem.jl` 中使用 **FGLS** 思路迭代（见返回中的 `diagnostics.iterations` 与 `system_method`）。
- **多方程 2SLS / 3SLS（`system_2sls` / `system_3sls`）**：每方程有各自的 **内生变量** 与 **外生工具** 列表；首期 **2SLS** 为按方程独立两阶段最小二乘 + 共享 listwise 样本；**3SLS** 在 2SLS 残差上估计 Σ 后做一次 GLS 式系统步骤（实现细节以包内注释为准）。
- **结构化结果**：除合并 `tidy` 外，务必消费 **`equation_glances`** 与 **`diagnostics.sigma_residual`**，勿依赖拼接文本。

## CLI 示例

### SUR

```text
use datasets/demo/sur_system_demo.csv
sur (y1 x1 x2) (y2 x1 x2)
```

可选：`maxiter(10) tol(1e-5)`（映射到 `model_spec.sur_max_iter` / `sur_tol`）。

### 多方程 2SLS（`reg3`）

单方程小示例（`datasets/demo/system_2sls_demo.csv`）：

```text
use datasets/demo/system_2sls_demo.csv
reg3 (y1 x1 x2), endogenous(x1) instruments(z1)
```

### 3SLS

```text
reg3 (y1 x1 x2), endogenous(x1) instruments(z1) method(3sls)
```

### 多方程时的 `|` 分隔

`endogenous(x1|x2)` 与 `instruments(z1 z2|z3)` 中，**`|` 分隔的每一段对应一个方程块**（与 `equations` 数组下标一致）。

## `fit_model` 请求要点（JSON）

- `model_type`：`sur` | `system_2sls` | `system_3sls`
- `equations`：字符串数组，如 `["y1 ~ x1 + x2", "y2 ~ x1 + x2"]`
- `system_2sls` / `system_3sls` 另需 `system_endogenous`、`system_instruments` 二维数组，外层长度等于方程数。
- Runtime 拒绝 **多于 8 条** 方程。

完整字段表见 [`docs/architecture/runtime-protocol.md`](../docs/architecture/runtime-protocol.md) 中 **「`sur` / `system_2sls` / `system_3sls`」** 专节。

## 验收自检

- `Pkg.test(MetricaSystem)` 通过。
- `cargo test fit_model_runs_sur_with_equation_glances_and_sigma`（Runtime `vertical_slice`）通过。
- App 消息流中结果含 **`equation_glances`** 与 **`diagnostics.sigma_residual`**，且系数表带 **`equation`** 列。
