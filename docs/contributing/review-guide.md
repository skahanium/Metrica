# Review 规则

Metrica 当前由个人维护为主，review 目标是守住架构边界和结果可信度，而不是追求流程复杂度。

## 通用检查

- 变更是否符合 [AGENTS.md](../../AGENTS.md) 的 Core / Runtime / App 边界
- 是否新增了模型族或 `model_type`；当前阶段默认拒绝
- 用户可见行为是否更新 README、教程或架构文档
- 数值结果变更是否有测试或 golden-value 说明
- 是否只修改必要文件，没有大范围格式化或无关重排

## Julia Core

- 不从打印文本解析下游行为，结果必须保持结构化：`glance`、`tidy`、`augment`、warnings、diagnostics
- 缺失值、样本量变化和错误路径必须有可读结构化 warning/error
- Bug 修复应包含回归测试；数值修复优先补 deterministic fixture 或 golden-value
- 包依赖必须写入对应 `Project.toml`，不能只依赖聚合环境偶然可用

## Runtime

- Runtime 只做进程编排、请求/响应 schema、日志和取消，不重复计量逻辑
- 错误返回必须结构化，不能吞掉 Julia 侧错误
- 修改 bridge 或 schema 时，应同步 `docs/architecture/runtime-protocol.md`

## App

- App 消费结构化 payload，不解析终端摘要文本
- UI 改动不得引入计量估计逻辑
- 测试应覆盖命令解析、状态流或结果展示的用户可见行为

## Docs / Quality

- 不把 planned / under validation 写成已完成
- 包数量、CI 状态、benchmark 状态必须和仓库事实一致
- release checklist、package status 和 README 口径要同步
