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

## 里程碑口径说明

按 `Metrica.jl-计量经济学框架-完善版.md` 的总体路线，`WLS` 仍属于 `阶段 2A (Linear)` / `里程碑 2 (教学向 OLS)` 的目标范围。

但当前仓库中的 Alpha 垂直切片只负责验证最小真实 OLS 全链路，因此现阶段暂未实现：

- WLS
- HC1 / Cluster 等更丰富协方差规格
- 更完整的线性模型族扩展

换言之，`WLS` 不是被移出总路线，而是被顺延到 OLS Alpha 链路验证通过之后继续补齐。

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

该脚本会输出结构化 JSON，可作为包层手工验证入口。当前仓库中的 Runtime 与桌面端真实桥接已建立；后续 Post-Alpha 工作将以这条 OLS 全链路作为稳定基线，继续补 WLS、稳健协方差与更完整输出能力。
