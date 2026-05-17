# Benchmarks

`benchmarks/` 保存可复现性能验证脚本和结果说明。第一阶段只启用最小 harness，避免 README 继续展示未验证性能倍数。

## 运行

```bash
julia --project=packages/MetricaRuntime.jl benchmarks/run_core_benchmarks.jl
```

脚本会把结果写入 `benchmarks/results/core-benchmarks.md`。结果文件是本地生成产物，不要求每次提交更新；正式发布前按 `docs/quality/release-checklist.md` 审阅。

## 当前覆盖

| Case | Status | Notes |
|---|---|---|
| OLS | covered | 使用 `datasets/golden/linear_ols.csv` |
| IV | covered | 使用 `datasets/demo/gmm_linear_demo.csv` 的 IV 路径 |
| Logit | covered | 使用脚本内确定性 DataFrame |
| GMM | covered | 使用 `datasets/demo/gmm_linear_demo.csv` |
| Spatial lag | covered | 使用 `datasets/demo/spatial_demo.csv` 与权重文件 |
