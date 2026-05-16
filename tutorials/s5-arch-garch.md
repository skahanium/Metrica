# S5.6 ARCH / GARCH 教程（CLI-first）

> **前置：** 已加载含时间索引与收益率（或水平序列）的 CSV；Runtime 已启动；工作目录能解析到仓库内 `datasets/demo/garch_demo.csv`。  
> **协议细节：** 字段与 `diagnostics` 键名见 [`docs/architecture/runtime-protocol.md`](../docs/architecture/runtime-protocol.md) 中 **`arch` / `garch` 专节**。

## 1. 模型在做什么

- **波动率聚集（volatility clustering）：** 大幅波动往往跟着大幅波动，小幅跟着小幅。ARCH / GARCH 用**随时间变化的条件方差** \(\sigma_t^2\) 描述这一现象。
- **首期均值方程：** 仅**常数均值** \(y_t=\mu+\varepsilon_t\)，\(\varepsilon_t=\sigma_t z_t\)，估计采用 **Gaussian QMLE**（与许多入门教材一致；**不等于**已完整实现半参数或稳健 M 估计）。
- **ARCH(q)：** \(\sigma_t^2=\omega+\sum_{i=1}^q \alpha_i \varepsilon_{t-i}^2\)。
- **GARCH(p,q)：** 在 ARCH 项之外再引入 \(\sigma_{t-j}^2\) 的滞后项 \(\beta_j\)，常用 **GARCH(1,1)** 捕捉持久波动。

## 2. CLI 示例（App 命令行）

演示数据列为 `time` 与 `ret`（见 `datasets/demo/garch_demo.csv`）。

```text
use datasets/demo/garch_demo.csv
garch ret, time(time)
arch ret, time(time) arch(1)
garch ret, time(time) arch(1) garch(1)
garch ret, time(time) garch(1 1)
```

说明：

- **`garch`**：省略 `garch(p q)` 时默认 **GARCH(1,1)**。`garch(p q)` 为两个整数；`garch(q)` 单个整数表示 **\(p=1\)**、\(q=\) 给定值。
- **`arch(p)` 在 `garch` 命令中：** 映射 **`garch_p`**（ARCH 项阶数），与总规示例 `arch(1) garch(1)` 对齐。
- **`arch`**：`arch(q)` **必填**，\(q\in[1,12]\)（与 Runtime 一致）。

可选优化控制（与协议键名一致）：`maxiter(...)`、`tol(...)`。

## 3. 如何阅读结构化结果

拟合成功后，`result_payload` 含：

- **`glance` / `tidy`：** 样本量、对数似然、信息准则、\(\mu,\omega,\alpha_i,\beta_j\) 等系数行（首期标准误可为空，见实现）。
- **`diagnostics`：** **`persistence`**（\(\sum\alpha+\sum\beta\)）接近 1 表示冲击衰减很慢；**`conditional_volatility_preview`** 为条件波动序列的**前缀预览**，全长在 **`volatility_length`**；**`failure_code`** 在非收敛或数值失败时出现。
- **`warnings`：** 教学向提示（如优化未收敛）。

App 中 **`VolatilitySummaryPanel`** 仅展示上述结构化字段，**不在 UI 内重算**波动率路径。

## 4. 限制与非目标（首期）

- 不做 **VaR/ES 产品化**、不做 **BEKK/DCC** 等多变量波动率模型。
- 不在首期对标准化残差自动附带 **Ljung-Box**（若未来增加，会在 `runtime-protocol` 单列键名）。
- 条件方差全序列可能很长：默认 **预览 + 长度元数据**，避免 JSON 过大。

## 5. 最小自检

1. `garch ret, time(time)` 能返回 `status: success`，且 `diagnostics` 含 `loglik`、`persistence`、`volatility_length`。  
2. 故意缩短样本或填写非法阶数时，应得到 **结构化错误** 或 **高优先级 warnings**（而非静默空表）。
