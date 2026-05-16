# 应用壳层（App Shell）

本文描述 **当前仓库已实现** 的桌面前端与原生宿主关系；叙述以 `apps/metrica-desktop/` 下源码为准。计量协议与 HTTP 载荷见 [`runtime-protocol.md`](./runtime-protocol.md)。

## 1. 产品事实：CLI-first 与结构化结果

- **主路径：** 用户在底部 **`CommandLine`** 输入 Stata 风格命令；`commandParser` / `commandGrammar` 解析后，由 `commandExecutor` 组装请求并调用 **`runtimeClient`**（对 **metrica-runtime** 的 HTTP，默认 `http://127.0.0.1:47821`），在 **`ResultFlow`** 消息列表中追加结构化结果。
- **消息类型：** `ResultBlock`（模型 `glance` / `tidy` / 族专属卡片与表）、`DataResultBlock`、`TransformResultBlock`、纯命令提示等（见 `messageStore` 与 `ResultFlow.tsx`）。
- **硬约束：** 只消费 Runtime 返回的 **JSON 结构化载荷**；不把终端文本或 `summary()` 当作结果真相来源。

## 2. 宿主与原生能力（非 Tauri）

当前桌面可执行文件由 **`src-tauri/`** 构建，技术栈为 **`tao`（窗口）+ `wry`（WebView）** + 内嵌前端静态资源，**不是** Tauri 2，也 **没有** `@tauri-apps/*` 的 `invoke` IPC。

| 职责 | 实现要点 |
|------|----------|
| 窗口与 WebView | `tao::window::WindowBuilder` + `wry::WebViewBuilder`，加载自定义协议 `metrica://localhost/...` |
| 启动 Runtime | `lib.rs` 中 `spawn_runtime()`：在子进程中执行 `metrica-runtime serve`（可通过 `METRICA_RUNTIME_BIN` 覆盖二进制路径） |
| 单实例 | Unix 域套接字 `/tmp/metrica-desktop.lock`，第二实例激活已有窗口后退出 |
| macOS 集成 | `NSOpenPanel` / `NSSavePanel` 选 CSV、项目路径、导出保存路径；`NSApplication` 图标与 **Edit** 菜单（剪切/复制/粘贴等走 responder chain） |

### 2.1 前端如何调「原生」能力

前端通过 **`fetch('metrica://localhost/...')`** 命中 WebView 自定义协议，由 Rust 侧返回 JSON（见 `src-react/services/nativeHost.ts`）：

| 路径 | 用途 |
|------|------|
| `/__native__/pick_csv` | 选择 CSV 文件 |
| `/__native__/pick_project_open` | 打开项目（目录或 `project.json`） |
| `/__native__/pick_project_save` | 保存项目目标路径 |
| `/__native__/pick_export_save?filename=...` | 导出文件保存路径 |

非 macOS 上部分能力返回 **501** 或错误 JSON，与实现一致。

### 2.2 与 Runtime 的通信

业务请求一律为浏览器 **`fetch` → `http://127.0.0.1:47821/...`**（见 `runtimeClient.ts`），与 WebView 协议分离。`healthPolling.ts` 轮询 **`GET /health`** 以反映 Julia 会话状态。

## 3. 主界面布局（当前实现）

单页纵向布局（`App.tsx`）：

1. **顶栏：** 品牌区 + 主题切换（`localStorage` + `data-theme`）。
2. **中部：** 可选 **全局错误 / Julia 连接中 / 不健康** 的 `Alert`；主体为 **`ResultFlow`**（全屏数据模式时为 **`DataFullscreen`**）。
3. **底部：** **`CommandLine`**（补全、执行、CLI 反馈条）。

**叠加层（portal / 状态驱动）：** **`TrashPanel`**、**`DataHistoryPanel`**，由 `appStore` 等控制显隐。

**`ResultFlow` 内部：** 顶部 **`MessageToolbar`**（多选、删除、回收站）；下方滚动区渲染按时间排序的消息卡片。

无「左侧变量树 + 中央模型表单 + 顶栏运行模型」三栏 IDE 布局；若路线图需要多面板工作台，应记在 **`S6` 产品化** 或单独 UI spec，**不得**写进本文当作已实现事实。

## 4. 技术栈（前端依赖）

| 层 | 选型 | 说明 |
|----|------|------|
| 宿主 | `tao` + `wry` | 见 `src-tauri/Cargo.toml` |
| UI | React 19 + TypeScript 5 | 入口 `src-react/main.tsx` |
| 构建 | Vite 6 | `npm run dev` / `npm run build` |
| 状态 | Zustand | `stores/*` |
| 组件库 | Ant Design 5 | |
| 表格 | AG Grid Community | `TidyTable`、`DataPreviewTable`、`DataFullscreen` 等 |
| 图表 | ECharts（`echarts-for-react`） | 如 `EventStudyPlot` |
| 路由 | 无 `react-router` | 单页应用，无多路由表 |

## 5. 组件与模块（与目录对应）

```
src-react/
├── main.tsx
├── components/
│   ├── App.tsx              # 顶栏 + ResultFlow/DataFullscreen + CommandLine
│   ├── CommandLine.tsx
│   ├── ResultFlow.tsx
│   ├── MessageToolbar.tsx
│   ├── ResultBlock.tsx      # 按 model_type 分支渲染 glance/tidy/族组件
│   ├── DataResultBlock.tsx
│   ├── TransformResultBlock.tsx
│   ├── DataFullscreen.tsx
│   ├── TrashPanel.tsx
│   ├── DataHistoryPanel.tsx
│   └── …                    # GlanceTable、TidyTable、EventStudyPlot 等
├── services/
│   ├── runtimeClient.ts     # → http://127.0.0.1:47821
│   ├── nativeHost.ts        # → metrica://localhost/__native__/...
│   ├── commandParser.ts
│   ├── commandGrammar.ts
│   ├── commandExecutor.ts
│   └── healthPolling.ts
└── stores/
```

## 6. 数据网格与图表（实现级）

- **AG Grid：** 用于宽表展示（系数表、预览、全屏数据）；能力以各组件实现为准（排序、选区等）。
- **ECharts：** 当前典型用途为事件研究等；**图表导出**为前端 `getDataURL`（SVG/PNG data URL），见 `chartExport.ts`，**不**经过 Makie 或 Tauri IPC 链（旧文档中的该路径已删除）。

## 7. 教学与警告

结构化 `warnings` 在各结果块中展示；具体文案与字段由 Core/Runtime 决定，App 侧只做呈现与复制命令等轻交互。

## 8. 受控扩展边界

- 允许：在 `commandGrammar` / `commandExecutor` / `runtimeClient` 中增加 **白名单** 动词与 schema 映射。
- 不允许：任意 shell、任意用户 Julia 源码执行、脱离 `TaskRequest` 的自由文本冒充完整模型请求。

## 9. 相关文档

- [`runtime-protocol.md`](./runtime-protocol.md) — HTTP 动作与载荷。
- [`../superpowers/specs/2026-04-30-metrica-main-design.md`](../superpowers/specs/2026-04-30-metrica-main-design.md) — 全局主链路与非目标。
- [`s4-warning-coverage.md`](./s4-warning-coverage.md) — S4 warning 验收对照。
- [`../superpowers/plans/2026-05-16-s5-execution-plan.md`](../superpowers/plans/2026-05-16-s5-execution-plan.md) — 当前活跃施工计划。
