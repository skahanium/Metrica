# Metrica Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the initial Metrica repository foundation for a dual-track product: Julia Core plus cross-platform desktop app skeleton.

**Architecture:** The repository is organized around three isolated layers: Julia packages in `packages/`, a Rust runtime bridge in `runtime/`, and a Tauri desktop shell in `apps/`. The first implementation cycle validates the architecture with a minimal OLS-ready Core contract and a desktop-facing runtime/result schema, without attempting full model breadth.

**Tech Stack:** Julia, Rust, Tauri, React, TypeScript, JSON, Markdown

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-24-metrica-dual-track-design.md`
- Create: `docs/superpowers/plans/2026-04-24-metrica-foundation-plan.md`
- Create: `packages/.gitkeep`
- Create: `apps/.gitkeep`
- Create: `runtime/.gitkeep`
- Create: `tutorials/.gitkeep`
- Create: `datasets/.gitkeep`
- Create: `benchmarks/.gitkeep`
- Create: `scripts/.gitkeep`
- Create: `apps/metrica-desktop/README.md`
- Create: `runtime/metrica-runtime/README.md`
- Create: `packages/MetricaBase.jl/README.md`
- Create: `packages/MetricaLinear.jl/README.md`
- Create: `packages/MetricaOutput.jl/README.md`
- Create: `docs/architecture/runtime-protocol.md`
- Create: `docs/architecture/app-shell.md`

## Task 1: Create repository scaffold for the dual-track architecture

**Files:**
- Create: `packages/.gitkeep`
- Create: `apps/.gitkeep`
- Create: `runtime/.gitkeep`
- Create: `tutorials/.gitkeep`
- Create: `datasets/.gitkeep`
- Create: `benchmarks/.gitkeep`
- Create: `scripts/.gitkeep`

- [ ] **Step 1: Create the root directory scaffold**

Use `apply_patch` to add empty placeholder files:

```diff
*** Add File: packages/.gitkeep
+
*** Add File: apps/.gitkeep
+
*** Add File: runtime/.gitkeep
+
*** Add File: tutorials/.gitkeep
+
*** Add File: datasets/.gitkeep
+
*** Add File: benchmarks/.gitkeep
+
*** Add File: scripts/.gitkeep
+
```

- [ ] **Step 2: Verify the scaffold exists**

Run:

```powershell
Get-ChildItem -Force | Select-Object Name
```

Expected:

```text
apps
benchmarks
datasets
docs
packages
runtime
scripts
tutorials
README.md
Metrica.jl-计量经济学框架-完善版.md
```

- [ ] **Step 3: Commit the scaffold**

If the repository has been initialized with git, run:

```powershell
git add packages/.gitkeep apps/.gitkeep runtime/.gitkeep tutorials/.gitkeep datasets/.gitkeep benchmarks/.gitkeep scripts/.gitkeep
git commit -m "chore: add dual-track repository scaffold"
```

Expected:

```text
[main ...] chore: add dual-track repository scaffold
```

## Task 2: Document the desktop app and runtime boundaries

**Files:**
- Create: `apps/metrica-desktop/README.md`
- Create: `runtime/metrica-runtime/README.md`
- Create: `docs/architecture/app-shell.md`
- Create: `docs/architecture/runtime-protocol.md`

- [ ] **Step 1: Add the desktop shell README**

Create `apps/metrica-desktop/README.md` with:

```markdown
# Metrica Desktop

Cross-platform native desktop workbench for Metrica.

## Responsibilities

- Project workspace and navigation
- Data import and inspection
- Model configuration and execution triggers
- Result rendering and export
- Teaching-oriented explanations and warnings

## Non-Responsibilities

- Econometric estimation logic
- Julia package internals
- Numerical algorithm implementation
```

- [ ] **Step 2: Add the runtime bridge README**

Create `runtime/metrica-runtime/README.md` with:

```markdown
# Metrica Runtime

Bridge layer between the desktop application and Julia Core.

## Responsibilities

- Launch and manage Julia processes
- Accept structured task requests
- Return structured results and warnings
- Handle logging, cancellation, and failure propagation

## Non-Responsibilities

- UI rendering
- Econometric model semantics
- Direct user-facing workflow design
```

- [ ] **Step 3: Add the app shell architecture note**

Create `docs/architecture/app-shell.md` with:

```markdown
# App Shell

The desktop shell is a Tauri-based workbench with six first-phase areas:

- Home
- Project
- Data Inspector
- Model Builder
- Results
- Learn

The shell must consume structured result payloads and may not parse terminal summary text.
```

- [ ] **Step 4: Add the runtime protocol note**

Create `docs/architecture/runtime-protocol.md` with:

```markdown
# Runtime Protocol

First-phase actions:

- `inspect_dataset`
- `fit_model`
- `export_result`
- `explain_warning`

Every request must contain `task_id`, `action`, `project_context`, and action-specific payload.
Every response must contain `task_id`, `status`, `messages`, and optional `result_payload`.
```

- [ ] **Step 5: Verify the docs read cleanly**

Run:

```powershell
Get-Content -Raw 'apps/metrica-desktop/README.md'
Get-Content -Raw 'runtime/metrica-runtime/README.md'
Get-Content -Raw 'docs/architecture/app-shell.md'
Get-Content -Raw 'docs/architecture/runtime-protocol.md'
```

Expected:

```text
Each file contains concise boundary definitions with no TODO or placeholder text.
```

- [ ] **Step 6: Commit the boundary docs**

If git is initialized, run:

```powershell
git add apps/metrica-desktop/README.md runtime/metrica-runtime/README.md docs/architecture/app-shell.md docs/architecture/runtime-protocol.md
git commit -m "docs: define app shell and runtime boundaries"
```

Expected:

```text
[main ...] docs: define app shell and runtime boundaries
```

## Task 3: Define the initial Julia package responsibilities

**Files:**
- Create: `packages/MetricaBase.jl/README.md`
- Create: `packages/MetricaLinear.jl/README.md`
- Create: `packages/MetricaOutput.jl/README.md`

- [ ] **Step 1: Add the Base package responsibility note**

Create `packages/MetricaBase.jl/README.md` with:

```markdown
# MetricaBase.jl

Protocol kernel for the Metrica ecosystem.

## Responsibilities

- Abstract model and result types
- Shared public APIs such as `fit`, `coef`, `vcov`, `predict`
- Structured result semantics such as `glance`, `tidy`, and `augment`
- ModelFrame and preprocessing contracts
- Capability and warning protocols

## Non-Responsibilities

- OLS or other estimator implementations
- Robust covariance algorithms
- Rendering tables or HTML output
- Visualization or desktop logic
```

- [ ] **Step 2: Add the Linear package responsibility note**

Create `packages/MetricaLinear.jl/README.md` with:

```markdown
# MetricaLinear.jl

Reference linear-model implementation package for Metrica.

## First-phase scope

- OLS
- Shared result objects returned through the Base API
- Model fitting from formula plus table-like data

## Deferred scope

- IV
- GLS
- WLS beyond the architecture-validation stage
```

- [ ] **Step 3: Add the Output package responsibility note**

Create `packages/MetricaOutput.jl/README.md` with:

```markdown
# MetricaOutput.jl

Output and report layer for Metrica.

## Responsibilities

- Terminal summaries
- Structured table rendering
- Markdown, HTML, and LaTeX exports

## Constraint

This package must consume public structured results and may not depend on private OLS internals.
```

- [ ] **Step 4: Verify the package notes**

Run:

```powershell
Get-Content -Raw 'packages/MetricaBase.jl/README.md'
Get-Content -Raw 'packages/MetricaLinear.jl/README.md'
Get-Content -Raw 'packages/MetricaOutput.jl/README.md'
```

Expected:

```text
The package responsibilities are clear, non-overlapping, and aligned with the dual-track architecture.
```

- [ ] **Step 5: Commit the package notes**

If git is initialized, run:

```powershell
git add packages/MetricaBase.jl/README.md packages/MetricaLinear.jl/README.md packages/MetricaOutput.jl/README.md
git commit -m "docs: define initial package responsibilities"
```

Expected:

```text
[main ...] docs: define initial package responsibilities
```

## Task 4: Freeze the runtime request/response schema in documentation

**Files:**
- Modify: `docs/architecture/runtime-protocol.md`

- [ ] **Step 1: Expand the request schema**

Update `docs/architecture/runtime-protocol.md` to include:

```json
{
  "task_id": "uuid",
  "action": "fit_model",
  "project_context": {
    "project_id": "proj_001",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "/path/to/data.csv",
    "format": "csv"
  },
  "model_spec": {
    "model_type": "ols",
    "formula": "y ~ x1 + x2 + x3",
    "vcov": {
      "type": "classical"
    }
  },
  "options": {
    "drop_missing": true,
    "return_augment": true
  }
}
```

- [ ] **Step 2: Expand the response schema**

Update the same file to include:

```json
{
  "task_id": "uuid",
  "status": "success",
  "messages": [
    {
      "level": "info",
      "code": "ROWS_DROPPED",
      "text": "12 rows were removed due to missing values."
    }
  ],
  "artifacts": [],
  "result_payload": {
    "glance": {},
    "tidy": [],
    "augment_preview": [],
    "diagnostics": [],
    "warnings": []
  }
}
```

- [ ] **Step 3: Add the failure contract**

Update the same file to include:

```json
{
  "task_id": "uuid",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "SINGULAR_MATRIX",
      "text": "Model could not be estimated because the design matrix is singular.",
      "hint": "Check whether one predictor is a linear combination of others."
    }
  ]
}
```

- [ ] **Step 4: Verify the schema note**

Run:

```powershell
Get-Content -Raw 'docs/architecture/runtime-protocol.md'
```

Expected:

```text
The document contains explicit request, success response, and error response examples.
```

- [ ] **Step 5: Commit the schema documentation**

If git is initialized, run:

```powershell
git add docs/architecture/runtime-protocol.md
git commit -m "docs: freeze initial runtime schema"
```

Expected:

```text
[main ...] docs: freeze initial runtime schema
```

## Task 5: Define the first desktop MVP in writing

**Files:**
- Modify: `docs/architecture/app-shell.md`

- [ ] **Step 1: Add the first-phase page list**

Update `docs/architecture/app-shell.md` with:

```markdown
## MVP Pages

- Home
- Project
- Data Inspector
- Model Builder
- Results
- Learn
```

- [ ] **Step 2: Add the MVP acceptance criteria**

Update the same file with:

```markdown
## MVP Acceptance

The desktop alpha is successful if a user can:

1. Open a project
2. Import a dataset
3. Configure and run one OLS model
4. View structured results
5. Export a result summary
6. Receive readable warnings and error explanations
```

- [ ] **Step 3: Add the out-of-scope list**

Update the same file with:

```markdown
## Out of Scope for MVP

- Panel-model UI
- Multi-model comparison dashboards
- Cloud sync
- Plugin marketplace
- Full diagnostics suite
```

- [ ] **Step 4: Verify the MVP note**

Run:

```powershell
Get-Content -Raw 'docs/architecture/app-shell.md'
```

Expected:

```text
The app shell note clearly describes the first-phase pages, MVP acceptance, and out-of-scope features.
```

- [ ] **Step 5: Commit the MVP definition**

If git is initialized, run:

```powershell
git add docs/architecture/app-shell.md
git commit -m "docs: define desktop MVP"
```

Expected:

```text
[main ...] docs: define desktop MVP
```

## Self-Review

Spec coverage:

- Dual-track architecture is covered by Tasks 1-2.
- Package boundaries are covered by Task 3.
- Runtime communication protocol is covered by Task 4.
- Desktop MVP scope is covered by Task 5.

Placeholder scan:

- No TODO or TBD markers are present in the plan body.

Type consistency:

- `task_id`, `action`, `project_context`, `messages`, and `result_payload` naming is used consistently across the runtime contract tasks.

## Notes

- This workspace is currently not a git repository, so commit steps are conditional on initializing git first.
- The next execution cycle should implement the scaffold first, then the runtime and app shell placeholders, before writing any econometric model code.
