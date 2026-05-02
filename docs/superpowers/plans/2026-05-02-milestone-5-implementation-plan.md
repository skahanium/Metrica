# 里程碑 5 实施计划

> **状态：已完成。** M5 所有 Task 已完成并提交（最新提交 `3ad6f9b Stabilize M4 and M5 green baselines`）。门禁测试全部通过，地基已稳定。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 加固 Metrica 地基：前端升级到 React 19 + TypeScript 5 技术栈，新增 MetricaData.jl 数据管理包。

**Architecture:** 双轨并行。Track A 在 `src-react/` 中构建 React/TypeScript 前端，与旧 `src/` 并存，完成后切换入口。Track B 在 Julia Core 层新增 `MetricaData.jl` 包，通过 Runtime `/transform` 端点暴露。两条轨道独立开发、独立测试、独立提交。

**当前收口切片（2026-05-02）：**

- `/transform` 统一为 Task 风格请求：`task_id`、`action: "transform"`、`project_context`、`dataset_ref`、`operations`、`options`
- `options.persist_output` 在 M5 默认启用，派生 CSV 写入 `<working_dir>/.metrica/derived/<task_id>.csv`
- Runtime 返回 `TaskResponse` 风格结果，`result_payload.result.dataset_path` 指向派生 CSV
- `MetricaData.operate_chain` 负责事务式执行、结构化错误与成功写出 CSV；任一步失败时不写派生文件
- React App 通过 `transformStore`、`datasetStore.activePath`、数据操作面板、操作历史与预览表形成“数据处理 → 模型拟合”闭环
- M5 不迁移当前 wry/tao 桌面壳到完整 Tauri 2 插件架构；完整插件化文件对话框进入 M9 产品化或后续桌面增强

**Tech Stack:** React 19, TypeScript 5, Vite, Zustand, Ant Design, AG Grid, ECharts, Julia 1.12, DataFrames.jl, Rust/axum

---

## 文件结构

### Track A 新建文件

```
apps/metrica-desktop/
  src-react/
    types/
      protocol.ts              # 共享类型定义（诊断、模型结果、数据操作）
    services/
      runtimeClient.ts          # HTTP 客户端，改写自 src/runtime-client.js
    stores/
      appStore.ts               # { activeTab, isLoading, error }
      modelStore.ts             # { modelType, formula, options, lastResult }
      datasetStore.ts           # { sourcePath, activePath, summary, isDerived }
      transformStore.ts         # { operations, history, lastTransformResult, isTransforming }
    components/
      App.tsx                   # 根组件，ConfigProvider + Layout
      Header.tsx                # 菜单栏、运行按钮、状态指示
      Sidebar.tsx               # 数据源面板、变量浏览器
      DataSourcePanel.tsx       # 文件选择、数据检查
      DataOperationsPanel.tsx   # 数据操作链配置与运行
      OperationHistory.tsx      # 操作历史、失败位置、行列变化
      DataPreviewTable.tsx      # inspect 或 transform preview
      ModelForm.tsx             # 模型类型/公式/选项表单
      GlanceTable.tsx           # AG Grid 渲染 glance 指标
      TidyTable.tsx             # AG Grid 渲染系数表
      DiagnosticCards.tsx       # 诊断检验结果卡片
      DiagnosticCharts.tsx      # ECharts 诊断图表
      AugmentPreview.tsx        # AG Grid 渲染拟合值/残差
      ErrorPanel.tsx            # 错误消息面板
      WarningPanel.tsx          # 警告消息面板
      EmptyState.tsx            # 通用空状态组件
    main.tsx                    # ReactDOM.createRoot 入口
  index-react.html              # 新入口 HTML（Vite 挂载点）
  package.json                  # 更新：添加 React/TS/Vite 依赖
  tsconfig.json                 # TypeScript 配置
  vite.config.ts                # Vite 构建配置
```

### Track B 新建文件

```
packages/MetricaData.jl/
  Project.toml
  src/
    MetricaData.jl              # 主模块，导出全部函数
    transform.jl                # generate / replace / rename / drop / keep
    reshape.jl                  # reshape_long / reshape_wide
    combine.jl                  # sort / filter / collapse
    join.jl                     # merge (inner/left/right/outer)
    serialize.jl                # 操作结果序列化
  test/
    runtests.jl                 # 每个函数独立测试
```

### 修改文件

```
runtime/metrica-runtime/src/server.rs     # 新增 /transform 端点
runtime/metrica-runtime/src/lib.rs        # 新增 TransformRequest/TransformResponse 类型
runtime/metrica-runtime/src/http.rs       # 删除（死代码清理）
runtime/metrica-runtime/src/main.rs       # 移除 http 模块引用
runtime/metrica-runtime/Cargo.toml        # 若需要新依赖
scripts/diagnostics_common.jl             # 归入 MetricaDiagnostics.jl
packages/MetricaTests.jl                   # 重命名为 MetricaDiagnostics.jl
CLAUDE.md                                  # M5 完成后更新前端栈描述
```

---

## Part 0：技术债务清理（先于双轨，共享基础设施）

### Task 0.1: 删除 http.rs 死代码

**Files:**
- Remove: `runtime/metrica-runtime/src/http.rs`
- Modify: `runtime/metrica-runtime/src/main.rs`
- Modify: `runtime/metrica-runtime/src/lib.rs`

- [ ] **Step 1: 从 lib.rs 移除 http 模块声明和重导出**

编辑 `runtime/metrica-runtime/src/lib.rs`，删除以下行：

```rust
pub mod http;
```

以及：

```rust
pub use http::{build_http_response, default_bind_addr, serve_http, HttpResponse};
```

- [ ] **Step 2: 从 main.rs 移除 http 模块引用**

编辑 `runtime/metrica-runtime/src/main.rs`，检查并移除任何 `use metrica_runtime::http::...` 或 `mod http` 引用。

- [ ] **Step 3: 删除 http.rs 文件**

```bash
rm runtime/metrica-runtime/src/http.rs
```

- [ ] **Step 4: 编译验证**

```bash
cd runtime/metrica-runtime && cargo build 2>&1
```

预期：编译成功，无 http 模块相关错误。

- [ ] **Step 5: 运行 Rust 测试**

```bash
cd runtime/metrica-runtime && cargo test
```

预期：全部通过。

- [ ] **Step 6: Commit**

```bash
git add runtime/metrica-runtime/src/http.rs runtime/metrica-runtime/src/main.rs runtime/metrica-runtime/src/lib.rs
git commit -m "chore: remove dead http.rs raw TCP server, axum is the sole HTTP layer"
```

---

### Task 0.2: 重命名 MetricaTests.jl → MetricaDiagnostics.jl

**Files:**
- Rename: `packages/MetricaTests.jl/` → `packages/MetricaDiagnostics.jl/`
- Modify: `scripts/julia_bridge_entry.jl`
- Modify: `scripts/julia_daemon.jl`
- Modify: `scripts/diagnostics_common.jl`

- [ ] **Step 1: 重命名目录**

```bash
mv packages/MetricaTests.jl packages/MetricaDiagnostics.jl
```

- [ ] **Step 2: 更新 Project.toml**

编辑 `packages/MetricaDiagnostics.jl/Project.toml`，将 `name = "MetricaTests"` 改为 `name = "MetricaDiagnostics"`。

- [ ] **Step 3: 更新主模块文件**

编辑 `packages/MetricaDiagnostics.jl/src/MetricaTests.jl`（如果存在），重命名为 `MetricaDiagnostics.jl`，将 `module MetricaTests` 改为 `module MetricaDiagnostics`。

```bash
cd packages/MetricaDiagnostics.jl/src
# 检查是否存在 MetricaTests.jl
ls
```

根据实际文件名执行相应重命名和模块声明更新。

- [ ] **Step 4: 更新所有引用**

在 `scripts/julia_bridge_entry.jl` 和 `scripts/julia_daemon.jl` 中，将 `MetricaTests` 替换为 `MetricaDiagnostics`。

搜索：
```bash
grep -r "MetricaTests" scripts/ packages/ runtime/
```

逐一替换所有生产代码中的引用（测试文件中的历史引用可保留在注释中）。

- [ ] **Step 5: 将 diagnostics_common.jl 归入 MetricaDiagnostics.jl**

```bash
mv scripts/diagnostics_common.jl packages/MetricaDiagnostics.jl/src/diagnostics_common.jl
```

更新 `julia_bridge_entry.jl` 和 `julia_daemon.jl` 中的 include 路径。

- [ ] **Step 6: 验证 Julia 环境**

```bash
cd packages/MetricaDiagnostics.jl && julia --project=. -e 'using MetricaDiagnostics; println("OK")'
```

预期：无错误输出 "OK"。

- [ ] **Step 7: Commit**

```bash
git add packages/MetricaTests.jl packages/MetricaDiagnostics.jl scripts/diagnostics_common.jl scripts/julia_bridge_entry.jl scripts/julia_daemon.jl
git commit -m "refactor: rename MetricaTests to MetricaDiagnostics, consolidate diagnostics_common.jl"
```

---

## Part 1：Track A — 前端 React/TypeScript 升级

### Task A.1: 初始化 Vite + React + TypeScript 项目

**Files:**
- Create: `apps/metrica-desktop/package.json`（更新）
- Create: `apps/metrica-desktop/tsconfig.json`
- Create: `apps/metrica-desktop/vite.config.ts`
- Create: `apps/metrica-desktop/index-react.html`
- Create: `apps/metrica-desktop/src-react/main.tsx`

- [ ] **Step 1: 更新 package.json**

覆写 `apps/metrica-desktop/package.json`：

```json
{
  "name": "metrica-desktop",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "zustand": "^5.0.0",
    "antd": "^5.22.0",
    "@ant-design/icons": "^5.5.0",
    "ag-grid-community": "^33.0.0",
    "ag-grid-react": "^33.0.0",
    "echarts": "^5.5.0",
    "echarts-for-react": "^3.0.0"
  },
  "devDependencies": {
    "@testing-library/react": "^16.1.0",
    "@testing-library/jest-dom": "^6.6.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^4.3.0",
    "jsdom": "^25.0.0",
    "typescript": "~5.6.0",
    "vite": "^6.0.0",
    "vitest": "^2.1.0"
  }
}
```

- [ ] **Step 2: 创建 tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "outDir": "./dist",
    "rootDir": "./src-react"
  },
  "include": ["src-react"]
}
```

- [ ] **Step 3: 创建 vite.config.ts**

```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  root: '.',
  build: {
    outDir: 'dist',
  },
  server: {
    port: 5173,
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: [],
  },
});
```

- [ ] **Step 4: 创建 index-react.html**

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Metrica</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src-react/main.tsx"></script>
</body>
</html>
```

- [ ] **Step 5: 创建最小 main.tsx 入口**

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './components/App';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
```

- [ ] **Step 6: 安装依赖**

```bash
cd apps/metrica-desktop && npm install
```

- [ ] **Step 7: 验证 dev server 启动**

```bash
cd apps/metrica-desktop && npm run dev
```

预期：Vite 启动成功，打开 http://localhost:5173 看到空白页面，无控制台错误。

- [ ] **Step 8: Commit**

```bash
git add apps/metrica-desktop/package.json apps/metrica-desktop/tsconfig.json apps/metrica-desktop/vite.config.ts apps/metrica-desktop/index-react.html apps/metrica-desktop/src-react/main.tsx
git commit -m "feat: scaffold Vite + React 19 + TypeScript 5 project"
```

---

### Task A.2: 定义共享类型协议（protocol.ts）

**Files:**
- Create: `apps/metrica-desktop/src-react/types/protocol.ts`

- [ ] **Step 1: 创建 protocol.ts**

```typescript
// ============================================================
// 共享类型定义 — 协议层单一数据源
// Julia / Rust / TypeScript 三层通过此文件约定字段名
// ============================================================

// ---- 基础消息类型 ----

export interface Warning {
  title: string;
  detail: string;
}

export interface Message {
  level: 'info' | 'warning' | 'error';
  code: string;
  text: string;
  hint?: string;
}

// ---- 诊断类型（OLS） ----

export interface VifEntry {
  name: string;
  vif: number;
}

export interface DiagnosticResult {
  statistic: number | null;
  pvalue: number | null;
  dof?: number | null;
  method?: string;
  note?: string;
  available?: boolean;
}

export interface ResetDiagnostic extends DiagnosticResult {
  df_num?: number;
  df_den?: number;
}

export interface JarqueBeraDiagnostic extends DiagnosticResult {
  skewness?: number;
  kurtosis?: number;
}

export interface OLSDiagnostics {
  vif?: VifEntry[];
  breusch_pagan?: DiagnosticResult;
  white_test?: DiagnosticResult;
  durbin_watson?: DiagnosticResult;
  breusch_godfrey?: DiagnosticResult;
  reset_test?: ResetDiagnostic;
  jarque_bera?: JarqueBeraDiagnostic;
}

// ---- 诊断类型（Panel） ----

export interface PanelDiagnostics {
  hausman?: DiagnosticResult;
  fixed_effect_f?: DiagnosticResult;
  breusch_pagan_lm?: DiagnosticResult;
}

// ---- 模型结果 ----

export interface GlanceResult {
  model: string;
  nobs: number;
  dof: number;
  metrics: Record<string, number>;
}

export interface TidyRow {
  term: string;
  estimate: number;
  std_error: number;
  statistic: number;
  p_value: number;
  ci_lower?: number;
  ci_upper?: number;
}

export interface AugmentRow {
  fitted: number;
  residual: number;
  std_residual?: number;
  leverage?: number;
  cooks_d?: number;
}

export interface ModelResult {
  glance: GlanceResult;
  tidy: TidyRow[];
  diagnostics: OLSDiagnostics | PanelDiagnostics;
  augment_preview?: AugmentRow[];
  warnings: Warning[];
  messages?: Message[];
  summary_text?: string;
  vcov_label?: string;
}

// ---- 数据摘要 ----

export interface ColumnSummary {
  name: string;
  type: string;
  missing: number;
}

export interface DatasetSummary {
  nrows: number;
  ncols: number;
  columns: ColumnSummary[];
  preview: Record<string, unknown>[];
}

// ---- 运行时请求/响应 ----

export interface ModelSpec {
  model_type: 'ols' | 'panel';
  formula: string;
  vcov?: { type: string };
  weights?: string;
  cluster_column?: string;
  panel_id?: string;
  panel_time?: string;
  panel_method?: 'fe' | 're' | 'fd' | 'between';
}

export interface FitModelRequest {
  task_id: string;
  action: 'fit_model';
  project_context: { project_id: string; working_dir: string };
  dataset_ref: { source: string; path: string; format: string };
  model_spec: ModelSpec;
  options: { drop_missing: boolean; return_augment: boolean };
}

export interface TaskResponse {
  task_id: string;
  status: 'success' | 'error';
  messages: Message[];
  artifacts?: string[];
  result_payload?: ModelResult;
}

// ---- 数据操作类型（Track B 用） ----

export type DataOpKind =
  | 'filter' | 'generate' | 'replace' | 'rename' | 'drop' | 'keep'
  | 'sort' | 'merge' | 'reshape_long' | 'reshape_wide' | 'collapse';

export interface DataOp {
  op: DataOpKind;
  args: Record<string, unknown>;
}

export interface TransformRequest {
  dataset_path: string;
  operations: DataOp[];
}

export interface TransformResult {
  operation: string;
  status: 'ok' | 'error';
  result?: {
    nrows: number;
    ncols: number;
    notes: string;
  };
  preview?: { columns: string[]; rows: Record<string, unknown>[] };
  warnings: Warning[];
  error?: { op_index: number; message: string };
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/metrica-desktop/src-react/types/protocol.ts
git commit -m "feat: add shared TypeScript protocol types for diagnostics, model results, and data ops"
```

---

### Task A.3: Zustand Stores

**Files:**
- Create: `apps/metrica-desktop/src-react/stores/appStore.ts`
- Create: `apps/metrica-desktop/src-react/stores/modelStore.ts`
- Create: `apps/metrica-desktop/src-react/stores/datasetStore.ts`

- [ ] **Step 1: 创建 appStore.ts**

```typescript
import { create } from 'zustand';

interface AppState {
  activeTab: string;
  isLoading: boolean;
  error: string | null;
  setActiveTab: (tab: string) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
}

export const useAppStore = create<AppState>((set) => ({
  activeTab: 'glance',
  isLoading: false,
  error: null,
  setActiveTab: (activeTab) => set({ activeTab }),
  setLoading: (isLoading) => set({ isLoading }),
  setError: (error) => set({ error }),
}));
```

- [ ] **Step 2: 创建 modelStore.ts**

```typescript
import { create } from 'zustand';
import type { ModelResult, ModelSpec } from '../types/protocol';

interface ModelState {
  modelType: 'ols' | 'panel';
  formula: string;
  vcovType: string;
  weightsColumn: string;
  clusterColumn: string;
  panelId: string;
  panelTime: string;
  panelMethod: 'fe' | 're' | 'fd' | 'between';
  lastResult: ModelResult | null;
  setModelType: (t: 'ols' | 'panel') => void;
  setFormula: (f: string) => void;
  setVcovType: (v: string) => void;
  setWeightsColumn: (w: string) => void;
  setClusterColumn: (c: string) => void;
  setPanelId: (id: string) => void;
  setPanelTime: (t: string) => void;
  setPanelMethod: (m: 'fe' | 're' | 'fd' | 'between') => void;
  setLastResult: (r: ModelResult | null) => void;
  buildModelSpec: () => ModelSpec;
}

export const useModelStore = create<ModelState>((set, get) => ({
  modelType: 'ols',
  formula: 'y ~ x1 + x2',
  vcovType: 'classical',
  weightsColumn: '',
  clusterColumn: '',
  panelId: '',
  panelTime: '',
  panelMethod: 'fe',
  lastResult: null,
  setModelType: (modelType) => set({ modelType }),
  setFormula: (formula) => set({ formula }),
  setVcovType: (vcovType) => set({ vcovType }),
  setWeightsColumn: (weightsColumn) => set({ weightsColumn }),
  setClusterColumn: (clusterColumn) => set({ clusterColumn }),
  setPanelId: (panelId) => set({ panelId }),
  setPanelTime: (panelTime) => set({ panelTime }),
  setPanelMethod: (panelMethod) => set({ panelMethod }),
  setLastResult: (lastResult) => set({ lastResult }),
  buildModelSpec: () => {
    const s = get();
    const spec: ModelSpec = {
      model_type: s.modelType,
      formula: s.formula,
    };
    if (s.modelType === 'panel') {
      spec.panel_id = s.panelId;
      spec.panel_time = s.panelTime;
      spec.panel_method = s.panelMethod;
    } else {
      spec.vcov = { type: s.vcovType };
      if (s.weightsColumn.trim()) spec.weights = s.weightsColumn.trim();
      if (s.clusterColumn.trim()) spec.cluster_column = s.clusterColumn.trim();
    }
    return spec;
  },
}));
```

- [ ] **Step 3: 创建 datasetStore.ts**

```typescript
import { create } from 'zustand';
import type { DatasetSummary } from '../types/protocol';

interface DatasetState {
  filePath: string;
  summary: DatasetSummary | null;
  setFilePath: (p: string) => void;
  setSummary: (s: DatasetSummary | null) => void;
}

export const useDatasetStore = create<DatasetState>((set) => ({
  filePath: '',
  summary: null,
  setFilePath: (filePath) => set({ filePath }),
  setSummary: (summary) => set({ summary }),
}));
```

- [ ] **Step 4: Commit**

```bash
git add apps/metrica-desktop/src-react/stores/
git commit -m "feat: add Zustand stores for app, model, and dataset state"
```

---

### Task A.4: Runtime Client 服务层

**Files:**
- Create: `apps/metrica-desktop/src-react/services/runtimeClient.ts`

- [ ] **Step 1: 创建 runtimeClient.ts**

```typescript
import type { FitModelRequest, TaskResponse, DatasetSummary, TransformRequest, TransformResult } from '../types/protocol';

const DEFAULT_BASE = 'http://127.0.0.1:47821';

function createTaskId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `task-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export interface FitModelParams {
  datasetPath: string;
  formula: string;
  modelType?: 'ols' | 'panel';
  vcovType?: string;
  weightsColumn?: string;
  clusterColumn?: string;
  panelId?: string;
  panelTime?: string;
  panelMethod?: string;
  workingDir?: string;
}

export function buildFitModelRequest(params: FitModelParams): FitModelRequest {
  const {
    datasetPath,
    formula,
    modelType = 'ols',
    vcovType = 'classical',
    weightsColumn = '',
    clusterColumn = '',
    panelId = '',
    panelTime = '',
    panelMethod = 'fe',
    workingDir = 'apps/metrica-desktop',
  } = params;

  const modelSpec: FitModelRequest['model_spec'] = {
    model_type: modelType,
    formula,
  };

  if (modelType === 'panel') {
    modelSpec.panel_id = panelId;
    modelSpec.panel_time = panelTime;
    modelSpec.panel_method = panelMethod as 'fe' | 're' | 'fd' | 'between';
  } else {
    modelSpec.vcov = { type: vcovType };
    if (weightsColumn.trim()) modelSpec.weights = weightsColumn.trim();
    if (clusterColumn.trim()) modelSpec.cluster_column = clusterColumn.trim();
  }

  return {
    task_id: createTaskId(),
    action: 'fit_model',
    project_context: { project_id: 'alpha-demo', working_dir: workingDir },
    dataset_ref: { source: 'file', path: datasetPath, format: 'csv' },
    model_spec: modelSpec,
    options: { drop_missing: true, return_augment: true },
  };
}

export async function fitModel(
  params: FitModelParams,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<TaskResponse> {
  const body = JSON.stringify(buildFitModelRequest(params));
  const res = await fetchImpl(`${baseUrl}/fit_model`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  return res.json();
}

export async function inspectDataset(
  datasetPath: string,
  workingDir: string = 'apps/metrica-desktop',
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<DatasetSummary> {
  const body = JSON.stringify({
    task_id: createTaskId(),
    action: 'inspect_dataset',
    project_context: { project_id: 'alpha-demo', working_dir: workingDir },
    dataset_ref: { source: 'file', path: datasetPath, format: 'csv' },
    model_spec: { model_type: 'ols', formula: 'y ~ x1' },
    options: { drop_missing: false, return_augment: false },
  });
  const res = await fetchImpl(`${baseUrl}/inspect_dataset`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  const json = await res.json();
  return json.result_payload as DatasetSummary;
}

export async function transformDataset(
  request: TransformRequest,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<TransformResult> {
  const res = await fetchImpl(`${baseUrl}/transform`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  return res.json();
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/metrica-desktop/src-react/services/runtimeClient.ts
git commit -m "feat: add TypeScript runtime client with typed fit/inspect/transform functions"
```

---

### Task A.5: 基础 UI 组件（App, Header, Sidebar, EmptyState, ErrorPanel, WarningPanel）

**Files:**
- Create: `apps/metrica-desktop/src-react/components/App.tsx`
- Create: `apps/metrica-desktop/src-react/components/Header.tsx`
- Create: `apps/metrica-desktop/src-react/components/Sidebar.tsx`
- Create: `apps/metrica-desktop/src-react/components/EmptyState.tsx`
- Create: `apps/metrica-desktop/src-react/components/ErrorPanel.tsx`
- Create: `apps/metrica-desktop/src-react/components/WarningPanel.tsx`

- [ ] **Step 1: 创建 EmptyState.tsx**

```tsx
interface EmptyStateProps {
  title: string;
  description?: string;
}

export function EmptyState({ title, description }: EmptyStateProps) {
  return (
    <div style={{ padding: '24px', textAlign: 'center', color: '#8c8c8c' }}>
      <strong>{title}</strong>
      {description && <p style={{ marginTop: 8 }}>{description}</p>}
    </div>
  );
}
```

- [ ] **Step 2: 创建 ErrorPanel.tsx**

```tsx
import { Alert } from 'antd';

interface ErrorPanelProps {
  messages: Array<{ code: string; text: string; hint?: string }>;
}

export function ErrorPanel({ messages }: ErrorPanelProps) {
  if (!messages.length) return null;
  return (
    <div style={{ marginBottom: 16 }}>
      {messages.map((m, i) => (
        <Alert
          key={i}
          type="error"
          message={m.code}
          description={m.hint ? `${m.text} ${m.hint}` : m.text}
          style={{ marginBottom: 8 }}
        />
      ))}
    </div>
  );
}
```

- [ ] **Step 3: 创建 WarningPanel.tsx**

```tsx
import { Alert } from 'antd';
import type { Warning } from '../types/protocol';

interface WarningPanelProps {
  warnings: Warning[];
}

export function WarningPanel({ warnings }: WarningPanelProps) {
  if (!warnings.length) return null;
  return (
    <div style={{ marginBottom: 16 }}>
      {warnings.map((w, i) => (
        <Alert
          key={i}
          type="warning"
          message={w.title}
          description={w.detail}
          style={{ marginBottom: 8 }}
          showIcon
        />
      ))}
    </div>
  );
}
```

- [ ] **Step 4: 创建 Header.tsx**

```tsx
import { Button, Space, Typography } from 'antd';
import { PlayCircleOutlined } from '@ant-design/icons';
import { useAppStore } from '../stores/appStore';

const { Title, Text } = Typography;

export function Header() {
  const isLoading = useAppStore((s) => s.isLoading);

  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 24px', height: 64, background: '#fff', borderBottom: '1px solid #f0f0f0' }}>
      <Space align="baseline">
        <Text type="secondary" style={{ fontSize: 12, letterSpacing: 2, textTransform: 'uppercase' }}>Metrica</Text>
        <Title level={4} style={{ margin: 0 }}>计量分析工作台</Title>
      </Space>
      <Button type="primary" icon={<PlayCircleOutlined />} loading={isLoading} htmlType="submit" form="model-form">
        运行模型
      </Button>
    </div>
  );
}
```

- [ ] **Step 5: 创建 Sidebar.tsx**

```tsx
import { Typography } from 'antd';
import { DataSourcePanel } from './DataSourcePanel';

const { Title, Text } = Typography;

export function Sidebar() {
  return (
    <div style={{ padding: 16, width: 280, background: '#fafafa', borderRight: '1px solid #f0f0f0', height: '100%' }}>
      <Title level={5}>数据源</Title>
      <DataSourcePanel />
      <div style={{ marginTop: 24 }}>
        <Title level={5}>变量</Title>
        <Text type="secondary">检查数据后将显示变量列表。</Text>
      </div>
    </div>
  );
}
```

- [ ] **Step 6: 创建 App.tsx**

```tsx
import { ConfigProvider, Layout, Tabs, theme } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { ModelForm } from './ModelForm';
import { GlanceTable } from './GlanceTable';
import { TidyTable } from './TidyTable';
import { DiagnosticCards } from './DiagnosticCards';
import { DiagnosticCharts } from './DiagnosticCharts';
import { AugmentPreview } from './AugmentPreview';
import { ErrorPanel } from './ErrorPanel';
import { WarningPanel } from './WarningPanel';
import { useAppStore } from '../stores/appStore';
import { useModelStore } from '../stores/modelStore';

const { Content, Sider } = Layout;

export function App() {
  const { activeTab, setActiveTab, error } = useAppStore();
  const lastResult = useModelStore((s) => s.lastResult);

  return (
    <ConfigProvider theme={{ algorithm: theme.defaultAlgorithm }} locale={zhCN}>
      <Layout style={{ minHeight: '100vh' }}>
        <Header />
        <Layout>
          <Sider width={280} style={{ background: '#fafafa' }}>
            <Sidebar />
          </Sider>
          <Content style={{ padding: 24, background: '#fff' }}>
            <ModelForm />
            {error && <ErrorPanel messages={[{ code: 'ERROR', text: error }]} />}
            {lastResult?.warnings && <WarningPanel warnings={lastResult.warnings} />}
            <Tabs
              activeKey={activeTab}
              onChange={setActiveTab}
              items={[
                { key: 'glance', label: '模型概览', children: <GlanceTable /> },
                { key: 'tidy', label: '系数表', children: <TidyTable /> },
                { key: 'diagnostics', label: '诊断', children: <><DiagnosticCards /><DiagnosticCharts /></> },
                { key: 'augment', label: '拟合值', children: <AugmentPreview /> },
              ]}
            />
          </Content>
        </Layout>
      </Layout>
    </ConfigProvider>
  );
}
```

- [ ] **Step 7: Commit**

```bash
git add apps/metrica-desktop/src-react/components/App.tsx apps/metrica-desktop/src-react/components/Header.tsx apps/metrica-desktop/src-react/components/Sidebar.tsx apps/metrica-desktop/src-react/components/EmptyState.tsx apps/metrica-desktop/src-react/components/ErrorPanel.tsx apps/metrica-desktop/src-react/components/WarningPanel.tsx
git commit -m "feat: add base UI components — App shell, Header, Sidebar, EmptyState, ErrorPanel, WarningPanel"
```

---

### Task A.6: 表单组件（ModelForm, DataSourcePanel）

**Files:**
- Create: `apps/metrica-desktop/src-react/components/ModelForm.tsx`
- Create: `apps/metrica-desktop/src-react/components/DataSourcePanel.tsx`

- [ ] **Step 1: 创建 DataSourcePanel.tsx**

```tsx
import { useState } from 'react';
import { Input, Button, Space, Typography } from 'antd';
import { FolderOpenOutlined, SearchOutlined } from '@ant-design/icons';
import { useDatasetStore } from '../stores/datasetStore';
import { inspectDataset } from '../services/runtimeClient';

const { Text } = Typography;

export function DataSourcePanel() {
  const { filePath, setFilePath, setSummary } = useDatasetStore();
  const [loading, setLoading] = useState(false);

  const handleInspect = async () => {
    if (!filePath) return;
    setLoading(true);
    try {
      const summary = await inspectDataset(filePath);
      setSummary(summary);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Space direction="vertical" style={{ width: '100%' }}>
      <Input
        placeholder="CSV 文件路径"
        value={filePath}
        onChange={(e) => setFilePath(e.target.value)}
      />
      <Space>
        <Button icon={<FolderOpenOutlined />} size="small">选择文件</Button>
        <Button icon={<SearchOutlined />} size="small" loading={loading} onClick={handleInspect}>
          检查数据
        </Button>
      </Space>
      {filePath && <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>{filePath}</Text>}
    </Space>
  );
}
```

- [ ] **Step 2: 创建 ModelForm.tsx**

```tsx
import { Form, Select, Input, Card } from 'antd';
import { useModelStore } from '../stores/modelStore';
import { useAppStore } from '../stores/appStore';
import { useDatasetStore } from '../stores/datasetStore';
import { fitModel } from '../services/runtimeClient';

export function ModelForm() {
  const {
    modelType, setModelType, formula, setFormula,
    vcovType, setVcovType, weightsColumn, setWeightsColumn,
    clusterColumn, setClusterColumn,
    panelId, setPanelId, panelTime, setPanelTime,
    panelMethod, setPanelMethod, setLastResult,
  } = useModelStore();
  const { setLoading, setError } = useAppStore();
  const filePath = useDatasetStore((s) => s.filePath);

  const handleRun = async () => {
    if (!filePath) { setError('请先选择数据集'); return; }
    setLoading(true);
    setError(null);
    try {
      const res = await fitModel({
        datasetPath: filePath,
        formula,
        modelType,
        vcovType,
        weightsColumn,
        clusterColumn,
        panelId,
        panelTime,
        panelMethod,
      });
      if (res.status === 'error') {
        setError(res.messages.map((m) => m.text).join('; '));
      } else if (res.result_payload) {
        setLastResult(res.result_payload);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card size="small" style={{ marginBottom: 16 }}>
      <Form id="model-form" layout="inline" onFinish={handleRun}>
        <Form.Item label="模型类型">
          <Select value={modelType} onChange={(v) => setModelType(v)} style={{ width: 100 }}>
            <Select.Option value="ols">OLS / WLS</Select.Option>
            <Select.Option value="panel">Panel</Select.Option>
          </Select>
        </Form.Item>
        <Form.Item label={modelType === 'panel' ? '面板公式' : 'OLS 公式'}>
          <Input value={formula} onChange={(e) => setFormula(e.target.value)} style={{ width: 240 }} />
        </Form.Item>
        {modelType === 'panel' ? (
          <>
            <Form.Item label="个体列">
              <Input value={panelId} onChange={(e) => setPanelId(e.target.value)} style={{ width: 100 }} placeholder="firm" />
            </Form.Item>
            <Form.Item label="时间列">
              <Input value={panelTime} onChange={(e) => setPanelTime(e.target.value)} style={{ width: 100 }} placeholder="year" />
            </Form.Item>
            <Form.Item label="方法">
              <Select value={panelMethod} onChange={(v) => setPanelMethod(v)} style={{ width: 120 }}>
                <Select.Option value="fe">FE 固定效应</Select.Option>
                <Select.Option value="re">RE 随机效应</Select.Option>
                <Select.Option value="fd">FD 一阶差分</Select.Option>
                <Select.Option value="between">Between</Select.Option>
              </Select>
            </Form.Item>
          </>
        ) : (
          <>
            <Form.Item label="协方差">
              <Select value={vcovType} onChange={(v) => setVcovType(v)} style={{ width: 120 }}>
                <Select.Option value="classical">classical</Select.Option>
                <Select.Option value="HC1">HC1</Select.Option>
                <Select.Option value="cluster">cluster</Select.Option>
              </Select>
            </Form.Item>
            <Form.Item label="权重列">
              <Input value={weightsColumn} onChange={(e) => setWeightsColumn(e.target.value)} style={{ width: 100 }} placeholder="可选" />
            </Form.Item>
            <Form.Item label="聚类列">
              <Input value={clusterColumn} onChange={(e) => setClusterColumn(e.target.value)} style={{ width: 100 }} placeholder="可选" />
            </Form.Item>
          </>
        )}
      </Form>
    </Card>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/metrica-desktop/src-react/components/ModelForm.tsx apps/metrica-desktop/src-react/components/DataSourcePanel.tsx
git commit -m "feat: add ModelForm and DataSourcePanel with full OLS/panel parameter UI"
```

---

### Task A.7: 结果渲染组件（GlanceTable, TidyTable, DiagnosticCards）

**Files:**
- Create: `apps/metrica-desktop/src-react/components/GlanceTable.tsx`
- Create: `apps/metrica-desktop/src-react/components/TidyTable.tsx`
- Create: `apps/metrica-desktop/src-react/components/DiagnosticCards.tsx`

- [ ] **Step 1: 创建 GlanceTable.tsx**

```tsx
import { useModelStore } from '../stores/modelStore';
import { EmptyState } from './EmptyState';
import { Descriptions, Card } from 'antd';
import type { GlanceResult } from '../types/protocol';

const METRIC_LABELS: Record<string, string> = {
  r2: 'R²',
  adj_r2: '调整 R²',
  sigma: '残差标准误',
  rss: 'RSS',
  tss: 'TSS',
  n_ids: '个体数',
  n_times: '时期数',
};

function formatMetric(key: string, value: number): string {
  if (['r2', 'adj_r2'].includes(key)) return value.toFixed(4);
  if (key === 'sigma') return value.toFixed(4);
  if (['rss', 'tss'].includes(key)) return value.toFixed(2);
  if (['n_ids', 'n_times'].includes(key)) return String(Math.round(value));
  return value.toFixed(4);
}

export function GlanceTable() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult) return <EmptyState title="尚未运行模型" description="请配置参数后点击运行。" />;

  const { glance } = lastResult;

  return (
    <Card size="small">
      <Descriptions bordered size="small" column={3}>
        <Descriptions.Item label="模型">{glance.model.toUpperCase()}</Descriptions.Item>
        <Descriptions.Item label="样本量">{glance.nobs}</Descriptions.Item>
        <Descriptions.Item label="自由度">{glance.dof}</Descriptions.Item>
        {Object.entries(glance.metrics).map(([key, value]) => (
          <Descriptions.Item key={key} label={METRIC_LABELS[key] ?? key}>
            {formatMetric(key, value)}
          </Descriptions.Item>
        ))}
      </Descriptions>
    </Card>
  );
}
```

- [ ] **Step 2: 创建 TidyTable.tsx**

```tsx
import { useMemo } from 'react';
import { AgGridReact } from 'ag-grid-react';
import { Card } from 'antd';
import { useModelStore } from '../stores/modelStore';
import { EmptyState } from './EmptyState';
import type { ColDef } from 'ag-grid-community';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-alpine.css';
import type { TidyRow } from '../types/protocol';

const COLUMNS: ColDef<TidyRow>[] = [
  { field: 'term', headerName: '参数', width: 150 },
  { field: 'estimate', headerName: '估计值', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'std_error', headerName: '标准误', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'statistic', headerName: '统计量', width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
  { field: 'p_value', headerName: 'p 值', width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
];

export function TidyTable() {
  const lastResult = useModelStore((s) => s.lastResult);
  const rowData = useMemo(() => lastResult?.tidy ?? [], [lastResult]);

  if (!lastResult) return <EmptyState title="尚未运行模型" />;

  return (
    <Card size="small">
      {lastResult.vcov_label && (
        <div style={{ marginBottom: 8, color: '#8c8c8c', fontSize: 13 }}>{lastResult.vcov_label}</div>
      )}
      <div className="ag-theme-alpine" style={{ height: Math.min(400, (rowData.length + 1) * 42) }}>
        <AgGridReact<TidyRow>
          rowData={rowData}
          columnDefs={COLUMNS}
          domLayout="autoHeight"
        />
      </div>
    </Card>
  );
}
```

- [ ] **Step 3: 创建 DiagnosticCards.tsx**

```tsx
import { Card, Descriptions, Tag, Empty } from 'antd';
import { useModelStore } from '../stores/modelStore';
import type { DiagnosticResult, OLSDiagnostics, PanelDiagnostics } from '../types/protocol';

const OLS_DIAG_META: Array<{ key: keyof OLSDiagnostics; label: string; description: string }> = [
  { key: 'breusch_pagan', label: 'Breusch-Pagan 异方差检验', description: 'H0: 同方差' },
  { key: 'white_test', label: 'White 异方差检验', description: 'H0: 同方差' },
  { key: 'durbin_watson', label: 'Durbin-Watson 自相关检验', description: 'H0: 无一阶自相关' },
  { key: 'breusch_godfrey', label: 'Breusch-Godfrey 自相关检验', description: 'H0: 无自相关' },
  { key: 'reset_test', label: 'RESET 模型设定检验', description: 'H0: 模型设定正确' },
  { key: 'jarque_bera', label: 'Jarque-Bera 正态性检验', description: 'H0: 残差正态' },
];

const PANEL_DIAG_META: Array<{ key: keyof PanelDiagnostics; label: string; description: string }> = [
  { key: 'hausman', label: 'Hausman 检验', description: 'H0: RE 一致；小 p 值倾向 FE' },
  { key: 'fixed_effect_f', label: '固定效应 F 检验', description: 'H0: 个体效应为零（混合 OLS）' },
  { key: 'breusch_pagan_lm', label: 'Breusch-Pagan LM 检验', description: 'H0: 无随机效应（混合 OLS）' },
];

function isPanelDiagnostics(d: OLSDiagnostics | PanelDiagnostics): d is PanelDiagnostics {
  return 'hausman' in d || 'fixed_effect_f' in d || 'breusch_pagan_lm' in d;
}

function DiagCard({ label, description, result }: { label: string; description: string; result?: DiagnosticResult }) {
  if (!result || result.available === false) {
    return (
      <Card size="small" title={label} style={{ marginBottom: 8 }}>
        <Tag color="default">不可用</Tag>
        <span style={{ color: '#8c8c8c', marginLeft: 8 }}>{result?.note ?? '当前数据集不满足检验条件。'}</span>
      </Card>
    );
  }
  return (
    <Card size="small" title={label} style={{ marginBottom: 8 }}>
      <Descriptions size="small" column={3}>
        <Descriptions.Item label="统计量">{result.statistic?.toFixed(4)}</Descriptions.Item>
        {result.dof != null && <Descriptions.Item label="自由度">{result.dof}</Descriptions.Item>}
        <Descriptions.Item label="p 值">{result.pvalue?.toFixed(4)}</Descriptions.Item>
        <Descriptions.Item label="说明">{description}</Descriptions.Item>
      </Descriptions>
    </Card>
  );
}

export function DiagnosticCards() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult) return <Empty title="尚未运行模型" />;

  const diag = lastResult.diagnostics;
  if (!diag) return <Empty title="无诊断结果" />;

  if (isPanelDiagnostics(diag)) {
    return (
      <div>
        {PANEL_DIAG_META.map(({ key, label, description }) => (
          <DiagCard key={key} label={label} description={description} result={diag[key]} />
        ))}
      </div>
    );
  }

  return (
    <div>
      {OLS_DIAG_META.map(({ key, label, description }) => (
        <DiagCard key={key} label={label} description={description} result={diag[key]} />
      ))}
    </div>
  );
}
```

- [ ] **Step 4: Commit**

```bash
git add apps/metrica-desktop/src-react/components/GlanceTable.tsx apps/metrica-desktop/src-react/components/TidyTable.tsx apps/metrica-desktop/src-react/components/DiagnosticCards.tsx
git commit -m "feat: add GlanceTable, TidyTable with AG Grid, and DiagnosticCards components"
```

---

### Task A.8: 诊断图表与增强预览（DiagnosticCharts, AugmentPreview）

**Files:**
- Create: `apps/metrica-desktop/src-react/components/DiagnosticCharts.tsx`
- Create: `apps/metrica-desktop/src-react/components/AugmentPreview.tsx`

- [ ] **Step 1: 创建 DiagnosticCharts.tsx**

```tsx
import ReactECharts from 'echarts-for-react';
import { Card, Empty } from 'antd';
import { useModelStore } from '../stores/modelStore';

export function DiagnosticCharts() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult?.augment_preview?.length) return <Empty description="无增强数据，无法生成诊断图表。请在运行时开启 return_augment。" />;

  const residuals = lastResult.augment_preview.map((r) => r.residual);
  const fitted = lastResult.augment_preview.map((r) => r.fitted);

  const histogramOption = {
    title: { text: '残差分布', left: 'center' },
    xAxis: { name: '残差' },
    yAxis: { name: '频数' },
    series: [{
      type: 'histogram',
      data: residuals,
      itemStyle: { color: '#1677ff' },
    }],
    tooltip: { trigger: 'axis' },
  };

  const qqOption = {
    title: { text: '残差 Q-Q 图', left: 'center' },
    xAxis: { name: '理论分位数' },
    yAxis: { name: '样本分位数' },
    series: [{
      type: 'scatter',
      data: residuals
        .slice()
        .sort((a, b) => a - b)
        .map((v, i) => [v, (i + 0.5) / residuals.length]),
      itemStyle: { color: '#1677ff' },
    }],
    tooltip: { trigger: 'item' },
  };

  const scatterOption = {
    title: { text: '残差 vs 拟合值', left: 'center' },
    xAxis: { name: '拟合值' },
    yAxis: { name: '残差' },
    series: [{
      type: 'scatter',
      data: fitted.map((f, i) => [f, residuals[i]]),
      itemStyle: { color: '#1677ff' },
    }],
    tooltip: { trigger: 'item' },
    markLine: {
      silent: true,
      data: [{ yAxis: 0 }],
    },
  };

  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))', gap: 16, marginTop: 16 }}>
      <Card size="small"><ReactECharts option={histogramOption} style={{ height: 300 }} /></Card>
      <Card size="small"><ReactECharts option={qqOption} style={{ height: 300 }} /></Card>
      <Card size="small"><ReactECharts option={scatterOption} style={{ height: 300 }} /></Card>
    </div>
  );
}
```

- [ ] **Step 2: 创建 AugmentPreview.tsx**

```tsx
import { AgGridReact } from 'ag-grid-react';
import { Card, Empty } from 'antd';
import { useModelStore } from '../stores/modelStore';
import type { ColDef } from 'ag-grid-community';
import type { AugmentRow } from '../types/protocol';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-alpine.css';

const COLUMNS: ColDef<AugmentRow>[] = [
  { field: 'fitted', headerName: '拟合值', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'residual', headerName: '残差', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'std_residual', headerName: '标准化残差', width: 130, valueFormatter: (p) => p.value?.toFixed(4) },
  { field: 'leverage', headerName: '杠杆值', width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
  { field: 'cooks_d', headerName: "Cook's D", width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
];

export function AugmentPreview() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult?.augment_preview?.length) return <Empty description="无增强数据。请在运行时开启 return_augment。" />;

  return (
    <Card size="small">
      <div className="ag-theme-alpine" style={{ height: Math.min(400, (lastResult.augment_preview!.length + 1) * 42) }}>
        <AgGridReact<AugmentRow> rowData={lastResult.augment_preview} columnDefs={COLUMNS} domLayout="autoHeight" />
      </div>
    </Card>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/metrica-desktop/src-react/components/DiagnosticCharts.tsx apps/metrica-desktop/src-react/components/AugmentPreview.tsx
git commit -m "feat: add ECharts diagnostic charts and AG Grid augment preview"
```

---

### Task A.9: React 组件测试

**Files:**
- Create: `apps/metrica-desktop/src-react/__tests__/GlanceTable.test.tsx`
- Create: `apps/metrica-desktop/src-react/__tests__/DiagnosticCards.test.tsx`
- Create: `apps/metrica-desktop/src-react/__tests__/runtimeClient.test.ts`

- [ ] **Step 1: 创建 vitest 配置（追加到 vite.config.ts）**

编辑 `apps/metrica-desktop/vite.config.ts`，确保 test 配置存在（已在 Task A.1 中包含，此处验证）。

- [ ] **Step 2: 创建 GlanceTable.test.tsx**

```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { GlanceTable } from '../components/GlanceTable';
import { useModelStore } from '../stores/modelStore';
import type { ModelResult } from '../types/protocol';

const mockResult: ModelResult = {
  glance: { model: 'ols', nobs: 128, dof: 124, metrics: { r2: 0.81, adj_r2: 0.80, sigma: 1.5, rss: 280.0, tss: 1473.0 } },
  tidy: [],
  diagnostics: {},
  warnings: [],
};

describe('GlanceTable', () => {
  it('renders empty state when no result', () => {
    useModelStore.setState({ lastResult: null });
    render(<GlanceTable />);
    expect(screen.getByText('尚未运行模型')).toBeDefined();
  });

  it('renders glance metrics with Chinese labels', () => {
    useModelStore.setState({ lastResult: mockResult });
    render(<GlanceTable />);
    expect(screen.getByText('OLS')).toBeDefined();
    expect(screen.getByText('128')).toBeDefined();
    expect(screen.getByText('0.8100')).toBeDefined();
  });
});
```

- [ ] **Step 3: 创建 DiagnosticCards.test.tsx**

```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { DiagnosticCards } from '../components/DiagnosticCards';
import { useModelStore } from '../stores/modelStore';

describe('DiagnosticCards', () => {
  it('renders OLS diagnostics', () => {
    useModelStore.setState({
      lastResult: {
        glance: { model: 'ols', nobs: 128, dof: 124, metrics: { r2: 0.81 } },
        tidy: [],
        diagnostics: {
          breusch_pagan: { statistic: 3.2, pvalue: 0.0736, dof: 2 },
          white_test: { statistic: 5.1, pvalue: 0.0778, dof: 2 },
          durbin_watson: { statistic: 1.85, pvalue: 0.62 },
        },
        warnings: [],
      },
    });
    render(<DiagnosticCards />);
    expect(screen.getByText('Breusch-Pagan 异方差检验')).toBeDefined();
    expect(screen.getByText('Durbin-Watson 自相关检验')).toBeDefined();
  });

  it('shows unavailable diagnostic gracefully', () => {
    useModelStore.setState({
      lastResult: {
        glance: { model: 'ols', nobs: 128, dof: 124, metrics: { r2: 0.81 } },
        tidy: [],
        diagnostics: {
          breusch_pagan: { statistic: null, pvalue: null, available: false, note: '样本不足' },
        },
        warnings: [],
      },
    });
    render(<DiagnosticCards />);
    expect(screen.getByText('不可用')).toBeDefined();
  });
});
```

- [ ] **Step 4: 创建 runtimeClient.test.ts**

```typescript
import { describe, it, expect } from 'vitest';
import { buildFitModelRequest } from '../services/runtimeClient';

describe('buildFitModelRequest', () => {
  it('builds OLS request with correct structure', () => {
    const req = buildFitModelRequest({
      datasetPath: '/tmp/demo.csv',
      formula: 'y ~ x1 + x2',
    });
    expect(req.action).toBe('fit_model');
    expect(req.dataset_ref.path).toBe('/tmp/demo.csv');
    expect(req.model_spec.model_type).toBe('ols');
  });

  it('builds panel request with panel fields', () => {
    const req = buildFitModelRequest({
      datasetPath: '/tmp/panel.csv',
      formula: 'invest ~ mvalue + capital',
      modelType: 'panel',
      panelId: 'firm',
      panelTime: 'year',
      panelMethod: 'fe',
    });
    expect(req.model_spec.model_type).toBe('panel');
    expect(req.model_spec.panel_id).toBe('firm');
    expect(req.model_spec.panel_time).toBe('year');
  });

  it('includes weights and cluster for OLS', () => {
    const req = buildFitModelRequest({
      datasetPath: '/tmp/demo.csv',
      formula: 'y ~ x1 + x2',
      vcovType: 'cluster',
      clusterColumn: 'group_id',
    });
    expect(req.model_spec.vcov?.type).toBe('cluster');
    expect(req.model_spec.cluster_column).toBe('group_id');
  });
});
```

- [ ] **Step 5: 运行测试**

```bash
cd apps/metrica-desktop && npx vitest run
```

预期：全部通过。

- [ ] **Step 6: Commit**

```bash
git add apps/metrica-desktop/src-react/__tests__/
git commit -m "test: add React component tests for GlanceTable, DiagnosticCards, and runtimeClient"
```

---

### Task A.10: 切换入口 & 归档旧代码

**Files:**
- Modify: `apps/metrica-desktop/index.html`（指向 Vite 构建产物，或保留旧入口作为备选）
- Archive: `apps/metrica-desktop/src/` → `apps/metrica-desktop/src-vanilla-archive/`
- Archive: `apps/metrica-desktop/tests/` → `apps/metrica-desktop/src-vanilla-archive/tests/`

- [ ] **Step 1: 归档旧代码**

```bash
cd apps/metrica-desktop
mkdir -p src-vanilla-archive
mv src src-vanilla-archive/
mv tests src-vanilla-archive/tests
```

- [ ] **Step 2: 更新 index.html 指向 Vite 入口**

将 `apps/metrica-desktop/index.html` 替换为 `index-react.html` 的内容，或直接覆盖：

```bash
cp index-react.html index.html
```

- [ ] **Step 3: 确认 npm test 使用新测试**

更新 `package.json` 的 test script 为 `"vitest run"`。

- [ ] **Step 4: 运行全量测试**

```bash
cd apps/metrica-desktop && npm test
```

预期：全部通过。

- [ ] **Step 5: Commit**

```bash
git add apps/metrica-desktop/index.html apps/metrica-desktop/src-vanilla-archive/ apps/metrica-desktop/src-react/ apps/metrica-desktop/index-react.html
git commit -m "feat: switch entry to React app, archive vanilla JS source"
```

---

## Part 2：Track B — MetricaData.jl 数据管理包

### Task B.1: 创建 MetricaData.jl 包骨架

**Files:**
- Create: `packages/MetricaData.jl/Project.toml`
- Create: `packages/MetricaData.jl/src/MetricaData.jl`
- Create: `packages/MetricaData.jl/test/runtests.jl`

- [ ] **Step 1: 创建 Project.toml**

```toml
name = "MetricaData"
uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
authors = ["Metrica Contributors"]
version = "0.1.0"

[deps]
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[compat]
DataFrames = "1"
julia = "1.10"
```

> UUID 可通过 `julia -e 'using UUIDs; println(uuid4())'` 生成后替换。

- [ ] **Step 2: 创建 MetricaData.jl 主模块**

```julia
module MetricaData

using DataFrames

include("transform.jl")
include("reshape.jl")
include("combine.jl")
include("join.jl")
include("serialize.jl")

export generate, replace, rename, drop, keep
export filter, sort
export merge, reshape_long, reshape_wide, collapse
export operate, operate_chain

end # module MetricaData
```

- [ ] **Step 3: 创建测试骨架 runtests.jl**

```julia
using MetricaData
using DataFrames
using Test

@testset "MetricaData.jl" begin
    @testset "transform" begin
        include("test_transform.jl")
    end
    @testset "reshape" begin
        include("test_reshape.jl")
    end
    @testset "combine" begin
        include("test_combine.jl")
    end
    @testset "join" begin
        include("test_join.jl")
    end
end
```

- [ ] **Step 4: Commit**

```bash
git add packages/MetricaData.jl/
git commit -m "feat: scaffold MetricaData.jl package skeleton"
```

---

### Task B.2: 实现 transform.jl（generate, replace, rename, drop, keep）

**Files:**
- Create: `packages/MetricaData.jl/src/transform.jl`
- Create: `packages/MetricaData.jl/test/test_transform.jl`

- [ ] **Step 1: 编写测试 test_transform.jl**

```julia
using MetricaData
using DataFrames
using Test

@testset "generate" begin
    df = DataFrame(x = [1, 2, 3], y = [4, 5, 6])
    result = generate(df, "z", "x + y")
    @test result.df.z == [5, 7, 9]
end

@testset "replace" begin
    df = DataFrame(x = [1, 2, 3], flag = ["a", "b", "a"])
    result = replace(df, "flag", "x > 1", "\"c\"")
    @test result.df.flag == ["a", "c", "c"]
end

@testset "rename" begin
    df = DataFrame(x = [1, 2, 3])
    result = MetricaData.rename(df, Dict("x" => "value"))
    @test "value" in names(result.df)
    @test !("x" in names(result.df))
end

@testset "drop" begin
    df = DataFrame(x = [1, 2], y = [3, 4], z = [5, 6])
    result = drop(df, [:z])
    @test names(result.df) == ["x", "y"]
end

@testset "keep" begin
    df = DataFrame(x = [1, 2], y = [3, 4], z = [5, 6])
    result = keep(df, [:x])
    @test names(result.df) == ["x"]
end
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.test()'
```

预期：函数未定义。

- [ ] **Step 3: 实现 transform.jl**

```julia
using DataFrames

struct OpResult
    operation::String
    status::String          # "ok" | "error"
    df::DataFrame
    notes::String
    error::Union{Nothing, Dict{String, Any}}
end

function OpResult(operation::String, df::DataFrame; notes::String = "")
    return OpResult(operation, "ok", df, notes, nothing)
end

function OpResult(operation::String, ::Nothing; error::Dict{String, Any})
    return OpResult(operation, "error", DataFrame(), "", error)
end

"""
    generate(df, name, expr)

创建新变量。`expr` 为字符串表达式，使用列名作为变量。
"""
function generate(df::DataFrame, name::String, expr::String)
    df2 = copy(df)
    df2[!, name] = [begin
        row = NamedTuple{tuple(Symbol.(names(df2))...)}(Tuple(r))
        eval(Meta.parse(expr))
    end for r in eachrow(df2)]
    return OpResult("generate", df2, notes = "已创建变量 '$name' = $expr")
end

"""
    replace(df, col, condition, value_expr)

对满足条件的行替换列值。`condition` 和 `value_expr` 为字符串表达式。
"""
function replace(df::DataFrame, col::String, condition::String, value_expr::String)
    df2 = copy(df)
    for r in eachrow(df2)
        row = NamedTuple{tuple(Symbol.(names(df2))...)}(Tuple(r))
        if eval(Meta.parse(condition))
            df2[r, Symbol(col)] = eval(Meta.parse(value_expr))
        end
    end
    return OpResult("replace", df2, notes = "已按条件 $condition 替换 '$col'")
end

"""
    rename(df, mapping)

重命名列。`mapping` 为 Dict(old => new)。
"""
function rename(df::DataFrame, mapping::Dict{String, String})
    df2 = copy(df)
    new_names = [get(mapping, String(n), String(n)) for n in names(df2)]
    rename!(df2, Symbol.(new_names))
    return OpResult("rename", df2, notes = "已重命名 $(length(mapping)) 列")
end

"""
    drop(df, cols)

删除指定列。
"""
function drop(df::DataFrame, cols::Vector{Symbol})
    df2 = df[:, Not(cols)]
    return OpResult("drop", df2, notes = "已删除 $(length(cols)) 列")
end

"""
    keep(df, cols)

保留指定列。
"""
function keep(df::DataFrame, cols::Vector{Symbol})
    df2 = df[:, cols]
    return OpResult("keep", df2, notes = "已保留 $(length(cols)) 列")
end
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 5: Commit**

```bash
git add packages/MetricaData.jl/src/transform.jl packages/MetricaData.jl/test/test_transform.jl
git commit -m "feat: implement MetricaData transform — generate, replace, rename, drop, keep"
```

---

### Task B.3: 实现 combine.jl（filter, sort, collapse）

**Files:**
- Create: `packages/MetricaData.jl/src/combine.jl`
- Create: `packages/MetricaData.jl/test/test_combine.jl`

- [ ] **Step 1: 编写测试**

```julia
using MetricaData
using DataFrames
using Test

@testset "filter" begin
    df = DataFrame(x = [1, 2, 3], y = [4, 5, 6])
    result = MetricaData.filter(df, "x > 1")
    @test nrow(result.df) == 2
    @test result.df.x == [2, 3]
end

@testset "sort" begin
    df = DataFrame(x = [3, 1, 2], y = [6, 4, 5])
    result = MetricaData.sort(df, [:x])
    @test result.df.x == [1, 2, 3]
end

@testset "collapse" begin
    df = DataFrame(
        group = ["A", "A", "B", "B"],
        value = [10, 20, 30, 40],
    )
    result = collapse(df, [:group], ["mean", "sum"], [:value])
    @test nrow(result.df) == 2
    @test "value_mean" in names(result.df)
    @test "value_sum" in names(result.df)
end
```

- [ ] **Step 2: 实现 combine.jl**

```julia
using DataFrames
using Statistics

"""
    filter(df, condition)

按条件筛选行。`condition` 为字符串表达式。
"""
function filter(df::DataFrame, condition::String)
    mask = [begin
        row = NamedTuple{tuple(Symbol.(names(df))...)}(Tuple(r))
        eval(Meta.parse(condition))
    end for r in eachrow(df)]
    df2 = df[mask, :]
    return OpResult("filter", df2, notes = "筛选条件: $condition，保留 $(nrow(df2)) / $(nrow(df)) 行")
end

"""
    sort(df, cols; rev = false)

按指定列排序。
"""
function sort(df::DataFrame, cols::Vector{Symbol}; rev::Bool = false)
    df2 = sort(df, cols; rev)
    return OpResult("sort", df2, notes = "已按 $(join(String.(cols), ", ")) 排序")
end

"""
    collapse(df, by, stats, value_cols)

分组聚合。`stats` 可包含 "mean", "sum", "sd", "min", "max", "count"。
"""
function collapse(df::DataFrame, by::Vector{Symbol}, stats::Vector{String}, value_cols::Vector{Symbol})
    gd = groupby(df, by)
    results = Dict{String, Any}()
    for col in value_cols
        for stat in stats
            name = "$col" * "_" * stat
            results[name] = if stat == "mean"
                combine(gd, col => mean => name)
            elseif stat == "sum"
                combine(gd, col => sum => name)
            elseif stat == "sd"
                combine(gd, col => std => name)
            elseif stat == "min"
                combine(gd, col => minimum => name)
            elseif stat == "max"
                combine(gd, col => maximum => name)
            elseif stat == "count"
                combine(gd, col => length => name)
            end
        end
    end
    # 合并所有结果
    df2 = results[first(keys(results))]
    for key in keys(results)
        if key != first(keys(results))
            df2 = innerjoin(df2, results[key], on = String.(by))
        end
    end
    return OpResult("collapse", df2, notes = "分组: $(join(String.(by), ", "))，统计: $(join(stats, ", "))")
end
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 4: Commit**

```bash
git add packages/MetricaData.jl/src/combine.jl packages/MetricaData.jl/test/test_combine.jl
git commit -m "feat: implement MetricaData combine — filter, sort, collapse"
```

---

### Task B.4: 实现 join.jl（merge）

**Files:**
- Create: `packages/MetricaData.jl/src/join.jl`
- Create: `packages/MetricaData.jl/test/test_join.jl`

- [ ] **Step 1: 编写测试**

```julia
using MetricaData
using DataFrames
using Test

@testset "merge inner" begin
    left = DataFrame(id = [1, 2, 3], v1 = [10, 20, 30])
    right = DataFrame(id = [2, 3, 4], v2 = [200, 300, 400])
    result = MetricaData.merge(left, right, ["id"], "inner")
    @test nrow(result.df) == 2
    @test "v1" in names(result.df)
    @test "v2" in names(result.df)
end

@testset "merge left" begin
    left = DataFrame(id = [1, 2, 3], v1 = [10, 20, 30])
    right = DataFrame(id = [2, 3, 4], v2 = [200, 300, 400])
    result = MetricaData.merge(left, right, ["id"], "left")
    @test nrow(result.df) == 3
end

@testset "merge with notes" begin
    left = DataFrame(id = [1, 2], v1 = [10, 20])
    right = DataFrame(id = [1, 3], v2 = [100, 300])
    result = MetricaData.merge(left, right, ["id"], "inner")
    @test contains(result.notes, "1 matched")
end
```

- [ ] **Step 2: 实现 join.jl**

```julia
using DataFrames

"""
    merge(left, right, on, how)

连接两个 DataFrame。`how` 支持 "inner"、"left"、"right"、"outer"。
"""
function merge(left::DataFrame, right::DataFrame, on::Vector{String}, how::String)
    on_sym = Symbol.(on)
    how_map = Dict(
        "inner" => :inner,
        "left" => :left,
        "right" => :right,
        "outer" => :outer,
    )
    join_type = get(how_map, how, :inner)

    df2 = join(left, right, on = on_sym, kind = join_type)
    matched = nrow(df2)
    unmatched_left = sum(.!(
        [any(r[on_sym] .== row[on_sym]) for r in eachrow(right)]
        for row in eachrow(left)
    ))
    notes = "$how join: $matched matched, $unmatched_left unmatched left"
    return OpResult("merge", df2, notes = notes)
end
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 4: Commit**

```bash
git add packages/MetricaData.jl/src/join.jl packages/MetricaData.jl/test/test_join.jl
git commit -m "feat: implement MetricaData merge — inner/left/right/outer join"
```

---

### Task B.5: 实现 reshape.jl（reshape_long, reshape_wide）

**Files:**
- Create: `packages/MetricaData.jl/src/reshape.jl`
- Create: `packages/MetricaData.jl/test/test_reshape.jl`

- [ ] **Step 1: 编写测试**

```julia
using MetricaData
using DataFrames
using Test

@testset "reshape_long" begin
    wide = DataFrame(
        country = ["USA", "CAN"],
        gdp_2019 = [21.4, 1.7],
        gdp_2020 = [20.9, 1.6],
    )
    result = reshape_long(wide, [:country], "year", ["gdp"])
    @test nrow(result.df) == 4
    @test "year" in names(result.df)
    @test "gdp" in names(result.df)
end

@testset "reshape_wide" begin
    long = DataFrame(
        country = ["USA", "USA", "CAN", "CAN"],
        year = [2019, 2020, 2019, 2020],
        gdp = [21.4, 20.9, 1.7, 1.6],
    )
    result = reshape_wide(long, [:country], :year, [:gdp])
    @test nrow(result.df) == 2
    @test "gdp_2019" in names(result.df) || "gdp_2020" in names(result.df)
end
```

- [ ] **Step 2: 实现 reshape.jl**

```julia
using DataFrames

"""
    reshape_long(df, id_cols, time_col, stub_cols)

宽 → 长转换。以 `id_cols` 为标识，`stub_cols` 为 stub 列表，
生成 `time_col`（取值来自原宽列名后缀）和 `value` 列。
"""
function reshape_long(df::DataFrame, id_cols::Vector{Symbol}, time_col::String, stub_cols::Vector{String})
    id_names = String.(id_cols)
    all_stub_cols = String[]
    for stub in stub_cols
        pattern = Regex("^$(stub)_(.+)")
        for col_name in names(df)
            m = match(pattern, String(col_name))
            if m !== nothing
                push!(all_stub_cols, String(col_name))
            end
        end
    end
    df2 = stack(df, Symbol.(all_stub_cols), Symbol.(id_names),
        variable_name = Symbol(time_col), value_name = :_value)

    # 拆回多个 value 列
    result = df2
    if length(stub_cols) > 1
        # 简单情况：单个 stub 用 _value
        rename!(result, :_value => Symbol(stub_cols[1]))
    end

    notes = "reshape long: $(nrow(df)) → $(nrow(result)) 行"
    return OpResult("reshape_long", result, notes = notes)
end

"""
    reshape_wide(df, id_cols, time_col, value_cols)

长 → 宽转换。
"""
function reshape_wide(df::DataFrame, id_cols::Vector{Symbol}, time_col::Symbol, value_cols::Vector{Symbol})
    result = unstack(df, id_cols, time_col, value_cols[1])
    notes = "reshape wide: $(nrow(df)) → $(nrow(result)) 行"
    return OpResult("reshape_wide", result, notes = notes)
end
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 4: Commit**

```bash
git add packages/MetricaData.jl/src/reshape.jl packages/MetricaData.jl/test/test_reshape.jl
git commit -m "feat: implement MetricaData reshape — wide↔long conversion"
```

---

### Task B.6: 实现 serialize.jl 与操作链

**Files:**
- Create: `packages/MetricaData.jl/src/serialize.jl`
- Modify: `packages/MetricaData.jl/src/MetricaData.jl`

- [ ] **Step 1: 实现 serialize.jl**

```julia
using DataFrames, JSON

"""
将 OpResult 序列化为 Dict（Runtime 可直接序列化为 JSON）。
"""
function result_to_dict(result::OpResult)
    d = Dict{String, Any}(
        "operation" => result.operation,
        "status" => result.status,
    )
    if result.status == "ok"
        d["result"] = Dict(
            "nrows" => nrow(result.df),
            "ncols" => ncol(result.df),
            "notes" => result.notes,
        )
        # 预览前 10 行
        preview_n = min(10, nrow(result.df))
        d["preview"] = Dict(
            "columns" => String.(names(result.df)),
            "rows" => [Dict(String.(names(result.df)) .=> collect(r)) for r in eachrow(first(result.df, preview_n))],
        )
    else
        d["error"] = result.error
    end
    d["warnings"] = []
    return d
end

"""
    operate(df, op::Dict)

根据字典描述执行单个数据操作。返回 OpResult。
"""
function operate(df::DataFrame, op::Dict{String, Any})
    op_type = op["op"]::String
    args = op["args"]::Dict{String, Any}

    if op_type == "filter"
        return MetricaData.filter(df, args["condition"]::String)
    elseif op_type == "generate"
        return generate(df, args["name"]::String, args["expr"]::String)
    elseif op_type == "replace"
        return replace(df, args["col"]::String, args["condition"]::String, args["value"]::String)
    elseif op_type == "rename"
        mapping = Dict{String, String}(k => v for (k, v) in args["mapping"])
        return rename(df, mapping)
    elseif op_type == "drop"
        return drop(df, Symbol.(args["cols"]))
    elseif op_type == "keep"
        return keep(df, Symbol.(args["cols"]))
    elseif op_type == "sort"
        return MetricaData.sort(df, Symbol.(args["cols"]))
    elseif op_type == "merge"
        right_path = args["with"]::String
        right = CSV.read(right_path, DataFrame)
        on = args["on"]
        how = get(args, "how", "inner")
        return MetricaData.merge(df, right, on isa Vector ? String.(on) : [String(on)], String(how))
    elseif op_type == "reshape_long"
        return reshape_long(df, Symbol.(args["id_cols"]), args["time_col"]::String, String.(args["stub_cols"]))
    elseif op_type == "reshape_wide"
        return reshape_wide(df, Symbol.(args["id_cols"]), Symbol(args["time_col"]), Symbol.(args["value_cols"]))
    elseif op_type == "collapse"
        return collapse(df, Symbol.(args["by"]), String.(args["stats"]), Symbol.(args["value_cols"]))
    else
        return OpResult(op_type, nothing, error = Dict("message" => "Unknown operation: $op_type"))
    end
end

"""
    operate_chain(df, operations::Vector{Dict})

顺序执行多个操作。任一操作失败则停止并返回错误。
"""
function operate_chain(df::DataFrame, operations::Vector{Dict{String, Any}})
    results = Dict{String, Any}[]
    current_df = df
    for (i, op) in enumerate(operations)
        result = operate(current_df, op)
        if result.status == "error"
            result_dict = result_to_dict(result)
            result_dict["error"] = Dict("op_index" => i, "message" => get(result.error, "message", "Unknown error"))
            result_dict["status"] = "error"
            return result_dict
        end
        push!(results, result_to_dict(result))
        current_df = result.df
    end
    # 返回最后一步的预览，附带完整操作历史
    final = last(results)
    final["operations"] = results
    return final
end
```

- [ ] **Step 2: 更新 MetricaData.jl 主模块**

追加导出 `result_to_dict`, `operate`, `operate_chain`。

```julia
export result_to_dict, operate, operate_chain
```

- [ ] **Step 3: 运行全量测试**

```bash
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.test()'
```

- [ ] **Step 4: Commit**

```bash
git add packages/MetricaData.jl/src/serialize.jl packages/MetricaData.jl/src/MetricaData.jl
git commit -m "feat: add MetricaData serialization and operation chaining"
```

---

## Part 3：Runtime `/transform` 端点

### Task C.1: 添加 Transform 请求/响应类型

**Files:**
- Modify: `runtime/metrica-runtime/src/lib.rs`

- [ ] **Step 1: 在 lib.rs 中添加类型定义**

在文件末尾追加：

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformOperation {
    pub op: String,
    pub args: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformRequest {
    pub dataset_path: String,
    pub operations: Vec<TransformOperation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformResult {
    pub operation: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<TransformResultDetail>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview: Option<TransformPreview>,
    pub warnings: Vec<Message>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<TransformError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformResultDetail {
    pub nrows: usize,
    pub ncols: usize,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformPreview {
    pub columns: Vec<String>,
    pub rows: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformError {
    pub op_index: usize,
    pub message: String,
}
```

- [ ] **Step 2: 编译验证**

```bash
cd runtime/metrica-runtime && cargo build
```

- [ ] **Step 3: Commit**

```bash
git add runtime/metrica-runtime/src/lib.rs
git commit -m "feat: add TransformRequest and TransformResponse types to lib.rs"
```

---

### Task C.2: 添加 /transform 端点

**Files:**
- Modify: `runtime/metrica-runtime/src/server.rs`

- [ ] **Step 1: 在 server.rs 添加 transform handler**

在 `inspect_dataset_handler` 之后追加：

```rust
use crate::{TransformRequest, TransformResult};

/// POST /transform — 接受数据操作链，转发到 Julia MetricaData 执行。
async fn transform_handler(
    State(session): State<SharedSession>,
    body: String,
) -> impl IntoResponse {
    let request: TransformRequest = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"status": "error", "message": format!("Invalid request: {}", e)})),
            );
        }
    };

    let julia_script = format!(
        r#"
using MetricaData
using DataFrames, CSV, JSON

df = CSV.read("{}", DataFrame)
operations = JSON.parse("""{}""")
result = operate_chain(df, operations)
JSON.json(result)
"#,
        request.dataset_path,
        serde_json::to_string(&request.operations).unwrap(),
    );

    let mut s = session.lock().unwrap();
    match s.execute(&julia_script) {
        Ok(output) => {
            match serde_json::from_str::<serde_json::Value>(&output) {
                Ok(result) => (StatusCode::OK, Json(result)),
                Err(_) => (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(json!({"status": "error", "message": "Failed to parse Julia output"})),
                ),
            }
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({"status": "error", "message": format!("Julia error: {}", e)})),
        ),
    }
}
```

- [ ] **Step 2: 在 build_router 中注册路由**

```rust
.route("/transform", post(transform_handler))
```

- [ ] **Step 3: 编译验证**

```bash
cd runtime/metrica-runtime && cargo build
```

- [ ] **Step 4: Commit**

```bash
git add runtime/metrica-runtime/src/server.rs
git commit -m "feat: add /transform endpoint for MetricaData operation chaining"
```

---

### Task C.3: 集成测试 `/transform` 端点

**Files:**
- Modify: `runtime/metrica-runtime/tests/vertical_slice.rs`

- [ ] **Step 1: 添加 transform 测试**

在 `vertical_slice.rs` 末尾追加：

```rust
#[test]
fn transform_filter_operation_returns_valid_json() {
    let session = crate::test_helpers::spawn_test_session();
    let client = reqwest::blocking::Client::new();

    let body = json!({
        "dataset_path": concat!(env!("CARGO_MANIFEST_DIR"), "/../../datasets/teaching/pwt_productivity_panel.csv"),
        "operations": [
            {"op": "filter", "args": {"condition": "year >= 2015"}},
            {"op": "generate", "args": {"name": "log_output", "expr": "log(output_per_worker)"}}
        ]
    }).to_string();

    let resp = client
        .post("http://127.0.0.1:47821/transform")
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .expect("POST /transform should succeed");

    assert_eq!(resp.status(), 200);
    let json: Value = resp.json().expect("response should be JSON");
    assert_eq!(json["status"], "ok");
    assert!(json["result"]["nrows"].as_u64().unwrap() > 0);
}
```

- [ ] **Step 2: 运行集成测试**

```bash
cd runtime/metrica-runtime && cargo test
```

- [ ] **Step 3: Commit**

```bash
git add runtime/metrica-runtime/tests/vertical_slice.rs
git commit -m "test: add /transform endpoint integration test"
```

---

## Part 4：收尾

### Task D.1: 更新 CLAUDE.md 和 SETUP.md

**Files:**
- Modify: `CLAUDE.md`
- Create: `SETUP.md`

- [ ] **Step 1: 更新 CLAUDE.md 前端栈描述**

将当前描述 `React 19 + TypeScript 5 + Zustand + Ant Design + AG Grid + ECharts` 保持不变（它现在准确了），并添加里程碑 5 完成状态。

- [ ] **Step 2: 创建 SETUP.md**

```markdown
# Metrica 开发环境设置

## 前置要求

- Julia 1.10+
- Rust toolchain (rustup)
- Node.js 20+

## 初始化

### 1. Julia 包

```bash
cd packages/MetricaBase.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaDiagnostics.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaLinear.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaPanel.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd packages/MetricaOutput.jl && julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### 2. Runtime

```bash
cd runtime/metrica-runtime && cargo build
```

### 3. 桌面应用

```bash
cd apps/metrica-desktop && npm install && npm run dev
```

## 运行测试

```bash
# Julia
cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.test()'

# Rust
cd runtime/metrica-runtime && cargo test

# 前端
cd apps/metrica-desktop && npm test
```
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md SETUP.md
git commit -m "docs: update CLAUDE.md for M5 completion, add SETUP.md developer guide"
```

---

## 验证

- [ ] `cd packages/MetricaData.jl && julia --project=. -e 'using Pkg; Pkg.test()'` — 全部通过
- [ ] `cd runtime/metrica-runtime && cargo test` — 含 /transform 集成测试，全部通过
- [ ] `cd apps/metrica-desktop && npm test` — React 组件测试全部通过
- [ ] `cd apps/metrica-desktop && npm run dev` — dev server 启动，页面正常渲染
- [ ] 手动流程：启动 Runtime → 打开应用 → 加载 CSV → 筛选数据 → 生成新变量 → 拟合 OLS → 查看诊断图表
