# Metrica 桌面端

Metrica 的桌面工作台：**当前可执行体为 `tao` + `wry` 宿主 + `src-react` 前端**（详见 `docs/architecture/app-shell.md`）；跨平台能力与打包形态以路线图 `S6` 为准。

## 职责

- 项目工作区与导航
- 数据导入与检查
- **CLI-first** 命令输入、解析与执行编排（对接 Runtime）
- 结果消息流与结构化渲染
- 面向教学的解释与警告

## 非职责

- 计量估计逻辑
- Julia 包内部实现细节
- 数值算法实现

## 当前主链路（`S4` 收口后）

桌面端以 **命令消息流** 为研究与复现主路径：用户输入 Stata 风格 CLI 命令，应用解析后调用 Runtime（`fit_model`、`inspect_dataset`、`query_dataset`、`transform`、项目与导出等动作），在会话中展示结构化 `glance`、`tidy`、`diagnostics` 与 `warnings`。详细行为见 `docs/architecture/app-shell.md` 与 `docs/architecture/runtime-protocol.md`。

已实现或演进中的能力（非穷尽，以代码为准）：

- 选择本地 CSV、配置 Runtime 端点与工作目录
- CLI 命令解析与反馈（`commandGrammar` / `commandExecutor`）
- 触发真实 `inspect_dataset`、`query_dataset`、`transform`、`fit_model` 等请求
- 线性、面板及 **`S4` 已注册 `model_type`** 的结构化结果渲染
- 项目保存/打开、运行列表、`export` / `rerun` 等动词路径（随迭代持续补齐）
- 渲染结构化 `glance`、`tidy`、`augment_preview`（若请求）、warnings 与 error

仍可能不完整或非目标的能力（见主设计「非目标」与路线图）：

- 全模型、全流程统一的「出版级」图表导出管线（当前仅有部分 CLI/前端路径，如事件研究图 `chartExport`）
- 多模型对比工作区完整产品化
- 崩溃后自动恢复全部 UI 状态

## 当前浏览器边界

当前页面使用浏览器原生文件选择器，但在纯浏览器环境中，宿主未必会把本地绝对路径暴露给页面。  
因此：

- 若宿主提供 `file.path`，页面会自动填入可用于 Runtime 的路径
- 若宿主不提供 `file.path`，页面只能填入文件名，用户仍需确认路径输入是否可被 Runtime 访问

这不是前端解析 CSV；数据检查与预览仍以 Runtime 返回的结构化结果为唯一真相。
