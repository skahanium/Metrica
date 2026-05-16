# S5 教学：线性 IV-GMM 与过识别检验（CLI 主路径）

> 约定：在**本仓库根目录**启动应用，或保证 `working_dir` 指向仓库根；Runtime 已启动且能加载 `packages/MetricaRuntime.jl` 环境（含 `MetricaGMM`）。

## 与 2SLS（`ivregress`）的关系

- `ivregress` 对应 `model_type: "iv"`，估计量为 2SLS。
- `gmm` 对应 `model_type: "gmm_linear"`，在相同矩条件 \(E[Z'u]=0\) 下使用一步或两步最优权重 GMM；过识别时可读 Hansen / Sargan **J** 检验（见结果中 `diagnostics`）。
- 两者在 CLI 上**复用** `endogenous(...)` 与 `instruments(...)` 选项形状。

## 数据

- 演示 CSV：`datasets/demo/gmm_linear_demo.csv`
- 列：`y`、`x1`（在示例中可作内生）、`x2`、`z1`、`z2`（工具）

## 最小命令序列（两步 GMM，默认）

```text
use "datasets/demo/gmm_linear_demo.csv"
describe y x1 x2 z1 z2
gmm y x1 x2, endogenous(x1) instruments(z1 z2)
```

## 一步权重

```text
gmm y x1 x2, endogenous(x1) instruments(z1 z2) weight(one_step)
```

等价于在 API 中设置 `model_spec.gmm_weight: "one_step"`；`two_step` 可写 `weight(two_step)` 或省略（后端默认两步）。

## 预期结构化输出

- `glance.model` 应为 `gmm_linear`；`glance.metrics` 中含 `j_stat`、`j_df` 等（与 Core 一致）。
- `result_payload.diagnostics` 中含 `j_statistic`、`j_pvalue`、`n_moments`、`n_params`、`weight_matrix_description` 等键，详见 [`docs/architecture/runtime-protocol.md`](../docs/architecture/runtime-protocol.md) 中「`gmm_linear`」小节。
- 恰识别（\(L=k\)）时 **J 检验不适用**，`j_pvalue` 可能为 null；两步请求下若样本矩协方差奇异，实现可能退回与一步相同的 \((Z'Z)^{-1}\) 权重，并在 `weight_matrix_description` 中说明。

## 常见误用与 warning

- **欠识别**（工具个数少于内生加外生系数个数）：返回结构化错误，需增加工具或简化公式。
- **内生变量未出现在公式右侧**：与 IV 相同，会报 `endog_not_in_formula` 类错误。
- **弱工具**：可能附带与 IV 类似的一阶段 F 规则 warning，教学上应减少弱工具依赖或增加相关信息变量。

## 自动化对照

- Julia 包测试：`packages/MetricaGMM.jl/test/runtests.jl`（教科书式小矩阵与演示 CSV）。
- Runtime 垂直切片：`runtime/metrica-runtime/tests/vertical_slice.rs` 中 `fit_model_runs_gmm_linear_with_diagnostics`。

## 导出

```text
runs
export markdown <run_id>, using("exports/gmm_run.md")
```
