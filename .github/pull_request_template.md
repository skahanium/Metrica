## 描述

<!-- 简要描述变更内容 -->

## 关联 Issue

<!-- 如有关联 Issue，请引用：Fixes #123 -->

## 变更类型

- [ ] Bug 修复
- [ ] 测试补充
- [ ] 文档更新
- [ ] 开源基础设施
- [ ] Golden-value / benchmark
- [ ] 其他（请说明）

## 影响范围

- [ ] Julia Core 包
- [ ] Runtime
- [ ] Desktop App
- [ ] 文档 / 教程
- [ ] CI / 开发工具

是否触及结构化协议（`glance` / `tidy` / `augment` / warnings / diagnostics）：

- [ ] 是
- [ ] 否

## 测试

<!-- 描述如何验证变更 -->

- [ ] 已运行相关 Julia 包测试：`julia --project=packages/<Package>.jl -e 'using Pkg; Pkg.test()'`
- [ ] 已运行核心测试：`make test-julia-core`
- [ ] 已运行 Runtime 测试：`cargo test --lib --manifest-path runtime/metrica-runtime/Cargo.toml`
- [ ] 已运行 App 测试：`cd apps/metrica-desktop && npm test`
- [ ] 如涉及数值结果，已更新或说明 golden-value / benchmark

## 检查清单

- [ ] 变更符合仓库架构（见 AGENTS.md）
- [ ] 未新增模型族或 model_type
- [ ] 测试覆盖未降低
- [ ] 相关文档已同步更新
- [ ] 没有把 planned / under validation 能力写成已完成能力
