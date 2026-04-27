# 应用壳层（App Shell）

桌面壳层是基于 Tauri 的工作台，聚焦教学友好的计量工作流。

壳层必须消费结构化结果载荷，且不得解析终端摘要文本。

## MVP 页面

当前 alpha 的真实实现并不是完整多页工作台，而是一张最小真实结果页。

当前已真实实现：

- 文件选择按钮
- Runtime 端点输入
- CSV 路径输入
- 数据检查按钮
- 数据摘要区
- 数据预览表
- OLS 公式输入
- 运行按钮
- `glance` 结果区
- `tidy` 系数表
- warning / error 渲染区

当前仍为后续范围：

- 首页（Home）
- 项目（Project）
- 数据检查器（Data Inspector）完整流程
- 学习（Learn）
- 完整结果导出流程

## MVP 验收标准

当用户能够完成以下事项时，桌面 alpha 即视为成功：

1. 配置 Runtime 端点
2. 选择或输入本地数据集路径
3. 检查数据并查看结构化预览
4. 配置并运行一个 OLS 模型
5. 查看结构化结果
6. 收到可读的 warning 与错误说明

## MVP 范围之外

- 面板模型 UI
- 多模型对比仪表板
- 云同步
- 插件市场
- 完整诊断套件

## 相关文档

- 当前消费本壳层的主规格：`docs/superpowers/specs/2026-04-25-metrica-alpha-real-ols-runtime-app-design.md`
- Runtime 载荷由 `docs/architecture/runtime-protocol.md` 负责。
- 项目级分层由 `docs/superpowers/specs/2026-04-24-metrica-dual-track-design.md` 负责。
