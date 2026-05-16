# S4 教学：离散选择模型（CLI 主路径）

> 约定：在**本仓库根目录**启动 Metrica 桌面应用，或将项目的 `working_dir` 指向仓库根，使下列相对路径可被 Runtime 解析。

## 数据

- 路径：`datasets/teaching/s4_discrete_demo.csv`
- 主要列：`y_bin`（0/1）、`y_count`（计数）、`x1`、`x2`、`group`

## 最小命令序列

```text
use "datasets/teaching/s4_discrete_demo.csv"
describe y_bin y_count x1 x2
summarize y_bin y_count x1 x2
logit y_bin x1 x2
poisson y_count x1 x2
```

## 预期结构化输出（结果流）

- `describe` / `summarize`：`data_result.kind` 为 `describe` / `summarize`，含 `dataset_summary` 与变量级字段。
- `logit` / `poisson`：`result` 消息中含 `glance`（如 `model`、`nobs`、`metrics`）与 `tidy`（系数行），**不要**依赖纯文本摘要驱动下游逻辑。

## 常见 warning 解读

- 收敛标记为否或迭代过多：检查完全分离、样本量过小或共线性；详见 `docs/architecture/s4-warning-coverage.md` Discrete 一节。

## 导出（CLI）

在至少一次成功的 `fit_model` 运行后：

```text
runs
export markdown, using("exports/logit_run.md")
```

若省略 `using(...)`，应用可能弹出保存路径选择器；取消则不会调用 Runtime 导出。
