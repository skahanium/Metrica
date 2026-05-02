# 里程碑 5：地基升级与数据能力

状态：实施中；当前第一优先级是恢复并保持绿色基线
日期：2026-05-02

> **收口约束：** 里程碑 5 已经开始实施。在 `MetricaData.jl`、Runtime `/transform` 与 React App 的门禁测试全部恢复绿色前，不开启 IV、GLS、GMM 等新模型阶段，也不扩大 App 工作流范围。

## 背景

里程碑 1-4 完成了 Metrica 的技术验证——OLS、面板模型、诊断、教学数据集完整链路已跑通。但进一步的代码健康审计和竞争力分析揭示了两个紧迫问题：

1. **前端技术栈与文档严重脱节**。CLAUDE.md 声称使用 React 19 + TypeScript 5 + Zustand + Ant Design + AG Grid + ECharts，但实际实现是零依赖的 vanilla JS。当前 4 个文件（约 1000 行）在功能上是够用的，但在可扩展性上已经撞墙——每个新诊断类型需要在 `result-view.js` 中手写 HTML 模板，每次协议变更需要在三层各自更新硬编码的字段名。

2. **数据管理能力为零**。用户必须在外部完成所有数据准备工作。没有 merge、reshape、collapse、generate 等基础操作，Metrica 无法支撑一个完整的分析工作流。这是与 Stata 差距最大的功能维度。

里程碑 5 的目标不是增加新的统计模型，而是**加固地基**——让 Metrica 具备可扩展的 UI 架构和基本的自主数据准备能力，为后续模型扩展提供承载力。

## 产品定位

兼有教学工具和研究工具双重定位。M5 的工作对两边都是基础设施：
- **教学侧**：React 组件化让诊断解释卡片、交互式图表成为可能；数据管理让学生可以在 Metrica 内完成整个作业流程
- **研究侧**：merge/collapse/reshape 是实证分析的基本动作；TypeScript 类型系统让复杂协议变更更安全

## 架构决策

- 数据管理计算放在 Core 层（Julia），与 OLS/Panel 保持一致的三层架构。不做 Runtime 层数据处理，不引入新的数据处理引擎
- 前端升级采用直接替换策略——不在 vanilla JS 和 React 之间做混合运行，旧代码在迁移完成后归档
- 双轨并行开发：Track A（前端）和 Track B（数据层）独立开发、独立测试、独立提交

## Track A：前端技术栈升级

### 目标

将 `apps/metrica-desktop/src/` 的 vanilla JS 升级为 React 19 + TypeScript 5 + Vite，引入 Zustand 管理状态，Ant Design 替换原生控件，AG Grid 渲染数据表，ECharts 渲染诊断图表。

### 组件树

```
<App>
  <ConfigProvider theme={antdTheme}>  — Ant Design 主题
    <Layout>
      <Header>          — 菜单栏、运行按钮、加载状态
      <Sider>           — 数据源面板、变量浏览器
      <Content>
        <Tabs>
          <GlanceTab>   — AG Grid 渲染 glance 指标表
          <TidyTab>     — AG Grid 渲染系数表（排序、筛选、虚拟滚动）
          <DiagTab>     — ECharts 诊断图 + 检验结果卡片
          <AugmentTab>  — AG Grid 渲染拟合值/残差预览
        </Tabs>
      </Content>
    </Layout>
  </ConfigProvider>
</App>
```

### Zustand Store 设计

**appStore**：`{ activeTab, isLoading, error }`
**modelStore**：`{ modelType, formula, options, lastResult }`
**datasetStore**：`{ filePath, summary, preview }`

### 文件结构

```
apps/metrica-desktop/
  src/                          # 旧 vanilla JS（迁移完成后归档）
  src-react/
    components/
      App.tsx
      Header.tsx
      Sidebar.tsx
      GlanceTable.tsx
      TidyTable.tsx
      DiagnosticCards.tsx
      DiagnosticCharts.tsx
      AugmentPreview.tsx
      DataSourcePanel.tsx
      ModelForm.tsx
    stores/
      appStore.ts
      modelStore.ts
      datasetStore.ts
    services/
      runtimeClient.ts          # 改写自 runtime-client.js
      types/
        protocol.ts             # 请求/响应类型定义（共享 schema）
    main.tsx
  index.html
  package.json
  tsconfig.json
  vite.config.ts
```

### 迁移策略

1. 在 `src-react/` 中并行开发，旧 `src/` 保持不变
2. 以现有测试用例为验收基准——新组件必须通过同等断言
3. 完成后切换 `index.html` 入口，归档 `src/`
4. `protocol.ts` 作为诊断和数据协议的统一类型定义，消除 Julia/Rust/JS 三层各自硬编码字段名的问题

### 验收标准

- [ ] 现有全部功能等价（OLS + Panel 拟合、诊断展示、数据预览、错误/警告渲染）
- [ ] 现有测试用例在新 UI 上全部通过（`npm test`）
- [ ] Ant Design 组件替换原生 HTML 控件
- [ ] AG Grid 替换手写 table（支持排序、筛选、虚拟滚动）
- [ ] ECharts 替换文本式诊断输出（至少：残差直方图、QQ plot）

## Track B：数据管理能力（MetricaData.jl）

### 目标

在 Core 层新增 Julia 包，提供对标 Stata 的基础数据操作能力。所有操作通过 Runtime `/transform` 端点暴露，App 层在 React 组件中接入。

### 包结构

```
packages/MetricaData.jl/
  Project.toml
  src/
    MetricaData.jl            # 主模块
    transform.jl              # generate / replace / rename / drop / keep
    reshape.jl                # reshape_long / reshape_wide
    combine.jl                # sort / filter / collapse
    join.jl                   # merge (inner/left/right/outer)
    serialize.jl              # 结果序列化
  test/
    runtests.jl               # 每个函数独立测试
```

### 数据操作清单

| 函数 | Stata 等价 | 说明 |
|------|-----------|------|
| `generate(df, name, expr)` | `generate` | 创建新变量，支持算术表达式 |
| `replace(df, name, condition, value)` | `replace` | 条件替换 |
| `rename(df, mapping)` | `rename` | 重命名列 |
| `drop(df, cols)` | `drop` | 删除列 |
| `keep(df, cols)` | `keep` | 保留指定列 |
| `filter(df, condition)` | `keep if` | 条件筛选行 |
| `sort(df, cols)` | `sort` | 排序 |
| `merge(left, right, on, how)` | `merge` | inner/left/right/outer 连接 |
| `reshape_long(df, id_cols, time_col, stub)` | `reshape long` | 宽→长 |
| `reshape_wide(df, id_cols, time_col, value_cols)` | `reshape wide` | 长→宽 |
| `collapse(df, by, stats)` | `collapse` | 分组聚合 (mean/sum/sd/min/max/count) |

### 结果协议

每个操作返回统一结构：

```json
{
  "operation": "merge",
  "status": "ok",
  "result": {
    "nrows": 358,
    "ncols": 8,
    "notes": "inner join: 358 matched, 2 unmatched left, 0 unmatched right"
  },
  "preview": { "columns": [...], "rows": [...] },
  "warnings": []
}
```

### Runtime 端点

```
POST /transform
{
  "dataset_path": "...",
  "operations": [
    {"op": "filter", "args": {"condition": "gdp > 0"}},
    {"op": "generate", "args": {"name": "log_gdp", "expr": "log(gdp)"}},
    {"op": "merge", "args": {"with": "...", "on": ["country", "year"], "how": "inner"}}
  ]
}
```

支持操作链——一次请求顺序执行多个操作，Julia 侧保证事务性（任一操作失败则整体回滚，返回错误）。

### 验收标准

- [ ] 每个数据操作函数有独立 Julia 单元测试
- [ ] `/transform` 端点 Rust 集成测试（多操作链、错误回滚、不合法参数）
- [ ] App 侧数据管理面板（Track A 完成后接入）
- [ ] 操作历史列表 + 实时预览
- [ ] 结构化错误指明失败的操作序号和原因

## 非目标

- 不新增统计模型（IV、Logit、GMM 等延后到 M6+）
- 不引入新的数据存储引擎（继续使用 CSV + DataFrame）
- 不做数据库接入
- 不做实时协作或云同步

## 技术债务清理（随 M5 一同处理）

M5 是清理已识别技术债务的自然时机：

| 问题 | 处理方式 |
|------|---------|
| `http.rs` 死代码 | 删除旧 TCP HTTP 实现，统一用 axum |
| `MetricaTests.jl` 命名不当 | 重命名为 `MetricaDiagnostics.jl` |
| 序列化逻辑重复 | 提取共享序列化到 `MetricaOutput.jl` |
| 诊断字段三层硬编码 | TypeScript `protocol.ts` 作为共享类型定义 |
| CLAUDE.md 前端栈不准确 | M5 完成后更新 |
| `diagnostics_common.jl` 游离脚本 | 归入 `MetricaDiagnostics.jl` |
| 缺少统一设置指南 | 添加项目级 SETUP.md |

## 验证

- Track A：`npm test`（React Testing Library + Vitest）
- Track B：Julia `Pkg.test("MetricaData")` + Rust `cargo test`（`/transform` 端到端）
- 整体：手动运行桌面应用，走一遍完整流程（加载数据 → 筛选 → 生成新变量 → merge → OLS 拟合 → 诊断查看）
