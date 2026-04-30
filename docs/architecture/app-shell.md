# 应用壳层（App Shell）

桌面壳层是基于 **Tauri 2 + React** 的计量经济学工作台，对标 RStudio / Jamovi / Stata 的经典工作台模式。

壳层必须消费结构化结果载荷，且不得解析终端摘要文本。

## 技术栈

| 层 | 选型 | 理由 |
|---|---|---|
| 壳层框架 | Tauri 2.x | 类型化 IPC 桥、原生文件对话框、菜单栏、剪贴板、窗口管理、构建管线（DMG/MSI）、能力权限系统 |
| 前端框架 | React 19 + TypeScript 5 | 组件生态最强，数据密集型 UI 组件最丰富 |
| 构建 | Vite 6 + `@tauri-apps/cli` | Tauri 官方推荐，HMR 热更新 |
| 状态管理 | Zustand | 轻量（~1KB），无 Provider 包裹，支持 selector 优化 |
| 路由 | React Router 7 | 多页面工作台（数据、模型、结果、学习） |
| 组件库 | Ant Design 5 | 中文生态最好，数据表格、表单、布局组件齐全 |
| 数据网格 | AG Grid Community | 虚拟化渲染 10 万+ 行，列调整/排序/筛选/选择 |
| 图表 | ECharts（echarts-for-react） | SVG/Canvas 双渲染器，交互式缩放/hover/筛选 |
| 样式 | CSS Modules + Ant Design token 系统 | 局部作用域避免样式冲突，token 系统支持主题定制 |

## 壳层能力（Tauri 2 插件）

| 能力 | 插件/API | 用途 |
|------|---------|------|
| 文件对话框 | `@tauri-apps/plugin-dialog` | 打开 CSV/Excel，导出 PDF/LaTeX |
| 剪贴板 | `@tauri-apps/plugin-clipboard-manager` | 复制系数表、导出 LaTeX |
| 菜单栏 | `@tauri-apps/api/menu` | File/Edit/View/Data/Model/Results/Tools/Help |
| 窗口管理 | `@tauri-apps/api/window` | 多窗口、大小持久化、全屏 |
| Shell | `@tauri-apps/plugin-shell` | 打开外部链接（教学文档） |
| Store | `@tauri-apps/plugin-store` | 持久化用户偏好（面板大小、最近项目） |

## 主窗口布局

```
┌──────────────────────────────────────────────────────────────────────┐
│ [菜单栏] File  Edit  View  Data  Model  Results  Tools  Help        │
├──────────────────────────────────────────────────────────────────────┤
│ [工具栏] [导入数据] [新建模型] [运行] [停止] [导出] │ [撤销] [重做]  │
├────────────┬─────────────────────────────────┬───────────────────────┤
│            │                                 │                       │
│  侧边栏    │       中央工作区                │    结果面板           │
│            │                                 │                       │
│ ┌────────┐ │  ┌───────────────────────────┐  │  ┌─────────────────┐  │
│ │项目导航 │ │  │  [数据检查] [模型配置]    │  │  │ 模型摘要 (glance)│  │
│ ├────────┤ │  │  [脚本编辑] [结果历史]    │  │  │ ┌─────┬───────┐ │  │
│ │变量列表 │ │  │                           │  │  │ │ 模型 │ OLS   │ │  │
│ │        │ │  │  (标签页切换的中央内容)     │  │  │ │ N    │ 842   │ │  │
│ │ x1 数值 │ │  │                           │  │  │ │ R²   │ 0.847 │ │  │
│ │ x2 数值 │ │  │  ┌─────────────────────┐  │  │  │ └─────┴───────┘ │  │
│ │ x3 类别 │ │  │  │ AG Grid 虚拟化表格  │  │  │                   │  │
│ │ y  数值 │ │  │  │ 10万+ 行流畅滚动     │  │  │ 系数表 (tidy)     │  │
│ │        │ │  │  └─────────────────────┘  │  │  │ ┌────┬────┬────┐ │  │
│ └────────┘ │  │                           │  │  │ │参数│估计 │p值 │ │  │
│            │  │  ┌─────────────────────┐  │  │  │ │ x1 │0.23│.001│ │  │
│            │  │  │ 公式: y ~ x1 + x2  │  │  │  │ └────┴────┴────┘ │  │
│            │  │  │ 模型: [OLS ▾]      │  │  │                   │  │
│            │  │  │ [运行模型]         │  │  │ 诊断图 (ECharts)   │  │
│            │  │  └─────────────────────┘  │  │  │ 残差 vs 拟合    │  │
│            │  └───────────────────────────┘  │  │ QQ 图           │  │
│            │                                 │  └─────────────────┘  │
├────────────┴─────────────────────────────────┴───────────────────────┤
│ [状态栏] Runtime: 已连接 │ Julia: 就绪 │ 数据: demo.csv (842行×5列) │
└──────────────────────────────────────────────────────────────────────┘
```

- **可调大小**：面板之间有拖拽分隔条（`react-resizable-panels`）
- **可折叠**：侧边栏可完全收起，扩大中央工作区
- **标签页**：中央工作区和结果面板都支持多标签页切换
- **状态持久化**：面板大小和布局在窗口关闭后保存，下次恢复

## 组件架构

```
App
├── ShellLayout                    # Tauri 窗口内的顶层布局
│   ├── MenuBar                   # 原生菜单栏（Tauri 菜单 API）
│   ├── Toolbar                   # 常用操作快捷栏
│   ├── MainWorkspace             # 可调大小的面板布局
│   │   ├── Sidebar               # 左侧：变量浏览器 + 项目导航
│   │   ├── CentralPanel          # 中央：数据表 / 模型配置 / 脚本编辑器
│   │   └── ResultPanel           # 右侧/底部：结果展示 + 图表
│   └── StatusBar                  # 底部状态栏
├── DataInspector                  # 数据检查页面
│   ├── DatasetSummary            # 行列摘要、列类型
│   ├── DataGrid                  # AG Grid 虚拟化数据表
│   └── VariableList              # 变量名、类型、缺失值统计
├── ModelBuilder                   # 模型配置页面
│   ├── FormulaInput              # 公式输入（支持变量拖拽）
│   ├── ModelTypeSelector         # 模型类型下拉
│   ├── VcovSelector              # 协方差类型选择
│   └── RunButton                 # 运行 + 进度指示
├── Results                        # 结果展示页面
│   ├── GlanceCards               # 模型摘要卡片
│   ├── TidyTable                 # 系数表（AG Grid）
│   ├── DiagnosticPlots           # ECharts 诊断图
│   ├── WarningsList              # 结构化警告 + 教学解释
│   └── ExportPanel               # 导出 CSV/LaTeX/PDF
└── Learn                          # 教学页面
    ├── TermGlossary              # 术语表
    └── TutorialSteps             # 分步教程
```

## Tauri IPC 命令

前端通过 Tauri 的 `invoke()` 调用 Rust 侧命令，获得原生桌面能力：

```typescript
// 文件对话框
const path = await open({
  title: '选择 CSV 文件',
  filters: [{ name: 'CSV', extensions: ['csv'] }],
  defaultPath: project.workingDir,
});

// 模型执行（通过 Tauri 命令转发到 Runtime HTTP）
const result = await invoke('execute_model', {
  request: { action: 'fit_model', dataset_ref, model_spec, options }
});
```

Rust 侧命令定义：

```rust
#[tauri::command]
async fn open_file_dialog(app, filters, default_path) -> Result<Option<String>, String>;

#[tauri::command]
async fn execute_model(state: State<RuntimeState>, request: TaskRequest) -> Result<TaskResponse, String>;

#[tauri::command]
async fn inspect_dataset(state: State<RuntimeState>, dataset_path: String) -> Result<TaskResponse, String>;

#[tauri::command]
async fn export_publication_plot(state: State<RuntimeState>, plot_spec, format, output_path) -> Result<String, String>;
```

## 数据网格（AG Grid）

| 能力 | 实现 |
|------|------|
| 10 万+ 行流畅滚动 | AG Grid 行虚拟化 |
| 列类型感知 | 数值列右对齐 + 等宽字体，字符串列左对齐 |
| 列调整/排序/筛选 | AG Grid 内置 |
| 单元格选择 + 复制 | AG Grid 内置 range selection |
| 缺失值高亮 | 单元格背景色标记，tooltip 显示缺失原因 |

## 可视化（ECharts）

消费 Core 层返回的 `PlotSpec` JSON，用 ECharts 渲染交互式图表。

诊断图：残差 vs 拟合值散点图、Q-Q 图、残差直方图、尺度-位置图。
数据探索图：变量分布直方图、两变量散点图 + 回归线、相关性热力图、箱线图。

交互特性：hover 显示精确值 + 观测行号、缩放/平移、框选高亮（联动数据表）、保存为 PNG/SVG。

出版级导出：用户点击导出时，PlotSpec 经 Tauri IPC → Runtime → Julia，由 Makie.jl 渲染 PDF/SVG/PNG。

可视化方向由当前主设计约束；具体 `PlotSpec` 与导出协议在进入对应实施任务时再写入当前计划，避免提前分叉出长期草案。

## 教学交互

在结果面板的每个结构化警告旁，显示教学解释卡片：

- 警告标题 + 结构化详情
- "什么是 listwise deletion？"等教学链接
- 缺失值分布明细
- 建议操作入口

## 目录结构

```
apps/metrica-desktop/
├── src-tauri/
│   ├── src/
│   │   ├── main.rs           # Tauri 入口
│   │   ├── lib.rs            # Tauri 插件注册 + 命令注册
│   │   ├── commands.rs       # IPC 命令实现
│   │   ├── runtime_bridge.rs # Runtime HTTP 客户端
│   │   └── state.rs          # Tauri 共享状态
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   └── capabilities/
├── src/
│   ├── main.tsx              # React 入口
│   ├── App.tsx               # 顶层路由 + 布局
│   ├── components/
│   ├── stores/               # Zustand stores
│   ├── hooks/
│   ├── services/             # Tauri IPC 封装
│   └── types/                # TypeScript 类型定义
├── index.html
├── package.json
├── vite.config.ts
└── tsconfig.json
```

## 实施阶段

### Phase 1：基础设施（壳层 + 构建管线）

- 用 `pnpm create tauri-app` 初始化 Tauri 2 + React + TypeScript 项目
- 配置 Vite、TypeScript、ESLint
- 配置 Tauri 插件（dialog, clipboard, shell, store）
- 实现原生菜单栏和工具栏骨架
- 验证：`pnpm tauri dev` 一键启动，React 页面在 Tauri 窗口中渲染

### Phase 2：工作台布局

- 实现 RStudio 风格的多面板布局（侧边栏 + 中央 + 结果 + 状态栏）
- 集成 `react-resizable-panels` 面板拖拽
- 实现标签页切换（数据 / 模型 / 结果 / 学习）
- 实现 Zustand 全局状态管理
- 验证：布局可交互，面板大小可调，标签页可切换

### Phase 3：Runtime 升级

- 将 Runtime 从手写 TCP 升级为 axum
- 实现持久化 Julia 进程管理器
- 实现 stdin/stdout JSON lines 协议
- 实现预热、超时、取消、崩溃恢复
- 保留现有 HTTP 端点兼容性
- 验证：`POST /fit_model` 返回真实 OLS 结果，无冷启动延迟

### Phase 4：数据检查

- 集成 AG Grid，实现虚拟化数据表
- 实现列类型感知渲染、缺失值高亮
- 实现变量浏览器（侧边栏）
- 实现数据摘要统计
- 验证：加载 demo.csv，10 万行模拟数据流畅滚动

### Phase 5：模型配置与结果展示

- 实现模型配置页面（公式输入、模型类型、协方差选择）
- 重写结果展示（glance 卡片、tidy 系数表、警告列表）
- 集成 ECharts，实现诊断图（残差图、QQ 图）
- 实现图表-数据联动
- 验证：端到端运行 OLS，展示结构化结果 + 诊断图

### Phase 6：教学交互与导出

- 实现教学解释卡片系统
- 实现导出功能（CSV、LaTeX、出版级 PDF）
- 实现命令历史 / 运行记录
- 实现项目保存/恢复
- 验证：完整教学工作流可演示

## 后续高级功能位置

"用户自定义能力"被视为较后阶段的高级功能，不属于当前页面范围。

后续只考虑两层受控能力：

- 受控自定义公式与选项
- 受控自定义动作 / 自定义分析模板

当前明确不考虑：

- 任意命令输入框
- 直接粘贴并执行 Julia 代码
- 脱离 Runtime 白名单的本地脚本执行入口

## 相关文档

- Runtime 载荷由 `docs/architecture/runtime-protocol.md` 负责。
- 项目级分层与当前主链路由 `docs/superpowers/specs/2026-04-30-metrica-main-design.md` 负责。
- 当前执行顺序由 `docs/superpowers/plans/2026-04-30-metrica-current-plan.md` 负责。
