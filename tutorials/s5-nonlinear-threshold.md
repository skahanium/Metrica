# S5.5 非线性最小二乘与单门限回归（CLI + Runtime 复现）

本教程假设 **Metrica Runtime** 已启动（默认 `http://127.0.0.1:47821`），且 Julia 守护进程健康；数据集路径相对于项目 `working_dir` 可解析。

## 1. 演示数据

使用仓库内演示 CSV（含 `y`、`x`、`q` 三列）：

`datasets/demo/nls_threshold_demo.csv`

## 2. 受控 NLS（`exp_growth`）

**均值形状（首期白名单）：** \(\mu = \beta_1 + \beta_2 \exp(\beta_3 z)\)，其中 \(z\) 为公式右侧**除截距外第一个**数值解释变量（`y ~ x` 时即 `x`）。

**CLI 示例：**

```text
nls y x, start(0.5 0.5 0.05)
```

可选：`family(exp_growth)`（默认即为 `exp_growth`）；`maxiter(...)`、`tol(...)` 传给 Optim。

**教学要点：**

- 非线性最小二乘对**初值敏感**；未收敛时请在结果诊断中查看 `failure_code` 与 `warnings`，并尝试调整 `start(...)`。
- 首期 **不输出渐近标准误**（`tidy` 中 `stderror` 为 `null`），避免与 OLS 的 `vcov` 语义混淆；推断扩展须另开专节。

## 3. 单门限双区制线性回归（`threshold`）

**模型：** 在候选门限 \(\gamma\) 上搜索，使分段 OLS 残差平方和最小；各区制使用**同一** `formula` 的线性设计矩阵。

**CLI 示例（动词 `threg`）：**

```text
threg y x q, qvar(q) grid(-1 1 21) trim(0.1)
```

- `qvar(...)` 映射 `threshold_variable`，且该列**必须**出现在公式右侧（以便 listwise 对齐）。
- `grid(min max n)` 由解析器展开为 **严格递增** 的等距数组；点数 **\(n \le 500\)**（Runtime 硬上限）。
- `trim` 可选，须在 \([0, 0.45)\)；省略时 Julia 端默认 **0.1**（在切换变量 \(q\) 上按分位修剪后再与网格求交）。

**教学要点：**

- 网格过粗可能导致门限识别不稳定；请关注 `diagnostics.search_grid_meta` 与 `warnings` 中的提示。
- 若各区制有效样本过少（实现中 **\<10**），拟合将失败并返回结构化 `ModelError`。

## 4. 与协议、实施计划的对齐

- 协议字段与错误码：`docs/architecture/runtime-protocol.md`（`nls` / `threshold` 专节及 **5c 非参数预留**）。
- Task 与验收：`docs/superpowers/plans/2026-05-16-s5-execution-plan.md` 中 **「S5.5」** 专节。
