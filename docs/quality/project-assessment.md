# Metrica 项目技术评估（可信度基线）

> **评估日期：** 2026-06-16  
> **分支基准：** `credibility-support`  
> **方法：** 源码、本地门禁与质量文档对照  

## 总体

三层架构与结构化协议（`glance` / `tidy` / `augment`、结构化警告）已落地。完善阶段 P0（18 包测试 + Runtime 串行集成 + 对齐脚本）仍是基础质量门禁。

当前可信度口径已收紧：仓库删除了未经 Stata / statsmodels / R / 闭式公式交叉验证的 `datasets/golden/*.json` 期望结果文件。`datasets/golden/*.csv` 现在只是手动外部验证输入数据，不能单独证明模型数值正确。

README 仍建议「不可用于生产或未经审阅的正式研究」；这与当前证据状态一致。

## 外部验证与测试

| 项目 | 状态 |
|------|------|
| JSON 标准答案 | 已移除；未交叉验证结果不得称为 golden |
| CSV 输入数据 | 保留并扩展，见 `datasets/golden/*.csv` |
| 手动验证覆盖表 | 见 [manual-golden-command-coverage.md](manual-golden-command-coverage.md) |
| 快路径 | `make test-golden` 检查无 JSON 期望文件且 CSV 可解析 |
| MetricaData 测试 | 多文件（query/inspect/operate/transform 等），非早期「21 行」口径 |

## 下一步可信度主线

- 为每条高优先级模型命令补 Stata / statsmodels / R / 闭式公式审计记录。
- 将通过交叉验证的路径逐条升级为 L2，不按包整体乐观升级。
- 对无法外部复核的路径明确标注 `external-limited` 或 `not applicable`。
- 发布前确认 README、package-status、golden-values 与手动验证覆盖表口径一致。

## 后续（非阻塞）

- 固定或记录 Stata / Python / R 验证环境。
- 为已通过审计的路径重新引入真正 external golden JSON 或等价机器可读证据。
- VAR、MCMC、空间与复杂抽样等方法需单独制定外部验证策略。

历史详评见仓库根目录 `PROJECT_REVIEW.md`（2026-05-24 快照，**可能滞后**；以本文件与 package-status 为准）。
