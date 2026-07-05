# 发布前质量门禁

发布前必须完成以下检查。若某项无法执行，必须在 release notes 中说明原因和风险。

## 测试与本地验证

- [ ] P0 本地门禁通过：18 个 Julia 包、对齐脚本、Runtime 串行集成与 desktop App tests。
- [ ] 受影响 Julia 包已运行 `julia --project=packages/<Package>.jl -e 'using Pkg; Pkg.test()'`。
- [ ] Runtime 已运行 `cargo check` 和 `cargo test --lib`。
- [ ] App 已运行 `npm ci` 和 `npm test`。

## Golden 与 Benchmark

- [ ] 受影响模型族的外部验证输入、审计记录或替代说明已同步。
- [ ] 新增或修改数值算法时，已补充外部验证计划或说明为何暂不适用。
- [ ] benchmark 报告已更新；若性能不受影响，release notes 中明确说明未更新原因。
- [ ] README 不包含未验证的性能倍数或无法复现的 benchmark 结论。

## 文档与发布资产

- [ ] README、CHANGELOG、CITATION、SUPPORT、SECURITY 的版本、阶段、能力口径一致。
- [ ] `docs/quality/package-status.md` 与 [credibility-tiers.md](credibility-tiers.md) 已反映最新质量/golden/benchmark 状态。
- [ ] 版本号符合 [版本策略](../governance/versioning.md)，破坏性变更已在 CHANGELOG 和 release notes 中明确说明。
- [ ] 支持范围符合 [支持策略](../governance/support-policy.md)，没有承诺未建立的 SLA、长期维护分支或发布渠道。
- [ ] 架构、协议、治理或破坏性变更已有 Issue 或 [决策记录](../governance/decision-records.md)。
- [ ] 用户可见行为变更已更新教程或架构文档。
- [ ] 没有把 planned / under validation 能力写成已完成能力。
