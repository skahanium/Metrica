# 应用壳层（App Shell）

桌面壳层是基于 Tauri 的工作台，聚焦教学友好的计量工作流。

壳层必须消费结构化结果载荷，且不得解析终端摘要文本。

## MVP 页面

各页面在 alpha 阶段的实现状态：

- 首页（Home）— alpha 占位
- 项目（Project）— alpha 占位
- 数据检查器（Data Inspector）— alpha 真实实现（文件选择 + 列预览）
- 模型构建器（Model Builder）— alpha 真实实现（公式输入 + 模型选择 + 运行按钮）
- 结果（Results）— alpha 真实实现（glance/tidy/warnings 结构化渲染）
- 学习（Learn）— alpha 占位

## MVP 验收标准

当用户能够完成以下事项时，桌面 alpha 即视为成功：

1. 打开项目
2. 导入数据集
3. 配置并运行一个 OLS 模型
4. 查看结构化结果
5. 导出结果摘要
6. 收到可读的警告与错误说明

## MVP 范围之外

- 面板模型 UI
- 多模型对比仪表板
- 云同步
- 插件市场
- 完整诊断套件

## 相关文档

- 当前消费本壳层的切片：`docs/superpowers/specs/2026-04-24-metrica-alpha-vertical-slice-design.md`
- Runtime 载荷由 `docs/architecture/runtime-protocol.md` 负责。
- 项目级分层由 `docs/superpowers/specs/2026-04-24-metrica-dual-track-design.md` 负责。
