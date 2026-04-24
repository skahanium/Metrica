# 文档边界

本文件界定各主要项目文档的职责范围。

其目的在于避免重复、相互矛盾的指引，以及跨文档的范围蔓延。

## 规则

- 每个文档只负责一个决策层级。
- 高层文档定义方向，不写低层载荷细节。
- 低层文档定义子系统细节，不写项目战略。
- 实施计划描述有序执行，不写架构理由。
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

不拥有：

- 当前冲刺范围
- Runtime 线协议示例
- 桌面 MVP 执行细节

### `docs/superpowers/specs/2026-04-24-metrica-dual-track-design.md`

拥有：

- 项目级双轨架构
- Core / Runtime / App 分层
- 跨平台产品定位

不拥有：

- 字段级 Runtime 请求与响应 schema
- 逐页桌面 MVP 细节
- 逐步实施排序

参考：

- `docs/architecture/runtime-protocol.md`
- `docs/architecture/app-shell.md`
- 未来的垂直切片规格

### `docs/architecture/runtime-protocol.md`

拥有：

- Runtime 动作名称
- 请求/响应载荷示例
- Runtime 与消费者之间的序列化边界

不拥有：

- 项目战略
- 包职责划分
- 为解释载荷所不需要的桌面产品范围

### `docs/architecture/app-shell.md`

拥有：

- 桌面工作台信息架构
- MVP 页面
- MVP 验收与范围外边界

不拥有：

- Runtime 载荷 schema
- Core 包语义
- 全仓库交付计划

### `docs/superpowers/plans/2026-04-24-metrica-foundation-plan.md`

拥有：

- 第一阶段执行顺序
- 任务排序
- 具体脚手架工作项

不拥有：

- 长篇架构解释
- 深层子系统理由
- 尚未排期的未来切片设计决策

### `docs/superpowers/specs/2026-04-24-metrica-alpha-vertical-slice-design.md`

拥有：

- 第一条可执行端到端切片
- 数据集 → OLS → 结构化结果 → Runtime → 桌面渲染的精确用户流
- 第一条真实链路包含与排除的边界

不拥有：

- 长期路线图
- 全部未来模型族
- 通用 AI 工作流政策

### `docs/superpowers/plans/2026-04-24-metrica-alpha-vertical-slice-plan.md`

拥有：

- 第一条真实端到端切片的执行顺序
- Core、Runtime、App 上的任务分组
- 第一条链路的验证检查点

不拥有：

- 高层产品架构
- 通用仓库脚手架工作
- 无关的未来里程碑

## 编辑策略

修改文档时：

1. 先更新归属文档。
2. 在非归属文档中，可行时用简短指针替换重复细节。
3. 不要将请求示例、页面列表或里程碑定义复制到多个文件。
4. 若新主题无法干净地归入现有文档，则新建聚焦文档并在此登记。
