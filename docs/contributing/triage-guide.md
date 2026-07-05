# Issue 分流与标签规则

本规则面向个人维护者，目标是低成本分流，而不是建立复杂治理流程。

## 初始分流

新 Issue 默认保留 `status: needs-triage`，维护者第一次阅读后做三件事：

1. 判断是否符合当前阶段
2. 标记类型和区域
3. 决定是否适合外部贡献者领取

## 标签

类型标签：

- `bug`：行为错误、崩溃、错误结果、错误提示不清楚
- `docs`：README、教程、架构文档、贡献文档
- `tests`：测试覆盖、golden-value、回归 fixture
- `quality`：benchmark、release checklist、开发脚本、质量门禁

区域标签：

- `julia-core`：`packages/`
- `runtime`：`runtime/` 或 Julia bridge
- `app`：`apps/`

贡献标签：

- `good first issue`：能在一个小 PR 内完成，问题边界清楚，预期文件和验证命令明确
- `help wanted`：维护者欢迎外部帮助，但任务可能需要更多上下文
- `out of scope`：当前阶段不接受，尤其是新增模型族、新 `model_type` 或大重构

## `good first issue` 标准

只有同时满足以下条件才打 `good first issue`：

- 不需要理解多个子系统
- 不改变公共协议或模型语义
- 可以用一个明确命令验证
- 失败/完成标准能写在 Issue 描述里

适合示例：

- 修正文档中的路径或命令
- 给已有 bug 加一个小回归测试
- 为现有模型补一个小 golden fixture
- 改善错误消息或 warning 文案

不适合示例：

- 新模型实现
- Runtime 协议重设计
- App 大交互改版
- 需要跨多个包重构
