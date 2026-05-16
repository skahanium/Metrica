# S5.4 分位数回归（单分位点 τ）

本教程说明如何在 **Runtime 已启动**、桌面应用 CLI 已连接同一工作区的前提下，用结构化 `fit_model` 流程估计**线性分位数回归**（首期仅支持**单一**分位点 \(\tau\)）。

## 与 OLS 的差别（教学要点）

- **OLS** 估计条件均值 \(\mathbb{E}[y \mid X]\)：斜率解释「\(X\) 增加一单位时 \(y\) 的**平均**变化」。
- **分位数回归** 估计条件分位数 \(Q_\tau(y \mid X)\)：斜率解释「在残差分布的 \(\tau\) 分位点上，\(X\) 对 \(y\) 的**局部位置**的边际位移」，对尾部与异质性更敏感。

首期实现使用 `QuantileRegressions.jl` 的内点求解器；标准误为包内 **渐近核（Hall–Sheather）** 口径，见返回载荷 `diagnostics.inference_kind`。**不要**与 OLS 的 `vcov`（HC1 / cluster 等）混为一谈——桥接层对 `quantile` **不转发** `vcov` / `weights` / `cluster`。

## 准备数据

仓库示例：`datasets/demo/quantile_demo.csv`（列 `y`, `x1`, `x2`）。将项目工作目录设为包含该文件的父目录（或把 CSV 拷入当前工作区）。

## CLI 示例

中位数（\(\tau=0.5\)）：

```text
qreg y x1 x2, quantile(0.5)
```

省略 `quantile(...)` 时，前端与 Runtime 默认 \(\tau = 0.5\)。

非法 \(\tau\)（如 `quantile(1)`）应在解析或 Runtime 校验阶段得到**可读错误**，不得静默失败。

## 成功时你应看到的结构化块

- `glance.model` 为 `quantile`，`glance.metrics` 含 **`tau`**、**`pseudo_r2`**。
- `tidy` 各行含 `name` / `estimate` / `stderror`（若核带宽数值不稳定则可能为 `null`，并伴随 `warnings` 说明）。
- `diagnostics` 含 `inference_kind`、`rank_X`、`cond_X`、`solver` 等，便于核对数值环境与算法路径。

## 进一步阅读

- 协议专节：`docs/architecture/runtime-protocol.md` 中 **`quantile`**。
- 实施任务与验收：`docs/superpowers/plans/2026-05-16-s5-execution-plan.md` 中 **S5.4** 专节。
