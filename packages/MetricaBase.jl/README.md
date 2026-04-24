# MetricaBase.jl

Metrica 生态的协议内核。

## 职责

- 抽象模型与结果类型
- 共享公共 API，例如 `fit`、`coef`、`vcov`、`predict`
- 结构化结果语义，例如 `glance`、`tidy`、`augment`
- ModelFrame 与预处理契约
- 能力与警告协议

## 非职责

- OLS 或其他估计量的具体实现
- 稳健协方差算法
- 表格或 HTML 渲染
- 可视化或桌面逻辑
