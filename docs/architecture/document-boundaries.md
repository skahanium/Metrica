# 文档边界

本文件界定当前保留文档的职责范围。早期 foundation、dual-track、vertical slice 与 visualization 草案，以及已完成里程碑的设计/计划文档均已清理；后续不得再用“历史参考”名义重新制造并行主线。

## 规则

- 每个文档只负责一个决策层级。
- 主设计定义方向、边界与当前事实基线。
- 子系统架构文档定义局部协议或工作台结构。
- 实施计划只描述接下来要做什么，不重复架构理由。
- 若某细节已有归属文档，其他文档应链接而非复述。

## 当前归属

### `README.md`

拥有：

- 仓库身份
- 当前仓库形态
- 指向权威文档的链接

不拥有：

- 架构细节
- 协议载荷
- 实施任务清单

### `AGENTS.md`

拥有：

- AI 协作规则
- 对智能体与行内补全的工作流期望
- 全仓库执行纪律

不拥有：

- 产品设计
- Runtime schema 细节
- 子系统功能规格

### `Metrica.jl-计量经济学框架-完善版.md`

拥有：

- 长期产品愿景
- 生态方向
- 战略性包拆分
- 阶段 `S1-S7` 的最高层边界
- 阶段划分原则与历史编号映射规则

不拥有：

- 当前冲刺范围
- Runtime 线协议示例
- 桌面 MVP 执行细节

### `docs/roadmap/`

拥有：

- 阶段级施工指引
- 各阶段的交付口径、施工原则与验收边界
- `S7` AI 增强层的未来预留约束

不拥有：

- 当前冲刺任务清单
- 字段级 Runtime schema
- 具体组件实现细节
- 对根目录总体蓝图的覆盖权

### `docs/quality/project-assessment.md`

拥有：

- 当前可信度基线与评分
- **下一步 30 天**可勾选 backlog（完善阶段执行锚点）
- 与 [package-status.md](../quality/package-status.md) 的衔接说明

不拥有：

- 长期产品愿景（见总蓝图）
- 字段级 Runtime schema

### `docs/superpowers/plans/2026-05-16-s5-execution-plan.md`

拥有：

- `S5` 历史实施顺序与验证习惯（**已完成，非活跃计划**）

不拥有：

- 当前冲刺任务（见 `docs/quality/project-assessment.md`）
- 替代总规或路线图的完整分期规格（须回链总规与 `docs/roadmap/s5-advanced-research-topics.md`）

### `docs/superpowers/specs/2026-04-30-metrica-main-design.md`

拥有：

- 当前唯一主设计
- 当前稳定主链路的事实基线
- Core / Runtime / App 分层边界
- 教学友好、结构化结果、受控扩展等全局产品原则
- 当前包含与排除范围

不拥有：

- 字段级 Runtime 请求与响应细节
- 桌面工作台组件级设计
- 逐步实施任务清单

### `docs/architecture/runtime-protocol.md`

拥有：

- Runtime 动作名称
- 请求/响应载荷示例
- Runtime 与消费者之间的序列化边界
- 当前 HTTP 端点
- 后续高级能力在协议层的扩展约束

不拥有：

- 项目战略
- 包职责划分
- 桌面产品布局

### `docs/architecture/app-shell.md`

拥有：

- 当前桌面宿主（`tao` + `wry`）与 `metrica://` 原生桥、`Runtime` HTTP 客户端分工
- CLI-first 主界面结构、主要 React 模块与目录对应关系
- 数据网格与图表在 App 侧的实际用法（以代码为准）

不拥有：

- Runtime 载荷 schema
- Core 包语义
- 全仓库交付计划

## 编辑策略

修改文档时：

1. 先确认新内容是否可并入现有主设计、当前计划或子系统架构文档。
2. 不为已完成阶段保留镜像 `spec`、镜像 `plan`、历史入口或 archive 副本。
3. 若确需新增 `spec` / `plan`，必须是当前仍在实施或即将实施的工作，并在完成后及时回收。
4. 删除或重命名文档后，必须检查全仓库引用，避免悬空链接。

## 历史编号保留规则

- 旧 `M` 号可以继续存在于 milestone `spec/plan`、测试记录与完成总结中。
- 新阶段叙事统一使用 `S1-S7`，旧 `M` 号只作为历史映射，不再单独承担长期路线表达。
- `docs/superpowers/specs/` 与 `docs/superpowers/plans/` 只保留当前活跃工作；已完成文档应直接删除。
