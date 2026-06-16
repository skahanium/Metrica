# `S3` 施工指引：复现与报告产品化

> **状态：部分已落地 / 非当前冲刺主线。** `S1`–`S5` 已完成；仓库处于**回顾完善阶段**（可信度与测试优先）。当前执行锚点见 [docs/quality/project-assessment.md](../quality/project-assessment.md)。安装包与分发见 `S6`。

## 阶段目标

`S3` 的目标是把"能算"升级为"能做完整项目"，使报告导出、项目保存和运行记录成为统一产品能力，而不是附加脚本。

## 纳入能力

- 项目文件、运行记录、数据谱系、结果复现
- 单模型完整报告（Markdown）
- 多模型对比表（手动选择，含数据兼容性检查）
- 结构化 CSV 导出（tidy / glance / diagnostics）
- 出版级图表导出（SVG + PNG）
- 错误恢复（Julia 崩溃后恢复工作区状态）

## 明确排除项

- 不在本阶段优先增加新模型族
- 不开放自由文本脚本入口作为复现机制
- 不把 AI 解释层混入报告产品化阶段
- 不做安装包与产品化打包（已移至 S6）

## 历史映射

- 对应旧 `M8-M9`

## 已落地能力（代码为准，2026-06）

- 项目保存/打开、运行列表、`rerun`（App `commandExecutor` + Runtime 项目动作）
- `export_report`：Markdown 与 tidy/glance/diagnostics CSV（Runtime + `MetricaOutput`）
- CLI-first 命令流与结构化结果渲染（见 [app-shell.md](../architecture/app-shell.md)）

## 阶段验收（尚未完全产品化）

- [ ] 出版级图表导出管线（SVG/PNG）统一、可复现
- [ ] 多模型对比表完整产品化（含兼容性检查与教学提示）
- [ ] Julia 崩溃后工作区状态自动恢复（部分能力在桌面宿主，未达 S3 全文验收）
- [x] 结果可导出为 Markdown 报告与 CSV 表格（主路径可用）
- [x] 项目可保存、重开、重跑并保留关键上下文（主路径可用）
