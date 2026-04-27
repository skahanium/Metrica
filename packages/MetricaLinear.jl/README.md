# MetricaLinear.jl

Metrica 的参考线性模型实现包。

## 第一阶段范围

- OLS
- 通过 Base API 返回的共享结果对象
- 由公式与类表数据驱动的模型拟合
- 面向 Runtime / 脚本层的结构化结果载荷

## 延后范围

- IV
- GLS
- 超出架构验证阶段的 WLS

## 当前最小可用入口

当前仓库中最小且已验证的真实 OLS 入口为：

- `fit_ols_file(path, formula)`
- `result_to_payload(result)`
- `/Users/skahanium/Metrica/scripts/run_minimal_ols.jl`

先初始化仓库 Julia 环境：

```bash
julia /Users/skahanium/Metrica/scripts/init_julia_env.jl
```

直接运行 demo 数据：

```bash
julia /Users/skahanium/Metrica/scripts/run_minimal_ols.jl /Users/skahanium/Metrica/apps/metrica-desktop/data/demo.csv "y ~ x1 + x2"
```

该脚本会输出结构化 JSON，当前适合作为最小手工验证入口；Runtime 与桌面端真实桥接仍属于后续链路工作。
