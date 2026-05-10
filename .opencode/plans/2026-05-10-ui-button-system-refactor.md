# Metrica UI 按钮体系与左侧边栏重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Metrica 桌面应用从"分散按钮+数据源面板"重构为"三菜单入口+变量/信息双面板"的清晰交互体系，实现消息流回收站和数据历史功能。

**Architecture:** 顶部收敛为项目/数据/导出三个 Dropdown 菜单；左侧边栏改为变量窗口（上）+ 信息窗口（下）；主面板 ResultFlow 增加消息选择、删除、回收站能力；新增数据历史栈支持任意状态回滚。`.metrica` 项目文件从 JSON 目录升级为 SQLite 单文件。

**Tech Stack:** React 19 + TypeScript 5 + Zustand 5 + Ant Design 5 + AG Grid 33 + Vite 6

**设计文档:** `ui-project-button-system-plan.md`

---

## 文件结构

```
src-react/
  components/
    Header.tsx              ← MODIFY: 5按钮 → 3菜单 (项目/数据/导出)
    Sidebar.tsx             ← MODIFY: 重构为变量窗口 + 信息窗口
    VariableWindow.tsx      ← NEW: 变量名列表 + 单击插入 + 双击重命名
    InfoWindow.tsx          ← NEW: 数据集信息 + 选中变量信息
    ResultFlow.tsx          ← MODIFY: 增加消息选择/删除/回收站
    MessageToolbar.tsx      ← NEW: 消息流工具栏 (全选/删除/恢复)
    TrashPanel.tsx          ← NEW: 回收站面板
    DataHistoryPanel.tsx    ← NEW: 数据历史面板
  stores/
    appStore.ts             ← MODIFY: +trashVisible, +dataHistoryVisible
    datasetStore.ts         ← MODIFY: +variableMetadata, +selectedVariable, +dataHistory
    messageStore.ts         ← NEW: 消息流状态 (选择/删除/回收站)
  types/
    protocol.ts             ← MODIFY: +VariableMetadata, +DataHistoryNode, +MessageItem
  __tests__/
    messageStore.test.ts    ← NEW
```

---

## Phase 1: 类型定义与 Store 基础

### Task 1: 扩展 protocol.ts 类型

**Files:**
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts`

- [ ] **Step 1: 添加 VariableMetadata、DataHistoryNode、MessageItem、SaveParadigm 类型**
- [ ] **Step 2: 运行 `npx tsc --noEmit` 确认无报错**
- [ ] **Step 3: 提交**

### Task 2: 创建 messageStore

**Files:**
- Create: `apps/metrica-desktop/src-react/stores/messageStore.ts`

- [ ] **Step 1: 实现消息增删、选择、回收站逻辑**
- [ ] **Step 2: 写单元测试覆盖添加/删除/恢复/选择**
- [ ] **Step 3: 运行 `npx vitest run __tests__/messageStore.test.ts`**
- [ ] **Step 4: 提交**

### Task 3: 扩展 datasetStore

**Files:**
- Modify: `apps/metrica-desktop/src-react/stores/datasetStore.ts`

- [ ] **Step 1: 添加 variableMetadata、selectedVariable、dataHistory、renameVariable、restoreToHistoryIndex**
- [ ] **Step 2: 运行 `npx tsc --noEmit`**
- [ ] **Step 3: 提交**

---

## Phase 2: 顶部菜单系统

### Task 4: 重构 Header.tsx

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/Header.tsx`

- [ ] **Step 1: 将 5 个独立按钮替换为项目/数据/导出三个 Dropdown 菜单**
- [ ] **Step 2: 更新 appStore 添加 trashVisible、dataHistoryVisible**
- [ ] **Step 3: 运行 `npx tsc --noEmit`**
- [ ] **Step 4: 提交**

---

## Phase 3: 左侧边栏重构

### Task 5: 创建 VariableWindow

**Files:**
- Create: `apps/metrica-desktop/src-react/components/VariableWindow.tsx`

- [ ] **Step 1: 实现变量列表、搜索、单击插入 CLI、双击触发 rename**
- [ ] **Step 2: 提交**

### Task 6: 创建 InfoWindow

**Files:**
- Create: `apps/metrica-desktop/src-react/components/InfoWindow.tsx`

- [ ] **Step 1: 实现数据集信息 + 选中变量信息展示**
- [ ] **Step 2: 提交**

### Task 7: 重构 Sidebar.tsx

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/Sidebar.tsx`

- [ ] **Step 1: 移除 DataSourcePanel，改为 VariableWindow + InfoWindow 上下布局**
- [ ] **Step 2: 提交**

---

## Phase 4: 消息流与回收站

### Task 8: 创建 MessageToolbar

**Files:**
- Create: `apps/metrica-desktop/src-react/components/MessageToolbar.tsx`

- [ ] **Step 1: 实现全选/取消全选/删除选中/回收站入口**
- [ ] **Step 2: 提交**

### Task 9: 创建 TrashPanel

**Files:**
- Create: `apps/metrica-desktop/src-react/components/TrashPanel.tsx`

- [ ] **Step 1: 实现回收站 Modal，支持恢复/永久删除/清空**
- [ ] **Step 2: 提交**

### Task 10: 更新 ResultFlow

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/ResultFlow.tsx`

- [ ] **Step 1: 集成 messageStore，支持消息选择高亮**
- [ ] **Step 2: 提交**

---

## Phase 5: 数据历史

### Task 11: 创建 DataHistoryPanel

**Files:**
- Create: `apps/metrica-desktop/src-react/components/DataHistoryPanel.tsx`

- [ ] **Step 1: 实现 Timeline 展示历史节点，支持恢复到任意点**
- [ ] **Step 2: 提交**

---

## Phase 6: 教学解释集成

### Task 12: 更新 ResultBlock

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/ResultBlock.tsx`

- [ ] **Step 1: 将教学开关从全局移至 ResultBlock 内部按钮**
- [ ] **Step 2: 提交**

---

## Phase 7: App.tsx 整合

### Task 13: 更新 App.tsx

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/App.tsx`

- [ ] **Step 1: 导入 TrashPanel、DataHistoryPanel，移除 Header 的 teaching props**
- [ ] **Step 2: 运行 `npx tsc --noEmit`**
- [ ] **Step 3: 运行 `npx vitest run` 全量测试**
- [ ] **Step 4: 提交**

---

## Phase 8: 清理与验证

### Task 14: 清理废弃代码

- [ ] **Step 1: 删除 DataSourcePanel.tsx**
- [ ] **Step 2: 移除所有对废弃组件的引用**
- [ ] **Step 3: 运行完整测试和类型检查**
- [ ] **Step 4: 提交**

### Task 15: 最终验证

- [ ] **Step 1: 验证顶部只显示项目/数据/导出**
- [ ] **Step 2: 验证左侧边栏为变量窗口+信息窗口**
- [ ] **Step 3: 验证消息流选择/删除/回收站**
- [ ] **Step 4: 验证数据历史恢复**
- [ ] **Step 5: 运行 `npm run build` 确认构建成功**

---

## Assumptions

- 项目只使用现有左侧边栏，不新增右侧边栏
- 原始 CSV 不嵌入 `.metrica`
- `.metrica` SQLite 读写服务的具体实现需单独计划
- 变量标签在本阶段固定为首次导入时的原始变量名
- 消息删除和数据历史恢复是两套不同机制
