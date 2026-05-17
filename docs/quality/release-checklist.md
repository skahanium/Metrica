# 发布前质量门禁

发布前必须完成以下检查。若某项无法执行，必须在 release notes 中说明原因和风险。

## CI 与测试

- [ ] PR 阻塞 CI 全绿：`MetricaBase.jl`、`MetricaLinear.jl`、Rust runtime、desktop App tests。
- [ ] 最新 nightly/full quality workflow 已审阅，并记录所有失败包的 issue 或修复 PR。
- [ ] 受影响 Julia 包已运行 `julia --project=packages/<Package>.jl -e 'using Pkg; Pkg.test()'`。
- [ ] Runtime 已运行 `cargo check` 和 `cargo test --lib`。
- [ ] App 已运行 `npm ci` 和 `npm test`。

## Golden 与 Benchmark

- [ ] 受影响模型族的 golden-value 测试无新增回归。
- [ ] 新增或修改数值算法时，已补充或更新 golden fixture。
- [ ] benchmark 报告已更新；若性能不受影响，release notes 中明确说明未更新原因。
- [ ] README 不包含未验证的性能倍数或无法复现的 benchmark 结论。

## 文档与发布资产

- [ ] README、CHANGELOG、CITATION、SUPPORT、SECURITY 的版本、阶段、能力口径一致。
- [ ] `docs/quality/package-status.md` 已反映最新 CI/golden/benchmark 状态。
- [ ] 用户可见行为变更已更新教程或架构文档。
- [ ] 没有把 planned / under validation 能力写成已完成能力。
