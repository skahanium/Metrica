# Metrica 双轨产品设计

## 概述

Metrica 不应只被定义为一个 Julia 计量经济学包集合，而应被设计为一个双轨产品：

- `Metrica Core`：基于 Julia 的计量经济学协议内核与模型生态。
- `Metrica App`：以桌面工作台形式交付的跨平台原生软件。

两条轨道并行推进，但必须严格分层，避免界面层反向侵入内核层设计。

本设计的核心目标有三点：

1. 用统一、稳定、可扩展的协议承载未来模型、输出、可视化和教学能力。
2. 从第一阶段起为桌面软件预留结构化结果接口，而不是将终端文本输出硬塞进 GUI。
3. 让教学、研究、未来产品化三条需求在同一架构下兼容，而不是演化成互相牵制的分支。

## 产品形态

Metrica 的最终产品应由三层构成：

### 1. Metrica Core

由 `MetricaBase.jl`、`MetricaLinear.jl`、`MetricaOutput.jl`、`MetricaRobust.jl` 等包组成。

职责：

- 定义模型协议、结果语义、扩展挂点。
- 提供拟合、推断、预测、输出等计算能力。
- 以结构化对象输出结果，而不是只提供打印文本。

非职责：

- 桌面窗口、导航、工作区管理。
- 本地项目状态管理。
- GUI 专属布局逻辑。

### 2. Metrica Runtime

位于桌面应用与 Julia Core 之间，是 App 与 Core 的桥接层。

职责：

- 启动与管理 Julia 运行时。
- 锁定环境版本与依赖。
- 执行模型任务并管理取消、中断、错误。
- 将 Core 输出转为桌面端稳定消费的序列化协议。
- 管理日志、进程生命周期与调试信息。

建议技术：

- `Rust`
- 控制面协议使用 `JSON`
- 大型表格结果后续可引入 `Arrow`

### 3. Metrica App

跨平台原生桌面端，面向课堂、研究者和未来更完整的工作流。

职责：

- 数据导入与预览
- 模型配置与运行
- 结果展示与导出
- 教学解释与错误提示
- 项目保存、恢复与历史记录

建议技术：

- `Tauri`
- `Rust`
- `React + TypeScript`

## 架构原则

### Core 不感知 App

Core 只能定义能力，不能知道自己是否被命令行、Pluto、文档站或桌面软件调用。

### Runtime 是唯一桥

App 不能直接依赖 Julia 包内部结构。所有桌面端任务都通过 Runtime 进入 Core。

### 文本输出不是 GUI 接口

桌面软件必须消费 `glance`、`tidy`、`augment`、`warnings` 这类结构化结果，而不是解析 `summary()` 文本。

### 教学体验是架构目标

缺失值处理、样本量变化、变量编码、常见错误解释等信息应当是协议中的一等对象，而不是 UI 拼凑出来的说明文字。

## 建议仓库布局

```text
Metrica/
├── packages/
│   ├── MetricaBase.jl/
│   ├── MetricaLinear.jl/
│   ├── MetricaRobust.jl/
│   ├── MetricaOutput.jl/
│   ├── MetricaPanel.jl/
│   ├── MetricaTests.jl/
│   ├── MetricaViz.jl/
│   └── Metrica.jl/
├── apps/
│   └── metrica-desktop/
├── runtime/
│   └── metrica-runtime/
├── docs/
├── tutorials/
├── datasets/
├── benchmarks/
├── scripts/
└── .github/workflows/
```

说明：

- `packages/` 存放 Julia 包生态。
- `apps/metrica-desktop/` 存放桌面端工程。
- `runtime/metrica-runtime/` 存放桥接层实现。
- `docs/`、`tutorials/`、`datasets/` 维持教学与文档资产独立。

## 桌面端显示方式

Metrica 的显示层建议分为三种入口，共享同一套 Core 语义：

### 1. Package API

面向开发者和脚本工作流。

### 2. Notebook / Pluto

面向教学和可复现实验。

### 3. Native Desktop App

面向真正的软件产品体验。第一阶段重点在这个层次建立工作台式界面，而不是简单命令结果展示。

建议桌面工作台包含这些主要区域：

- 左侧导航：项目、数据、模型、结果、学习
- 中央主视图：数据表、模型配置器、结果页
- 右侧上下文面板：变量说明、警告解释、教学提示

## Runtime 通信设计

第一阶段建议采用“桌面端启动 Julia 子进程”的模式，不直接将 Julia 嵌入宿主进程。

理由：

- 实现难度更低
- 调试更直接
- 崩溃隔离更清晰
- 打包与升级策略更可控

Runtime 的动作命名、请求结构与响应 payload 示例由 `docs/architecture/runtime-protocol.md` 独立负责，本设计只定义其架构位置与职责边界。

## Core 对 App 公开的结构化结果

第一阶段至少稳定 4 类结果结构：

### `glance`

模型级摘要：

- 模型名称
- 样本量
- 自由度
- R² / 调整 R²
- 协方差类型
- AIC / BIC

### `tidy`

参数级长表：

- 参数名
- 估计值
- 标准误
- 统计量
- p 值
- 置信区间

### `augment`

观测级结果：

- 拟合值
- 残差
- 标准化残差
- 可能的杠杆值或影响度指标

### `warnings`

教学友好的解释对象：

- 机器可识别代码
- 短标题
- 说明文本
- 建议动作
- 严重程度

## 第一版 App 页面设计

第一版桌面软件不要做成“大而全统计平台”，只做一个完整跑通 OLS 工作流的教学型工作台。

建议主页面：

### 1. Home

- 最近项目
- 示例项目
- 快速导入数据
- 最近运行记录

### 2. Project

- 当前项目概览
- 数据源
- 已保存模型
- 导出记录

### 3. Data Inspector

- 字段列表
- 类型识别
- 缺失值统计
- 分类变量水平
- 样本数量与删除摘要

### 4. Model Builder

- 公式输入
- 模型类型选择
- 协方差类型选择
- 运行按钮
- 参数和选项面板

### 5. Results

- 模型摘要卡片
- 系数表
- 拟合和残差摘要
- 警告与解释
- 导出入口

### 6. Learn

- 常见问题解释
- 术语说明
- 教程入口
- 示例分析说明

具体 MVP 页面定义、验收标准和范围排除由 `docs/architecture/app-shell.md` 独立负责，本设计不重复展开。

## 并行建设策略

### Core 线

优先完成：

- `MetricaBase.jl`
- OLS 参考实现
- 最小 `glance / tidy / augment`
- 基础错误和警告对象

### App 线

优先完成：

- `Tauri` 桌面壳
- 主导航与工作台布局
- 数据检查页和结果页原型
- Runtime 请求响应协议接入
- 使用 mock 数据驱动 UI

### 汇合点

两条线通过以下内容汇合：

- Runtime 动作协议
- 结构化结果 schema
- 错误与警告对象语义

## 第一阶段范围

第一阶段目标不是构建 Stata 替代品，而是完成一个可演示、可继续扩张的软件骨架。

应完成：

- OLS 参考模型
- 结构化结果输出
- 桌面项目工作台骨架
- 本地数据导入与预览
- 结果展示与导出
- 基础教学提示

暂不完成：

- 面板模型桌面配置器
- 多模型复杂比较工作流
- 插件市场
- 云同步
- 高阶图形诊断全家桶
- 远程执行或浏览器部署

## 里程碑建议

### Milestone 1：Core + Schema Foundation

- 冻结 `Base` 层接口与结果语义
- 冻结 Runtime 协议草案
- 为 App 预留稳定消费格式

### Milestone 2：Desktop Skeleton

- 建立 Tauri 桌面工程
- 完成项目、数据、模型、结果四大骨架页面
- 用 mock 结果驱动 UI

### Milestone 3：First Real Run

- Runtime 调起 Julia
- 桌面端跑通真实 OLS
- 展示真实 `glance / tidy`
- 支持最小导出

### Milestone 4：Alpha Polishing

- 强化缺失值追踪
- 增补教学解释
- 增加最小教程和示例项目
- 完成可演示 alpha

## 结论

Metrica 应该从现在起被定义为：

> 一个以 Julia Core 为计量计算引擎、以 Runtime 为桥接层、以跨平台桌面工作台为产品形态的现代计量经济学生态。

这意味着项目建设不能只围绕“Julia 包还缺哪些模型”展开，而要同时围绕：

- 协议是否稳定
- 结果是否结构化
- Runtime 是否可靠
- App 是否能承载真实用户工作流

来设计。
