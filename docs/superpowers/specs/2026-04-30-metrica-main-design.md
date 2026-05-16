# Metrica 主设计：S1–S4 稳定主链路与 S5 扩展基线

> **状态：当前主设计锚点。** 本文件记录 **`S1`–`S4` 已收口** 的产品与协议事实基线，并划定 **`S5` 高级研究专题** 的扩展边界。早期 foundation、dual-track、vertical slice 与远期 visualization 草案已回收，不再作为独立实施依据。
>
> **当前事实基线：** 真实 OLS/WLS/IV/GLS 与扩展协方差、扩展诊断已贯通；面板能力覆盖 FE/RE/FD/Between、HDFE、CRE、Panel IV、Driscoll-Kraay 等；**`S4` 离散、因果、时间序列、复杂抽样** 等模型族已纳入同一 `fit_model` 结构化结果协议；Runtime 为 axum HTTP + 持久化 Julia 守护进程（stdin/stdout JSON lines），并暴露数据查询、变换、项目与导出等动作；**桌面 App 主交互为 CLI-first 命令消息流**，结构化消费 `glance` / `tidy` / `diagnostics` / `warnings`，不解析终端摘要文本。教学向教程见 `tutorials/s4-*.md` 等。
>
> **`S3`（复现与报告）与产品化：** 项目保存/加载、运行记录、`export_report` 等在 Runtime 与桥接层已具备实现与测例；App 侧持续接入 CLI 动词与 UI。**不得**将「仅文档宣称」或样例 JSON 当作完成标准；未完成项在路线图与实施计划中如实标注为部分落地或待验范围。
>
> **`S5` 边界：** 在稳定协议上扩展 GMM、动态面板、系统方程、分位数等高级专题；新模型不得写入 `MetricaBase.jl` 的估计量实现，仅扩共享协议与类型约定；详见 [`S5-高级研究专题总施工规划.md`](../../../S5-高级研究专题总施工规划.md) 与 [`docs/roadmap/s5-advanced-research-topics.md`](../../roadmap/s5-advanced-research-topics.md)。不得重开平行 mock 主链路。

## 概述

本设计文档定义 Metrica 当前阶段最核心的产品与架构目标：

**以 “本地 CSV 导入 + 真实数据检查 + 数据操作 + 真实线性/面板拟合 + 结构化结果 + 桌面工作台渲染 + 教学友好警告” 作为当前稳定主链路。**

这不是一个演示级 mock 切片，也不是占位式联调；它是后续所有模型能力、输出能力、桌面能力与教学能力的基石。

本文档将当前真实实现路线固定为：

- 真实线性模型族与面板模型族
- `StatsModels.jl` 风格公式语义
- 混合依赖策略：CSV/表/公式使用成熟生态，Metrica 自主掌握 OLS 结果语义
- `Runtime -> Julia` 通过子进程 CLI 执行真实桥接

## 目标

当前阶段的目标是在已成立的 **`S1`–`S4` 主链路** 上继续加固协议与数值语义，同步推进 **`S3` 级复现/报告能力** 的桌面闭环与 **`S5` 高级专题** 的分期交付，并保持以下前提成立：

1. `MetricaBase.jl` 的结构化协议足以作为 Core、Runtime、App 三层的稳定共享边界。
2. `MetricaLinear.jl` 可以在不依赖 GUI、也不暴露第三方回归对象的前提下，提供真实 OLS 能力。
3. `runtime/metrica-runtime` 可以通过 Julia 子进程稳定执行 `inspect_dataset`、`query_dataset`、`fit_model`、`transform` 等动作，以及项目/导出类 HTTP 动作（见 `docs/architecture/runtime-protocol.md`），并传递结构化成功/失败载荷。
4. `apps/metrica-desktop` 可以只消费结构化数据检查结果与模型结果对象，而不回退到解析终端文本。
5. 教学友好行为在当前工作台中仍是协议级能力，而不是 UI 补丁。

当前阶段性落点：

- 已完成的最小可用边界：`fit_ols_file`、统一 `fit` 入口、`glance`、`tidy`、`augment`、结构化 warning / error、结构化 payload、Runtime 真实调用 Julia、桌面端结构化渲染与数据操作主链路
- 已完成的扩展能力：Runtime/App 贯通 WLS、HC1、IV/2SLS、GLS 与基础诊断选项，数值可信度测试已补强，扩展诊断（White、DW、BG、RESET、JB）已在 Core 层实现；面板能力已贯通 FE/RE/FD/Between、HDFE、CRE、Panel IV、Driscoll-Kraay 与升级诊断；**`S4` 离散、因果、时间序列、复杂抽样** 模型族已纳入统一协议；React 工作台、**CLI-first 消息流** 与 `/transform` 数据工作流已实现并收口
- 明确排除的短期捷径：前端直接调用本地 Julia 脚本、前端消费示例 JSON、Runtime 返回样例载荷冒充真实链路
- **`S5` 高级研究专题：** 在协议稳定前提下分期落地（见总规）；每专题须自带最小教学数据、CLI 路径、Runtime 垂直切片与结构化 warning 清单
- **延后：** 多模型对比产品化、完整图表导出产品、任意脚本执行、AI 增强层等；不阻塞当前主链路与 `S5` 分期验收

## 非目标

本设计明确不包含以下内容：

- 多模型对比工作流的完整产品化
- 完整 `augment` 大表渲染
- 完整诊断图系统
- 用户任意脚本执行
- 通用命令行式自由文本执行入口
- 常驻 Julia worker 或分布式执行
- 云同步、插件市场或多用户能力

## 总体架构

### Core

`packages/` 负责真实计量能力与结构化结果语义。

- `MetricaBase.jl` 只定义共享协议、结果类型、警告/错误类型与公共接口，不承载 OLS 数值实现。
- `MetricaLinear.jl` 提供真实 OLS/WLS/IV/GLS 与协方差选项（包括 Cluster 协方差），并将结果封装为 Metrica 自有结构化对象。
- `MetricaDiagnostics.jl` 提供扩展诊断能力（VIF、Breusch-Pagan、White、Durbin-Watson、Breusch-Godfrey、RESET、Jarque-Bera）。
- `MetricaPanel.jl` 提供基础与研究口径面板能力，包括 FE/RE/FD/Between、HDFE、CRE、Panel IV 与相关诊断。
- Core 不向 Runtime 或 App 暴露第三方包内部结果对象。

### Runtime

`runtime/metrica-runtime` 是桌面端与 Julia Core 之间的唯一桥。

- 接收 `inspect_dataset`、`query_dataset`、`fit_model`、`transform` 等请求（及 `run_diagnostic`、项目/导出端点，见 `runtime-protocol`）
- 做轻量输入校验与路径整理
- 通过 axum HTTP 框架暴露端点
- 管理持久化 Julia 进程的生命周期
- 返回结构化成功或失败响应

Runtime 不得重做计量逻辑，不得解释系数或重新计算统计量。

当前实现约束：

- Runtime 继续作为前端触发真实模型任务与数据任务的唯一执行入口
- Runtime 可以转发结构化结果，但不得复制 Julia 侧的计量语义或统计计算
- 不得把样例响应测试通过误报为“真实主链路已打通”

### App

`apps/metrica-desktop` 负责真实且可扩展的桌面工作台主链路。

- 选择本地 CSV 与项目上下文
- 通过 **CLI 命令消息流** 触发数据检查、数据查询（`query_dataset`）、数据变换与拟合
- 执行基础数据操作（`transform` 等）
- 输入线性、面板或 **`S4` 已注册 `model_type`** 的模型配置
- 渲染结构化列摘要与预览表
- 渲染结构化 `glance`、`tidy`、`diagnostics`、`warnings` 与错误

App 不解析 `summary()` 文本，也不依赖终端打印格式。

当前实现约束：

- App 必须继续通过 Runtime 发起真实 `fit_model` / `transform` / `query_dataset` 及项目、导出相关动作（以 `runtime-protocol` 为准）
- App 必须继续渲染结构化 `glance`、`tidy`、warnings、diagnostics 与数据操作结果
- 不得把壳层页面或占位 banner 视为“基本可用前端”

## Julia 端设计

### 依赖策略

本阶段采用混合策略：

- `CSV.jl` 负责 CSV 读取
- `DataFrames.jl` 负责表结构与列访问
- `StatsModels.jl` 负责公式语义与设计矩阵构造
- Metrica 自身负责 OLS 求解、结果对象封装、警告与错误语义

选择该策略的原因是：

- 不重复造 CSV/表/公式生态的轮子
- 保持公式接口与 Julia 主流生态一致
- 将最关键的协议语义与教学行为保留在 Metrica 内部

### 数值底座与自定义计算边界

Core 内部的线性代数与概率计算应优先使用 Julia 生态的通用抽象，例如 `AbstractMatrix`、`AbstractVector`、`LinearAlgebra`、`Statistics` 与 `Distributions.jl`。除非序列化边界、数值稳定性或性能控制明确要求，不应把内部实现过早固定为单一矩阵类型或单一分解路径。

这类灵活性只属于 Core 内部计算层。Runtime 与 App 不暴露任意矩阵对象、任意 Julia 代码或自由文本命令；所有可被用户、文档、导出或桌面端消费的结果仍必须回到结构化 `glance`、`tidy`、`augment`、`warnings`、`diagnostics` 与 `artifacts` 等协议对象。

远期自定义计算应通过受控公式、结构化选项、白名单动作或已注册分析模板进入系统，而不是通过通用脚本执行入口进入系统。

### 公开公式语义

公开接口按 `StatsModels.jl` 风格设计。

当前稳定支持：

- 常见线性项相加
- 默认带截距
- `-1` 或 `0` 去截距

当前不承诺完整支持但接口上预留扩展兼容性：

- 分类变量展开
- 交互项
- 函数变换

实现上允许底层已具备更广语义，但验收标准只以当前承诺范围为准。

### OLS 内部流程

`MetricaLinear.jl` 的模型入口应保持为一条职责清晰的真实流水线：

1. 读取请求中的数据路径与拟合选项
2. 加载 CSV 为表结构
3. 依据公式提取模型相关列
4. 按缺失值策略筛除样本并生成删样信息
5. 构建响应变量向量与设计矩阵
6. 执行 OLS 求解
7. 计算摘要统计量与参数级统计量
8. 封装为 `glance`、`tidy`、warnings 或 `ModelError`

这条流水线中每个步骤应为小而单一职责的函数，便于后续扩展 `augment`、稳健协方差与其他模型。

### OLS 数值与结果语义

本阶段要求真实 OLS，而非 mock 系数或占位统计量。

最小成功结果必须稳定产出：

- `glance`
  - `model`
  - `nobs`
  - `dof`
  - `metrics`
- `metrics` 至少包含：
  - `r2`
  - `adj_r2`
  - `sigma`
  - `rss`
  - `tss`
- `tidy`
  - `name`
  - `estimate`
  - `stderror`
  - `statistic`
  - `pvalue`
- `warnings`
  - 用于教学友好展示的结构化警告对象

`augment` 能力已实现，通过 `options.return_augment = true` 可请求逐观测增强数据，包含拟合值、残差、标准化残差、杠杆值与 Cook's D。默认预览前 100 行。

### 缺失值处理

缺失值处理是协议级能力，而不是 UI 提示细节。

默认策略：

- 对模型实际使用到的列执行逐行筛除
- 记录原始样本量、保留样本量、删除样本量
- 尽可能记录触发删样的变量集合

若发生删样，必须返回结构化 warning，而不是静默改变样本量。

### 错误与警告语义

阻断性问题使用 `ModelError`：

- 文件不存在
- CSV 解析失败
- 公式引用列不存在
- 有效样本为空
- 设计矩阵奇异
- 自由度不足

非阻断但需提示的问题使用 `ModelWarning`：

- 因缺失值删样
- 数值条件较差的风险提示
- 其他不会阻止结果产出的教学友好说明

错误与警告都必须带有适合桌面端直接展示的短标题、详细说明与可选建议。

## Runtime 设计

### 执行方式

Runtime 通过 axum HTTP 框架 + 持久化 Julia 进程执行真实模型任务。

选择该方式的原因：

- 与现有架构文档一致
- 调试最直接
- 崩溃隔离清晰
- 当前基线更容易验证成功/失败路径
- 持久化进程减少冷启动时间
- 支持会话状态与数据集缓存

### 请求与响应

`inspect_dataset` 与 `fit_model` 仍沿用既有结构化协议方向：

- `inspect_dataset`
  - `dataset_ref.path` 指向本地 CSV
  - `options.preview_rows` 可请求数据检查返回更多预览行；桌面端全量数据视图用该字段加载完整小型数据集
  - 返回 `dataset_summary`、`columns`、`preview_rows` 与可选 `warnings`

- `dataset_ref.path` 指向本地 CSV
- `model_spec.model_type = "ols"`
- `model_spec.formula` 为 `StatsModels` 风格字符串
- `options.drop_missing` 默认开启

Runtime 的职责只包括：

- 输入字段的最小完整性校验
- 调用参数规范化
- 通过 axum HTTP 框架暴露端点
- 管理持久化 Julia 进程的生命周期
- 捕获 stdout/stderr、退出码与超时
- 将 Julia 返回的 JSON 响应转发为稳定桌面协议

本阶段的最小真实前端链路要求 Runtime 额外满足：

- 有一个能被桌面端稳定调用的 `fit_model` 执行入口
- 有一个能被桌面端稳定调用的 `inspect_dataset` 执行入口
- 对成功与失败都返回统一结构化响应
- 支持持久化 Julia 进程的会话管理

## 面向后期高级能力的当前铺垫

尽管“用户自定义能力”被放在较后阶段，本阶段仍应避免把未来路线堵死。

当前需要保留的铺垫包括：

1. `action`、`project_context`、`dataset_ref`、`model_spec`、`options` 继续作为稳定信封，而不是被 OLS 特例化为临时字段集合。
2. `model_spec.formula` 与结构化 `options` 继续被视为受控输入，而不是通用脚本入口。
3. Runtime 的分发逻辑应保持“按动作名进入固定执行路径”，便于后续引入受控新动作或模板动作。
4. App 只展示 schema 驱动的输入与结果，不假定未来能力一定来自单一 OLS 页面。

后续高级能力只认可两层：

- 第一层：受控自定义公式与选项
- 第二层：受控自定义动作 / 自定义分析模板

当前阶段明确不为以下能力背书：

- 任意 Julia 代码执行
- 任意 shell 命令执行
- 以自由文本命令作为公开产品接口

## App 结果与交互（当前事实）

**主路径：** CLI-first 命令输入 → 解析为结构化 `ModelSpec` / 任务请求 → 经 Runtime HTTP 执行 → 消息流中展示结构化结果。与「单页表单 + 单一运行按钮」的早期 Alpha 描述相比，**以命令流为教学与复现主入口**；表单式辅助输入若存在，为次要或兼容路径，不得被文档表述为唯一主路径。

当前须稳定具备：

- 数据与 Runtime 连接状态反馈
- 命令输入、历史与结果消息流
- 结构化 `glance`、`tidy`、`diagnostics`（按模型族）、`warnings`、错误展示
- 与 `query_dataset` / `transform` / 项目动词等对齐的客户端封装（细节见 `docs/architecture/app-shell.md`）

**产品化愿景（非当前验收门槛）：** 经典多面板 IDE、完整侧边栏变量浏览器、统一出版导出管线等可作为后续阶段（如 `S6`）目标；**当前** 壳层为 **tao + wry** 内嵌 WebView + CLI-first 消息流，不得与上述愿景混写为「已实现主链路」。

明确不包含（与本主设计非目标一致）：

- 多模型对比的完整产品化
- 任意用户 Julia/shell 脚本入口
- 任何依赖 mock 载荷冒充真实链路的「完成」宣称

## 数据检查最小协议

`inspect_dataset` 的最小成功结果应至少包含：

- `dataset_summary`
  - `row_count`
  - `column_count`
- `columns`
  - `name`
  - `inferred_type`
  - `missing_count`
- `preview_rows`
  - 仅返回前几行原始值的结构化对象数组
- `warnings`
  - 如存在空列、全缺失列或其他教学友好提示

### 失败分层

Runtime 至少要区分三类失败：

1. 请求级失败
   - 字段缺失
   - 路径无效
   - 模型类型不支持
2. 执行级失败
   - Julia 进程无法启动
   - 非零退出
   - 超时
   - 输出不是合法 JSON
3. 模型级失败
   - 公式错误
   - 空样本
   - 奇异矩阵
   - 其他由 Julia 明确返回的结构化失败

其中模型级失败应尽可能原样保留 Julia 端的标题、说明与建议，不得被 Runtime 吞掉细节。

## App 设计

### 当前主用户流（CLI-first）

1. 用户配置工作目录与数据集（及项目文件，若使用）
2. 用户在 CLI 输入区键入命令（如 `reg`、`xtreg`、`logit`、`did` 等，以 `commandGrammar` 为准）
3. 应用解析命令并调用 Runtime 对应动作（`fit_model`、`inspect_dataset`、`transform`、`export_report` 等）
4. 消息流展示运行中状态与结构化结果载荷
5. 成功时渲染模型族对应的摘要、系数表与诊断组件
6. 若有 warnings，在结构化列表中展示教学说明
7. 失败时展示结构化错误码与建议

兼容路径：部分模型仍可通过表单字段辅助构造命令，但**文档与验收以 CLI 消息流为准**。

### 渲染原则

App 只消费 Runtime 返回的结构化 JSON。

- 不解析终端文本
- 不自行推断删样原因
- 不自行拼装统计含义

任何与模型结果相关的展示语义，都应来源于 Core/Runtime 返回的结构化载荷。

## 测试与验收

### Julia 包测试

至少覆盖以下场景：

- 正常 CSV + 正常公式 + 成功 OLS
- 缺失值删样并生成 warning
- 公式引用不存在列
- 有效样本为空
- 设计矩阵奇异
- 截距默认存在与显式去截距
- WLS 权重拟合
- HC1/Cluster 协方差选项
- 扩展诊断（VIF、Breusch-Pagan、White、DW、BG、RESET、JB）

### Runtime 测试

至少覆盖以下场景：

- `fit_model` 请求成功序列化
- Julia 进程成功返回结构化 `glance` 与 `tidy`
- Julia 进程返回结构化模型错误
- Julia 进程启动失败或输出非法 JSON 时生成稳定执行级错误

### App 验证

至少验证以下用户流：

- 选择 demo CSV
- 输入一个有效 OLS 公式并运行
- 结果页出现关键摘要指标与系数表
- 诊断区可显示 VIF 与 Breusch-Pagan 结果
- 警告区可显示删样提示
- 错误区可显示公式错误或拟合错误

### 基线验收标准

以下条件构成当前基线，后续扩展不得破坏：

1. 桌面端可选择本地 CSV 并发起真实 `fit_model`
2. Runtime 实际调用 Julia 持久化进程，而不是 mock
3. Julia 真实完成 OLS 拟合并返回结构化 `glance` 与 `tidy`
4. 缺失值删样可端到端显示为教学友好 warning
5. 至少两类失败可端到端展示为可读错误
6. 整条链路可通过一个稳定 demo 数据集重复验证

## 已完成专题设计结论索引（S3–S4 收口）

以下结论原载于独立 `spec` / `plan`，已在 `S5.0` 并回本文件或 `docs/architecture/`，原文件删除以免多套主叙事：

- **交互纯度 / CLI-first：** 桌面端以命令消息流为研究与教学主路径；Runtime 为唯一执行桥；禁止 App 解析 `summary()` 文本冒充结果语义。
- **`S4` 模型族：** 离散（`logit` 等）、因果（`did`、`ipw` 等）、时间序列（`arima`、`unitroot` 等）、复杂抽样（`survey_*`）等与线性/面板族统一走 `fit_model` 与结构化输出；`model_type` 枚举以 `julia_bridge_entry.jl` 与 `MetricaBase.MODEL_REGISTRY` 为准。
- **图标与品牌资产：** 应用图标与仓库 `assets/icons/` 交付路径已稳定；具体像素规范不再单独占活跃 spec。
- **计量算法审查（第一批）：** 数值与算法侧修复以 Julia 包测试与变更记录为准；新审查轮次若开启应另建 dated 计划，不恢复旧 plan 为活跃依据。

## 文档变更记录（节选）

- **S5.0：** 更新标题与基线至 `S1`–`S4` + CLI-first；增加 `S5` 边界与已完成 spec 结论索引；回收独立 `superpowers` 计划中仍有效的叙述。

## 结论

当前 Metrica 最重要的任务不是继续堆叠模块名或页面名，而是在 **`S1`–`S4` 已验证主链路** 上继续加固协议与数值语义，并按 [`S5` 总规](../../../S5-高级研究专题总施工规划.md) 分期扩展高级专题。

后续所有能力扩展，都应建立在这条链路之上推进，而不是绕开它继续增加未验证的子系统。

这条链路已经把项目从“架构合理、方向清晰”推进到“架构成立、系统可验证”的阶段。
