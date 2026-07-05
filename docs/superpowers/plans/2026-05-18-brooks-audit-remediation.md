# Brooks Audit Remediation Implementation Plan

> **状态：已完成 / 已归档（2026-06-03）。** 对齐脚本、IV/GLS golden 与相关文档已合入 `main`。勿再作为活跃实施计划；当前工作见 [docs/quality/project-assessment.md](../../quality/project-assessment.md)。

> **For agentic workers:** 历史记录 only — 勿按本文件开新任务。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the concrete regressions and consistency gaps found while checking `BROOKS-AUDIT-2026-05-17.md`.

**Architecture:** Keep fixes within the existing Core / Runtime / App boundaries. This pass repairs quality-gate checks, Julia model registry declarations, golden-value fixtures, and docs consistency without adding model families or changing user-facing model semantics.

**Tech Stack:** Julia packages, Rust runtime, TypeScript protocol docs, local quality scripts.

---

### Task 1: Model Type Alignment

**Files:**
- Modify: `scripts/check_model_type_alignment.jl`
- Modify: `packages/MetricaBayes.jl/src/types.jl`
- Modify: `packages/MetricaBayes.jl/src/MetricaBayes.jl`
- Modify: `packages/MetricaDuration.jl/src/types.jl`
- Modify: `packages/MetricaDuration.jl/src/MetricaDuration.jl`
- Modify: `packages/MetricaSpatial.jl/src/types.jl`
- Modify: `packages/MetricaSpatial.jl/src/MetricaSpatial.jl`

- [ ] Fix invalid Julia return type syntax in the alignment script.
- [ ] Parse all backtick-delimited README model types, not only the first item per row.
- [ ] Add marker model structs and registry entries for Bayes, Duration, and Spatial model types that the runtime already supports.
- [ ] Run `julia scripts/check_model_type_alignment.jl` and confirm it reports aligned sources.

### Task 2: Golden Fixtures

**Files:**
- Modify: `datasets/golden/linear_iv.json`
- Modify: `datasets/golden/linear_gls.json`

- [ ] Generate actual deterministic values from the current `MetricaLinear` implementation.
- [ ] Replace placeholder `TO BE GENERATED`, `TBD`, `TODO`, and zero expected values.
- [ ] Run `julia --project=/Users/skahanium/Metrica/packages/MetricaLinear.jl -e "using Pkg; Pkg.test()"`.

### Task 3: Documentation Consistency

**Files:**
- Modify: `docs/quality/package-status.md`

- [ ] Sync PR quality mode with the expanded 18-package matrix.
- [ ] Mark Linear IV/GLS as internal deterministic fixtures unless externally validated.
- [ ] Keep remaining golden gaps explicit.

### Task 4: Audit Residual Verification

**Files:**
- Read only: Runtime and app protocol files.

- [ ] Run Rust compile and unit tests.
- [ ] Re-run alignment and targeted Julia tests.
- [ ] Report remaining architecture audit items that are not safe to finish as a quick fix, especially full `ModelSpec` wire-format migration.
