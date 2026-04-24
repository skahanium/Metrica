# Metrica 基础实施计划

> **状态：已完成。** 本计划中的脚手架、边界文档和初始 schema 均已落地。保留此文件作为历史参考。当前活跃实施计划为 `docs/superpowers/plans/2026-04-24-metrica-alpha-vertical-slice-plan.md`。
>
> **面向代理工作者：** 须使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans，**按任务逐步**执行本计划。步骤使用复选框语法（`- [ ]`）跟踪。

**目标：** 为双轨产品搭建仓库基础：Julia Core 与跨平台桌面应用骨架。

**架构：** 仓库分为三层：`packages/` 中的 Julia 包、`runtime/` 中的 Rust 运行时桥、`apps/` 中的 Tauri 桌面壳。首个实现周期以最小 OLS 就绪的 Core 契约与面向桌面的 runtime/结果 schema 验证架构，不追求模型广度。

**技术栈：** Julia、Rust、Tauri、React、TypeScript、JSON、Markdown

---

## 文件结构

- 创建：`docs/superpowers/specs/2026-04-24-metrica-dual-track-design.md`
- 创建：`docs/superpowers/plans/2026-04-24-metrica-foundation-plan.md`
- 创建：`packages/.gitkeep`
- 创建：`apps/.gitkeep`
- 创建：`runtime/.gitkeep`
- 创建：`tutorials/.gitkeep`
- 创建：`datasets/.gitkeep`
- 创建：`benchmarks/.gitkeep`
- 创建：`scripts/.gitkeep`
- 创建：`apps/metrica-desktop/README.md`
- 创建：`runtime/metrica-runtime/README.md`
- 创建：`packages/MetricaBase.jl/README.md`
- 创建：`packages/MetricaLinear.jl/README.md`
- 创建：`packages/MetricaOutput.jl/README.md`
- 创建：`docs/architecture/runtime-protocol.md`
- 创建：`docs/architecture/app-shell.md`

## 任务 1：为双轨架构创建仓库脚手架

**涉及文件：**
- 创建：`packages/.gitkeep`
- 创建：`apps/.gitkeep`
- 创建：`runtime/.gitkeep`
- 创建：`tutorials/.gitkeep`
- 创建：`datasets/.gitkeep`
- 创建：`benchmarks/.gitkeep`
- 创建：`scripts/.gitkeep`

- [ ] **步骤 1：创建根目录占位**

使用 `apply_patch` 添加空占位文件：

```diff
*** Add File: packages/.gitkeep
+
*** Add File: apps/.gitkeep
+
*** Add File: runtime/.gitkeep
+
*** Add File: tutorials/.gitkeep
+
*** Add File: datasets/.gitkeep
+
*** Add File: benchmarks/.gitkeep
+
*** Add File: scripts/.gitkeep
+
```

- [ ] **步骤 2：验证脚手架存在**

运行：

```powershell
Get-ChildItem -Force | Select-Object Name
```

预期：

```text
apps
benchmarks
datasets
docs
packages
runtime
scripts
tutorials
README.md
Metrica.jl-计量经济学框架-完善版.md
```

- [ ] **步骤 3：提交脚手架**

若已初始化 git，运行：

```powershell
git add packages/.gitkeep apps/.gitkeep runtime/.gitkeep tutorials/.gitkeep datasets/.gitkeep benchmarks/.gitkeep scripts/.gitkeep
git commit -m "chore: add dual-track repository scaffold"
```

预期：

```text
[main ...] chore: add dual-track repository scaffold
```

## 任务 2：书面界定桌面应用与 Runtime 边界

**涉及文件：**
- 创建：`apps/metrica-desktop/README.md`
- 创建：`runtime/metrica-runtime/README.md`
- 创建：`docs/architecture/app-shell.md`
- 创建：`docs/architecture/runtime-protocol.md`

- [ ] **步骤 1：添加桌面壳 README**

创建 `apps/metrica-desktop/README.md`，内容为：

```markdown
# Metrica 桌面端

Metrica 的跨平台原生桌面工作台。

## 职责

- 项目工作区与导航
- 数据导入与检查
- 模型配置与执行触发
- 结果渲染与导出
- 面向教学的解释与警告

## 非职责

- 计量估计逻辑
- Julia 包内部实现细节
- 数值算法实现
```

- [ ] **步骤 2：添加 Runtime 桥 README**

创建 `runtime/metrica-runtime/README.md`，内容为：

```markdown
# Metrica Runtime

桌面应用与 Julia Core 之间的桥接层。

## 职责

- 启动与管理 Julia 进程
- 接收结构化任务请求
- 返回结构化结果与警告
- 处理日志、取消与失败传播

## 非职责

- UI 渲染
- 计量模型语义
- 直接面向用户的流程设计
```

- [ ] **步骤 3：添加应用壳层架构说明**

创建 `docs/architecture/app-shell.md`，内容为：

```markdown
# 应用壳层（App Shell）

桌面壳层是基于 Tauri 的工作台，包含六个第一阶段区域：

- 首页（Home）
- 项目（Project）
- 数据检查器（Data Inspector）
- 模型构建器（Model Builder）
- 结果（Results）
- 学习（Learn）

壳层必须消费结构化结果载荷，且不得解析终端摘要文本。
```

- [ ] **步骤 4：添加 Runtime 协议说明**

创建 `docs/architecture/runtime-protocol.md`，内容为：

```markdown
# Runtime 协议

第一阶段动作：

- `inspect_dataset`
- `fit_model`
- `export_result`
- `explain_warning`

每个请求必须包含 `task_id`、`action`、`project_context` 以及动作相关载荷。  
每个响应必须包含 `task_id`、`status`、`messages`，以及可选的 `result_payload`。
```

- [ ] **步骤 5：检查文档可读性**

运行：

```powershell
Get-Content -Raw 'apps/metrica-desktop/README.md'
Get-Content -Raw 'runtime/metrica-runtime/README.md'
Get-Content -Raw 'docs/architecture/app-shell.md'
Get-Content -Raw 'docs/architecture/runtime-protocol.md'
```

预期：

```text
各文件包含简洁的边界定义，无 TODO 或占位正文。
```

- [ ] **步骤 6：提交边界文档**

若已初始化 git，运行：

```powershell
git add apps/metrica-desktop/README.md runtime/metrica-runtime/README.md docs/architecture/app-shell.md docs/architecture/runtime-protocol.md
git commit -m "docs: define app shell and runtime boundaries"
```

预期：

```text
[main ...] docs: define app shell and runtime boundaries
```

## 任务 3：界定初始 Julia 包职责

**涉及文件：**
- 创建：`packages/MetricaBase.jl/README.md`
- 创建：`packages/MetricaLinear.jl/README.md`
- 创建：`packages/MetricaOutput.jl/README.md`

- [ ] **步骤 1：添加 Base 包职责说明**

创建 `packages/MetricaBase.jl/README.md`，内容为：

```markdown
# MetricaBase.jl

Metrica 生态的协议内核。

## 职责

- 抽象模型与结果类型
- 共享公共 API，例如 `fit`、`coef`、`vcov`、`predict`
- 结构化结果语义，例如 `glance`、`tidy`、`augment`
- ModelFrame 与预处理契约
- 能力与警告协议

## 非职责

- OLS 或其他估计量的具体实现
- 稳健协方差算法
- 表格或 HTML 渲染
- 可视化或桌面逻辑
```

- [ ] **步骤 2：添加 Linear 包职责说明**

创建 `packages/MetricaLinear.jl/README.md`，内容为：

```markdown
# MetricaLinear.jl

Metrica 的参考线性模型实现包。

## 第一阶段范围

- OLS
- 通过 Base API 返回的共享结果对象
- 由公式与类表数据驱动的模型拟合

## 延后范围

- IV
- GLS
- 超出架构验证阶段的 WLS
```

- [ ] **步骤 3：添加 Output 包职责说明**

创建 `packages/MetricaOutput.jl/README.md`，内容为：

```markdown
# MetricaOutput.jl

Metrica 的输出与报告层。

## 职责

- 终端摘要
- 结构化表格渲染
- Markdown、HTML 与 LaTeX 导出

## 约束

本包必须消费公开的结构化结果，且不得依赖私有 OLS 内部实现。
```

- [ ] **步骤 4：验证包说明**

运行：

```powershell
Get-Content -Raw 'packages/MetricaBase.jl/README.md'
Get-Content -Raw 'packages/MetricaLinear.jl/README.md'
Get-Content -Raw 'packages/MetricaOutput.jl/README.md'
```

预期：

```text
包职责清晰、互不重叠，并与双轨架构一致。
```

- [ ] **步骤 5：提交包说明**

若已初始化 git，运行：

```powershell
git add packages/MetricaBase.jl/README.md packages/MetricaLinear.jl/README.md packages/MetricaOutput.jl/README.md
git commit -m "docs: define initial package responsibilities"
```

预期：

```text
[main ...] docs: define initial package responsibilities
```

## 任务 4：在文档中冻结 Runtime 请求/响应 schema

**涉及文件：**
- 修改：`docs/architecture/runtime-protocol.md`

- [ ] **步骤 1：扩展请求 schema**

更新 `docs/architecture/runtime-protocol.md`，加入：

```json
{
  "task_id": "uuid",
  "action": "fit_model",
  "project_context": {
    "project_id": "proj_001",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "/path/to/data.csv",
    "format": "csv"
  },
  "model_spec": {
    "model_type": "ols",
    "formula": "y ~ x1 + x2 + x3",
    "vcov": {
      "type": "classical"
    }
  },
  "options": {
    "drop_missing": true,
    "return_augment": true
  }
}
```

- [ ] **步骤 2：扩展响应 schema**

在同一文件中补充：

```json
{
  "task_id": "uuid",
  "status": "success",
  "messages": [
    {
      "level": "info",
      "code": "ROWS_DROPPED",
      "text": "因缺失值已移除 12 行。"
    }
  ],
  "artifacts": [],
  "result_payload": {
    "glance": {},
    "tidy": [],
    "augment_preview": [],
    "diagnostics": [],
    "warnings": []
  }
}
```

- [ ] **步骤 3：添加失败契约**

在同一文件中补充：

```json
{
  "task_id": "uuid",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "SINGULAR_MATRIX",
      "text": "设计矩阵奇异，无法估计模型。",
      "hint": "请检查是否存在某一预测变量是其他变量的线性组合。"
    }
  ]
}
```

- [ ] **步骤 4：验证 schema 说明**

运行：

```powershell
Get-Content -Raw 'docs/architecture/runtime-protocol.md'
```

预期：

```text
文档包含明确的请求、成功响应与错误响应示例。
```

- [ ] **步骤 5：提交 schema 文档**

若已初始化 git，运行：

```powershell
git add docs/architecture/runtime-protocol.md
git commit -m "docs: freeze initial runtime schema"
```

预期：

```text
[main ...] docs: freeze initial runtime schema
```

## 任务 5：书面定义首个桌面 MVP

**涉及文件：**
- 修改：`docs/architecture/app-shell.md`

- [ ] **步骤 1：添加第一阶段页面列表**

更新 `docs/architecture/app-shell.md`，加入：

```markdown
## MVP 页面

- 首页（Home）
- 项目（Project）
- 数据检查器（Data Inspector）
- 模型构建器（Model Builder）
- 结果（Results）
- 学习（Learn）
```

- [ ] **步骤 2：添加 MVP 验收标准**

在同一文件中补充：

```markdown
## MVP 验收

当用户能够完成以下事项时，桌面 alpha 即视为成功：

1. 打开项目
2. 导入数据集
3. 配置并运行一个 OLS 模型
4. 查看结构化结果
5. 导出结果摘要
6. 收到可读的警告与错误说明
```

- [ ] **步骤 3：添加范围外列表**

在同一文件中补充：

```markdown
## MVP 范围之外

- 面板模型 UI
- 多模型对比仪表板
- 云同步
- 插件市场
- 完整诊断套件
```

- [ ] **步骤 4：验证 MVP 说明**

运行：

```powershell
Get-Content -Raw 'docs/architecture/app-shell.md'
```

预期：

```text
应用壳层说明清楚描述第一阶段页面、MVP 验收与范围外功能。
```

- [ ] **步骤 5：提交 MVP 定义**

若已初始化 git，运行：

```powershell
git add docs/architecture/app-shell.md
git commit -m "docs: define desktop MVP"
```

预期：

```text
[main ...] docs: define desktop MVP
```

## 自检

规格覆盖：

- 双轨架构由任务 1–2 覆盖。
- 包边界由任务 3 覆盖。
- Runtime 通信协议由任务 4 覆盖。
- 桌面 MVP 范围由任务 5 覆盖。

占位扫描：

- 计划正文中不得出现 TODO 或 TBD 标记。

类型一致性：

- `task_id`、`action`、`project_context`、`messages`、`result_payload` 等命名在 Runtime 契约相关任务中保持一致。

## 说明

- 若工作区尚未初始化 git，则提交类步骤须先完成 `git init` 后再执行。
- 下一轮执行应先完成脚手架，再完成 Runtime 与桌面壳占位，然后再编写任何计量模型代码。
