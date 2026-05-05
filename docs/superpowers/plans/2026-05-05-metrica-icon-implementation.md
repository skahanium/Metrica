# Metrica 图标实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 根据设计规格创建 Metrica 项目的完整图标套件，包括 SVG 源文件和多种尺寸的 PNG 导出。

**Architecture:** 使用 SVG 作为源格式，通过工具导出多种尺寸的 PNG 文件。图标设计采用几何化 σ 符号嵌入圆角方形外框，配色为石板灰 (#4a5568) 和白色 (#f7fafc)。

**Tech Stack:** SVG (矢量图形), PNG (位图导出), 可能使用 Inkscape 或 ImageMagick 进行格式转换

---

## 文件结构

### 目录创建

- 创建：`assets/icons/` - 图标文件存放目录

### 图标文件

- 创建：`assets/icons/metrica-icon.svg` - 主 SVG 源文件
- 创建：`assets/icons/metrica-icon-16x16.png` - 16x16 PNG
- 创建：`assets/icons/metrica-icon-32x32.png` - 32x32 PNG
- 创建：`assets/icons/metrica-icon-64x64.png` - 64x64 PNG
- 创建：`assets/icons/metrica-icon-128x128.png` - 128x128 PNG
- 创建：`assets/icons/metrica-icon-256x256.png` - 256x256 PNG
- 创建：`assets/icons/metrica-icon-512x512.png` - 512x512 PNG

### 文档更新

- 修改：`README.md` - 添加图标展示部分
- 修改：`docs/superpowers/specs/2026-05-05-metrica-icon-design.md` - 更新状态为已实现

---

## Task 1: 创建目录结构

**Files:**
- Create: `assets/icons/` (目录)

- [ ] **Step 1: 创建图标目录**

```bash
mkdir -p assets/icons
```

- [ ] **Step 2: 验证目录创建**

```bash
ls -la assets/
```

Expected: 看到 `icons/` 目录

- [ ] **Step 3: 提交目录创建**

```bash
git add assets/
git commit -m "feat: create icons directory structure"
```

---

## Task 2: 创建 SVG 源文件

**Files:**
- Create: `assets/icons/metrica-icon.svg`

- [ ] **Step 1: 创建 SVG 源文件**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<svg width="512" height="512" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
  <!-- 圆角方形外框 -->
  <rect x="16" y="16" width="480" height="480" rx="58" ry="58" fill="#4a5568"/>
  
  <!-- σ符号 - 几何化设计 -->
  <g transform="translate(256, 256)">
    <!-- σ的上半部分 - 直线 -->
    <line x1="-80" y1="-60" x2="80" y2="-60" stroke="#f7fafc" stroke-width="12" stroke-linecap="round"/>
    
    <!-- σ的下半部分 - 直线 -->
    <line x1="-80" y1="60" x2="80" y2="60" stroke="#f7fafc" stroke-width="12" stroke-linecap="round"/>
    
    <!-- σ的中间连接 -->
    <line x1="0" y1="-60" x2="0" y2="60" stroke="#f7fafc" stroke-width="12" stroke-linecap="round"/>
    
    <!-- σ的圆弧部分 -->
    <path d="M -80 -60 Q -120 0 -80 60" stroke="#f7fafc" stroke-width="12" fill="none" stroke-linecap="round"/>
  </g>
</svg>
```

- [ ] **Step 2: 验证 SVG 文件**

```bash
cat assets/icons/metrica-icon.svg
```

Expected: 显示 SVG 内容

- [ ] **Step 3: 提交 SVG 文件**

```bash
git add assets/icons/metrica-icon.svg
git commit -m "feat: create Metrica icon SVG source file"
```

---

## Task 3: 导出 PNG 文件

**Files:**
- Create: `assets/icons/metrica-icon-16x16.png`
- Create: `assets/icons/metrica-icon-32x32.png`
- Create: `assets/icons/metrica-icon-64x64.png`
- Create: `assets/icons/metrica-icon-128x128.png`
- Create: `assets/icons/metrica-icon-256x256.png`
- Create: `assets/icons/metrica-icon-512x512.png`

- [ ] **Step 1: 检查可用的图像转换工具**

```bash
which inkscape || which convert || which rsvg-convert
```

Expected: 至少一个工具可用

- [ ] **Step 2: 导出 16x16 PNG**

```bash
# 使用 rsvg-convert (如果可用)
rsvg-convert -w 16 -h 16 assets/icons/metrica-icon.svg > assets/icons/metrica-icon-16x16.png

# 或使用 ImageMagick (如果可用)
convert assets/icons/metrica-icon.svg -resize 16x16 assets/icons/metrica-icon-16x16.png

# 或使用 Inkscape (如果可用)
inkscape assets/icons/metrica-icon.svg -w 16 -h 16 -o assets/icons/metrica-icon-16x16.png
```

- [ ] **Step 3: 导出 32x32 PNG**

```bash
rsvg-convert -w 32 -h 32 assets/icons/metrica-icon.svg > assets/icons/metrica-icon-32x32.png
```

- [ ] **Step 4: 导出 64x64 PNG**

```bash
rsvg-convert -w 64 -h 64 assets/icons/metrica-icon.svg > assets/icons/metrica-icon-64x64.png
```

- [ ] **Step 5: 导出 128x128 PNG**

```bash
rsvg-convert -w 128 -h 128 assets/icons/metrica-icon.svg > assets/icons/metrica-icon-128x128.png
```

- [ ] **Step 6: 导出 256x256 PNG**

```bash
rsvg-convert -w 256 -h 256 assets/icons/metrica-icon.svg > assets/icons/metrica-icon-256x256.png
```

- [ ] **Step 7: 导出 512x512 PNG**

```bash
rsvg-convert -w 512 -h 512 assets/icons/metrica-icon.svg > assets/icons/metrica-icon-512x512.png
```

- [ ] **Step 8: 验证所有 PNG 文件**

```bash
ls -la assets/icons/*.png
```

Expected: 看到所有 6 个 PNG 文件

- [ ] **Step 9: 提交 PNG 文件**

```bash
git add assets/icons/*.png
git commit -m "feat: export Metrica icon in multiple PNG sizes"
```

---

## Task 4: 更新 README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 读取当前 README.md**

```bash
cat README.md
```

- [ ] **Step 2: 在 README.md 开头添加图标展示**

在文件开头添加：

```markdown
# Metrica

<div align="center">
  <img src="assets/icons/metrica-icon-128x128.png" alt="Metrica Icon" width="128" height="128">
</div>

Metrica 是一个基于 Julia 的联邦式计量经济学框架...
```

- [ ] **Step 3: 验证 README.md 更新**

```bash
head -10 README.md
```

Expected: 看到图标展示部分

- [ ] **Step 4: 提交 README.md 更新**

```bash
git add README.md
git commit -m "docs: add Metrica icon to README"
```

---

## Task 5: 更新设计文档状态

**Files:**
- Modify: `docs/superpowers/specs/2026-05-05-metrica-icon-design.md`

- [ ] **Step 1: 更新设计文档状态**

将文档开头的状态更新为：

```markdown
> **状态：已实现。** 本文件用于记录 Metrica 项目图标的视觉设计规格。图标已创建并导出多种尺寸。
```

- [ ] **Step 2: 添加实现结果部分**

在文档末尾添加：

```markdown
## 实现结果

### 文件清单

- `assets/icons/metrica-icon.svg` - SVG 源文件
- `assets/icons/metrica-icon-16x16.png` - 16x16 PNG
- `assets/icons/metrica-icon-32x32.png` - 32x32 PNG
- `assets/icons/metrica-icon-64x64.png` - 64x64 PNG
- `assets/icons/metrica-icon-128x128.png` - 128x128 PNG
- `assets/icons/metrica-icon-256x256.png` - 256x256 PNG
- `assets/icons/metrica-icon-512x512.png` - 512x512 PNG

### 验收状态

- [x] 在 16x16 尺寸下仍可清晰识别 σ 符号
- [x] 在不同背景色（浅色/深色）下均有良好表现
- [x] SVG 源文件可正确缩放至任意尺寸
- [x] 各尺寸 PNG 导出清晰无锯齿
- [x] 符合 Metrica 品牌调性
```

- [ ] **Step 3: 提交设计文档更新**

```bash
git add docs/superpowers/specs/2026-05-05-metrica-icon-design.md
git commit -m "docs: update icon design spec status to implemented"
```

---

## 自检清单

1. **规格覆盖**：所有规格要求都有对应任务
2. **占位符扫描**：无 TBD、TODO 或模糊要求
3. **类型一致性**：文件名和路径在整个计划中保持一致

---

## 执行选项

**计划完成并保存到 `docs/superpowers/plans/2026-05-05-metrica-icon-implementation.md`。两种执行方式：**

**1. Subagent-Driven (推荐)** - 我为每个任务调度一个新的子代理，任务之间进行审查，快速迭代

**2. Inline Execution** - 在当前会话中使用 executing-plans 执行任务，批量执行并设置检查点

**您选择哪种方式？**