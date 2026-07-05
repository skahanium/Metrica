# 可信度分级

Metrica 用可审计证据链描述「能在多大程度上依赖数值与协议」，避免 README 与实现脱节。当前仓库已移除未经交叉验证的 JSON 期望结果，因此所有模型族默认回到 L1，等待 Stata / statsmodels / R / 闭式公式复核后再升级。

## L1 — 协议可信

**含义：** 结构化输出形状、警告码、Runtime 校验与 App 消费路径一致；不保证特定数值与外部软件一致。

**典型证据：**

- `MetricaBase` 序列化与 formula 边界测试
- `scripts/check_model_type_alignment.jl`
- `vertical_slice` 集成测试（`--test-threads=1`）
- PR 前本地门禁：`Pkg.test()` 全 18 包

## L2 — 外部参考可信（模型族内）

**含义：** 至少一条关键模型路径已用 Stata、statsmodels/Python、R 或可审查闭式公式完成交叉验证，并记录比较字段、容差、版本和命令。

**典型证据：**

- 固定输入 CSV
- 外部验证命令或脚本
- 审计记录
- Metrica 输出与外部参考在明确容差内一致

## L3 — 研究审慎可用（模型族内）

**含义：** 在 L2 基础上，外部验证环境可复现，发布前可重复运行；无已知 P0 回归。

**典型证据：**

- 固定 Stata / Python / R 版本记录
- 发布前复跑记录
- 质量矩阵与 README 口径同步

## README 叙述阶梯

| 阶段 | 允许表述 |
|------|----------|
| 当前默认 | 不可用于生产或正式研究；见 CONTRIBUTING |
| 单路径 L2 | 某个 model_type 的特定路径已通过外部参考验证 |
| 教学路径 L2 齐备后 | 教学与常见实证**部分**场景可审慎使用；仍以 package-status 为准 |
| 禁止 | 「与 Stata/R 完全等价」「全部模型已外部验证」 |

## 维护规则

- 新增或修改外部验证输入时更新 [manual-golden-command-coverage.md](manual-golden-command-coverage.md)。
- 某路径升级为 L2/L3 时，同步更新 [package-status.md](package-status.md) 与 [golden-values.md](golden-values.md)。
