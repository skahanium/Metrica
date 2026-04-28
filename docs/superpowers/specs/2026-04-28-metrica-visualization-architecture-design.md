# Metrica 可视化架构设计

> **状态：远期设计，非当前实施依据。** 本文档记录可视化系统的架构方向，供后续阶段实施时参考。当前 Alpha 主链路已完成结构化 `glance`/`tidy`/`warnings` 的结果渲染，可视化工作在 Core 基座加固完成后启动。

## 概述

Metrica 需要支持两类可视化需求：

1. **统计诊断图**：残差图、QQ 图、热力图、相关性矩阵等
2. **空间计量叠加**：地图底图 + 统计指标叠加（含交互式缩放/平移）

两类需求共享同一架构模式：Core 定义图的"是什么"（PlotSpec），两个独立通道各自渲染。

## 核心协议

### PlotSpec

```
PlotSpec {
  plot_type:      :residuals | :qq | :heatmap | :spatial_choropleth | ...
  data:           [系列数组或引用 augment 的列]
  axes:           { x_label, y_label, x_type, y_type }
  reference_lines: [{ value, label, style }]
  annotations:    [{ x, y, text, severity }]
  spatial_ref:    GeoJSON | nil
  title:          String
  caption:        String
}
```

### TableSpec

```
TableSpec {
  table_type:     :regression | :summary_stats | :correlation_matrix | ...
  headers:        [String]
  rows:           [[CellValue]]
  col_formats:    [{ align, precision, role }]
  annotations:    [{ row, col, text, severity }]
  caption:        String
}
```

**核心原则：Core 生产数据语义，不生产像素。**

## 双通道架构

```
                          ┌──────────────────────┐
                          │    MetricaBase.jl     │
                          │  PlotSpec / TableSpec │
                          └──────────┬───────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
     ┌────────▼────────┐    ┌───────▼───────┐    ┌────────▼────────┐
     │  MetricaPlot.jl  │    │ MetricaTables │    │  其他模型包      │
     │  生成 PlotSpec   │    │ 生成TableSpec │    │  (OLS, IV...)   │
     └────────┬────────┘    └───────┬───────┘    └────────┬────────┘
              │                     │                     │
              └──────────────────────┼─────────────────────┘
                                     │ JSON (Runtime 搬运)
                          ┌──────────▼───────────┐
                          │      Runtime          │
                          │  不解释图/表语义      │
                          └──────────┬───────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
     ┌────────▼────────┐    ┌───────▼───────┐    ┌────────▼────────┐
     │  交互通道 (App)   │    │ 离线通道 (Core) │    │  文件导出 (App)  │
     │  ECharts/Plotly  │    │ Makie.jl 渲染  │    │  用户触发调用    │
     │  实时缩放/hover   │    │ PDF/SVG/PNG   │    │  Runtime → Julia │
     └──────────────────┘    └───────────────┘    └─────────────────┘
```

- **交互通道**：App 消费 PlotSpec JSON，用 ECharts（统计图）/ Leaflet（地图）/ Three.js（3D，按需）渲染为交互式 Web 组件
- **离线通道**：App 触发导出时，Runtime 将 PlotSpec 回传 Julia，用 Makie.jl 渲染出版级 PDF/SVG/PNG
- **Runtime 职责不变**：不解释图/表语义，只搬运 PlotSpec/TableSpec JSON

## 技术选型

| 场景 | 推荐 | 备选 | 说明 |
|------|------|------|------|
| 统计图表 | ECharts | Plotly.js | SVG 渲染器可做高精度截图过渡；中文文档成熟 |
| 地图叠加 | Leaflet | MapLibre GL | ~40KB gzipped，GeoJSON 原生，与 spatial_ref 直接对接 |
| 3D 可视化 | Three.js | — | 按需引入，不做默认依赖 |
| 离线渲染 | Makie.jl (Cairo) | — | PDF/SVG/PNG 输出，LaTeX 公式，确定性和可复现 |
| 前端架构 | 保持 ES modules | — | 不引入 React/Vue；每个渲染组件是纯函数 |

### 跨平台兼容

```
macOS   →  WKWebView（WebKit）  → WebGL 2.0 完整支持
Windows →  WebView2（Chromium） → 三个平台中最强 GPU/WebGL 支持
```

ECharts、Leaflet、Three.js 在 macOS 和 Windows 上均已充分验证。Linux 平台暂不在当前范围。

## 新增包

- **`MetricaPlot.jl`**：从模型结果构造 `PlotSpec`，例如 `residual_plot(fit) → PlotSpec`、`qq_plot(fit) → PlotSpec`。依赖 `MetricaBase`
- **`MetricaTables.jl`**：构造 `TableSpec`，例如 `regression_table(fit) → TableSpec`。依赖 `MetricaBase`
- **`MetricaRender.jl`**（或在上述包内）：用 Makie.jl/PrettyTables.jl 消费 PlotSpec/TableSpec，产出出版级文件

## 实施顺序

| Phase | 内容 | 触发条件 |
|-------|------|---------|
| 0 | 当前状态：glance/tidy/warnings 结构化渲染完成 | ✅ |
| 1 | MetricaBase 新增 PlotSpec 类型；MetricaPlot.jl 新包；serialize.jl 新增 `plots` 字段；App 引入 ECharts 渲染残差图+QQ图 | Core 基座加固完成 |
| 2 | MetricaBase 新增 TableSpec 类型；MetricaTables.jl 新包；App 添加 PDF/LaTeX 导出按钮；Julia 端渲染 PDF/TeX | Phase 1 完成 |
| 3 | Julia 端 Makie.jl 实现 `render_pdf(plot::PlotSpec)` | Phase 2 完成 |
| 4 | `spatial_ref: GeoJSON` 启用；App 引入 Leaflet；MetricaPlot.jl 新增 `choropleth_plot()` | Phase 3 完成 |
| 5 | Three.js 3D 按需引入 | 有明确需求时 |

## 相关文档

- 总架构：`docs/superpowers/specs/2026-04-24-metrica-dual-track-design.md`
- 当前活跃设计：`docs/superpowers/specs/2026-04-25-metrica-alpha-real-ols-runtime-app-design.md`
- App 壳层：`docs/architecture/app-shell.md`
