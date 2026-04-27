# Metrica Alpha 真实 OLS 全链路设计

> **状态补充：** 本设计仍是当前 Alpha 主链路的主规格。当前仓库已先完成 Julia 端最小可用 OLS；接下来的直接目标是把这条链路继续收口为“最小真实全链路前端”，即 `App -> Runtime -> Julia -> 结构化结果 -> App` 必须真实打通，不允许以 mock 响应或前端直调脚本替代。

## 概述

本设计文档定义 Metrica 当前阶段最核心的实施目标：

**将 “本地 CSV 导入 + 真实数据检查 + 真实 OLS 拟合 + 结构化结果 + 桌面渲染 + 教学友好警告” 这条 Alpha 主链路真正跑通。**

这不是一个演示级 mock 切片，也不是占位式联调；它是后续所有模型能力、输出能力、桌面能力与教学能力的基石。

本文档在既有双轨架构与 Alpha 垂直切片文档基础上，进一步将本阶段的真实实现路线固定为：

- 真实 `OLS`
- `StatsModels.jl` 风格公式语义
- 混合依赖策略：CSV/表/公式使用成熟生态，Metrica 自主掌握 OLS 结果语义
- `Runtime -> Julia` 通过子进程 CLI 执行真实桥接

## 目标

本阶段的目标不是扩大模型覆盖面，而是用最高标准完成第一条可长期演进的真实主链路，并验证以下前提：

1. `MetricaBase.jl` 的结构化协议足以作为 Core、Runtime、App 三层的稳定共享边界。
2. `MetricaLinear.jl` 可以在不依赖 GUI、也不暴露第三方回归对象的前提下，提供真实 OLS 能力。
3. `runtime/metrica-runtime` 可以通过 Julia 子进程稳定执行 `inspect_dataset` 与 `fit_model` 两类任务，并传递结构化成功/失败载荷。
4. `apps/metrica-desktop` 可以只消费结构化数据检查结果与模型结果对象，而不回退到解析终端文本。
5. 教学友好行为在第一条链路中是协议级能力，而不是 UI 补丁。

当前阶段性落点补充：

- 已完成的最小可用边界：`fit_ols_file`、`glance`、`tidy`、结构化 warning / error、结构化 payload
- 当前正在推进的边界：Runtime 真实调用 Julia、桌面端真实发请求与渲染、数据检查最小链路
- 明确排除的短期捷径：前端直接调用本地 Julia 脚本、前端消费示例 JSON、Runtime 返回样例载荷冒充真实链路

## 非目标

本设计明确不包含以下内容：

- 面板模型、IV、GLS、WLS
- 多模型对比工作流
- 完整 `augment` 大表渲染
- 诊断图系统
- 常驻 Julia worker 或分布式执行
- 云同步、插件市场或多用户能力

## 总体架构

### Core

`packages/` 负责真实计量能力与结构化结果语义。

- `MetricaBase.jl` 只定义共享协议、结果类型、警告/错误类型与公共接口，不承载 OLS 数值实现。
- `MetricaLinear.jl` 提供 Alpha 所需的真实 OLS 实现，并将结果封装为 Metrica 自有结构化对象。
- Core 不向 Runtime 或 App 暴露第三方包内部结果对象。

### Runtime

`runtime/metrica-runtime` 是桌面端与 Julia Core 之间的唯一桥。

- 接收 `inspect_dataset` 请求
- 接收 `fit_model` 请求
- 做轻量输入校验与路径整理
- 通过 Julia CLI 子进程执行真实拟合
- 返回结构化成功或失败响应

Runtime 不得重做计量逻辑，不得解释系数或重新计算统计量。

当前实现要求补充：

- Runtime 必须成为前端触发 OLS 的唯一执行入口
- Runtime 可以转发结构化结果，但不得复制 Julia 侧的 OLS 语义或统计计算
- 在真实子进程桥接完成前，不得把样例响应测试通过误报为“真实 OLS 全链路已打通”

### App

`apps/metrica-desktop` 负责最小但真实的桌面工作流。

- 选择本地 CSV
- 触发数据检查
- 输入 OLS 公式
- 触发运行
- 渲染结构化列摘要与预览表
- 渲染结构化 `glance`、`tidy`、warnings 与错误

App 不解析 `summary()` 文本，也不依赖终端打印格式。

当前实现要求补充：

- App 必须通过 Runtime 发起真实 `fit_model`
- App 必须渲染结构化 `glance`、`tidy`、warnings 与错误
- 在真实调用 Runtime 前，不得把壳层页面或占位 banner 视为“基本可用前端”

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

### 公开公式语义

公开接口按 `StatsModels.jl` 风格设计。

Alpha 阶段承诺稳定支持：

- 常见线性项相加
- 默认带截距
- `-1` 或 `0` 去截距

Alpha 阶段不承诺完整支持但接口上预留扩展兼容性：

- 分类变量展开
- 交互项
- 函数变换

实现上允许底层已具备更广语义，但验收标准只以 Alpha 承诺范围为准。

### OLS 内部流程

`MetricaLinear.jl` 的 Alpha 入口应拆为一条职责清晰的真实流水线：

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

Alpha 阶段允许 `augment` 暂不对外完整公开，但内部实现应预留拟合值与残差计算位置，避免后续返工。

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

Runtime 通过一次一调用的 Julia CLI 子进程执行真实模型任务。

选择该方式的原因：

- 与现有架构文档一致
- 调试最直接
- 崩溃隔离清晰
- Alpha 更容易验证成功/失败路径

### 请求与响应

`inspect_dataset` 与 `fit_model` 仍沿用既有结构化协议方向：

- `inspect_dataset`
  - `dataset_ref.path` 指向本地 CSV
  - 返回 `dataset_summary`、`columns`、`preview_rows` 与可选 `warnings`

- `dataset_ref.path` 指向本地 CSV
- `model_spec.model_type = "ols"`
- `model_spec.formula` 为 `StatsModels` 风格字符串
- `options.drop_missing` 默认开启

Runtime 的职责只包括：

- 输入字段的最小完整性校验
- 调用参数规范化
- 启动 Julia 子进程
- 捕获 stdout/stderr、退出码与超时
- 将 Julia 返回的 JSON 响应转发为稳定桌面协议

本阶段的最小真实前端链路要求 Runtime 额外满足：

- 有一个能被桌面端稳定调用的 `fit_model` 执行入口
- 有一个能被桌面端稳定调用的 `inspect_dataset` 执行入口
- 对成功与失败都返回统一结构化响应
- 不要求在本阶段引入常驻 worker、任务队列或复杂调度

## App 最小结果页

前端当前阶段不追求完整工作台，而追求一条可长期保留的最小真实结果页。

必须包含：

- 文件选择按钮
- CSV 路径输入
- 数据检查按钮
- 数据摘要区
- 数据预览表
- 公式输入
- 运行按钮
- 运行中状态
- `glance` 摘要区
- `tidy` 系数表
- warnings 区
- error 区

明确不包含：

- 多模型切换
- 项目系统全量流程
- 复杂导航与多标签工作区
- 任何依赖 mock 结果的占位运行体验

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

### Alpha 最小真实用户流

桌面端只实现最窄但真实的一条流程：

1. 用户选择本地 CSV
2. 用户输入 OLS 公式
3. 用户点击运行
4. 页面显示运行中状态
5. 成功时展示 `glance` 摘要卡片与 `tidy` 系数表
6. 若有 warnings，单独展示教学友好提示区
7. 失败时展示结构化错误说明与建议

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

### Runtime 测试

至少覆盖以下场景：

- `fit_model` 请求成功序列化
- Julia 子进程成功返回结构化 `glance` 与 `tidy`
- Julia 子进程返回结构化模型错误
- Julia 进程启动失败或输出非法 JSON 时生成稳定执行级错误

### App 验证

至少验证以下用户流：

- 选择 demo CSV
- 输入一个有效 OLS 公式并运行
- 结果页出现关键摘要指标与系数表
- 警告区可显示删样提示
- 错误区可显示公式错误或拟合错误

### Alpha 验收标准

当且仅当以下条件同时成立时，本阶段目标视为完成：

1. 桌面端可选择本地 CSV 并发起真实 `fit_model`
2. Runtime 实际调用 Julia 子进程，而不是 mock
3. Julia 真实完成 OLS 拟合并返回结构化 `glance` 与 `tidy`
4. 缺失值删样可端到端显示为教学友好 warning
5. 至少两类失败可端到端展示为可读错误
6. 整条链路可通过一个稳定 demo 数据集重复验证

## 结论

当前 Metrica 最重要的任务不是继续堆叠模块名或页面名，而是以高标准完成第一条真实可运行的主链路。

只有这条链路跑通，项目才真正从“架构合理、方向清晰”进入“架构成立、系统可验证”的阶段。

后续所有能力扩展，都应建立在这条链路之上推进，而不是绕开它继续增加未验证的子系统。
