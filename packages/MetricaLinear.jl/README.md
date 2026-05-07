# MetricaLinear.jl

Metrica 的参考线性模型实现包。

## 已实现能力

- OLS / WLS（加权最小二乘）
- HC1 稳健标准误
- Cluster 聚类稳健标准误
- IV / 2SLS（工具变量回归）
- GLS（广义最小二乘）
- 结构化结果载荷（glance / tidy / augment / diagnostics / warnings）
- 近奇异设计矩阵检测（条件数校验）
- 欠识别 / 秩亏 / 自由度不足的结构化错误

## 当前入口

```julia
using MetricaLinear
result = fit(OLSModel, "y ~ x1 x2", "data.csv"; vcov=:HC1)
payload = result_to_payload(result)
```

先初始化仓库 Julia 环境：

```bash
julia /Users/skahanium/Metrica/scripts/init_julia_env.jl
```

直接运行 demo 数据：

```bash
julia /Users/skahanium/Metrica/scripts/run_minimal_ols.jl /Users/skahanium/Metrica/apps/metrica-desktop/data/demo.csv "y ~ x1 + x2"
```

该脚本会输出结构化 JSON，可作为包层手工验证入口。当前仓库中的 Runtime 与桌面端真实桥接已建立；后续 Post-Alpha 工作将以这条 OLS 全链路作为稳定基线，继续补 WLS、稳健协方差与更完整输出能力。
