# S4 教学：复杂调查数据（CLI 主路径）

> 约定：在**本仓库根目录**启动应用，或保证 `working_dir` 指向仓库根。

## 数据

- 路径：`datasets/teaching/s4_survey_demo.csv`
- 主要列：`y`（连续）、`y_bin`、`y_count`、`x1`、`x2`、`wt`（权重）、`strata`、`psu`

## 最小命令序列

```text
use "datasets/teaching/s4_survey_demo.csv"
describe y y_bin y_count x1 x2 wt strata psu
svy ols y x1 x2, weights(wt) strata(strata) psu(psu)
svy logit y_bin x1 x2, weights(wt) strata(strata) psu(psu)
svy poisson y_count x1 x2, weights(wt) strata(strata) psu(psu)
```

## 预期结构化输出

- `glance.model` 应为 `survey_ols`、`survey_logit`、`survey_poisson` 等与 Runtime 对齐的 wire 名。
- `tidy` 系数表与调查方差相关设置应来自结构化结果，而非解析终端文本。

## 常见 warning 解读

- 权重列缺失或非正：拟合可能失败；应出现 `ModelError` 或明确错误消息（见 `docs/architecture/s4-warning-coverage.md` Survey 一节）。

## 导出

```text
runs
export markdown <run_id>, using("exports/svy_ols.md")
```
