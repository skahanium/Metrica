# 可信度分级

Metrica 用可审计证据链描述「能在多大程度上依赖数值与协议」，避免 README 与实现脱节。分级与 [package-status.md](package-status.md) 的 Golden / Credibility 列一一对应。

## L1 — 协议可信

**含义：** 结构化输出形状、警告码、Runtime 校验与 App 消费路径一致；不保证特定数值与外部软件一致。

**典型证据：**

- `MetricaBase` 序列化与 formula 边界测试
- `scripts/check_model_type_alignment.jl`
- `vertical_slice` 集成测试（`--test-threads=1`）
- PR 阻塞 CI：`Pkg.test()` 全 18 包

## L2 — 数值可信（模型族内）

**含义：** 该模型族至少有一个标准 [golden-value](golden-values.md) 用例：`datasets/golden/<id>.{csv,json}`、再生脚本、包内 golden 测试，容差仅声明在 JSON 中。

**典型证据：**

- `scripts/golden/compute_*_reference.jl`
- 包内 `test/test_golden.jl`（通过 `make test-golden`）
- `reference.notes` 说明样本处理与 Metrica 行为

## L3 — 研究审慎可用（模型族内）

**含义：** 在 L2 基础上，参考值可在文档化环境（如固定 R 版本）中由维护者或 CI smoke 复现；无已知 P0 回归。

**典型证据：**

- [scripts/golden/README.md](../../scripts/golden/README.md) 中的 R 复现步骤
- 可选 workflow `golden-r-smoke.yml`（非 PR 阻塞）
- release checklist 中勾选受影响族的 golden

## README 叙述阶梯

| 阶段 | 允许表述 |
|------|----------|
| 当前默认 | 不可用于生产或正式研究；见 CONTRIBUTING |
| 核心路径 L2（线性 + 离散 GLM） | 部分 model_type 已通过 golden 验证，列表见 package-status |
| 教学路径 L2 齐备后 | 教学与常见实证**部分**场景可审慎使用；仍以 package-status 为准 |
| 禁止 | 「与 Stata/R 完全等价」「全部模型已外部验证」 |

## 维护规则

- 新增或修改 golden 时更新 `package-status.md` 与 `golden-values.md`。
- 发布前执行 [release-checklist.md](release-checklist.md) 中的 Golden 与文档项。
