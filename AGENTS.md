# Metrica AI Collaboration Protocol

This file is the primary project-level instruction source for any AI coding assistant working in this repository, including but not limited to Codex, Claude, Cursor, and other agentic or autocomplete-capable models.

If a tool supports a project instruction file, this repository should treat `AGENTS.md` as the canonical source. Tool-specific files may mirror or adapt this content, but they should not conflict with it.

## 1. Project Identity

Metrica is not only a Julia package collection. It is a dual-track product:

- `Metrica Core`: Julia econometrics packages and protocol layer
- `Metrica Runtime`: bridge layer between desktop software and Julia execution
- `Metrica App`: cross-platform native desktop workbench

All changes should preserve this separation.

## 2. Primary Goal

The project goal is to build a modern econometrics ecosystem that is:

- teaching-friendly
- architecturally consistent
- numerically reliable
- extensible
- able to grow into a native cross-platform product

Do not optimize for short-term feature count at the cost of protocol clarity or architectural stability.

## 3. Non-Negotiable Principles

All AI assistants working here must follow these rules.

### 3.1 Respect the architecture

Do not blur the boundaries below:

- `packages/` contains Julia package code and protocol definitions
- `runtime/` contains bridge and execution-management logic
- `apps/` contains desktop application code
- `docs/`, `tutorials/`, `datasets/`, and `benchmarks/` contain supporting assets, not core implementation logic

UI code must not contain econometric logic.
Core package code must not depend on GUI details.
Runtime code must not become a second business-logic layer.

### 3.2 Structure before feature count

Prefer stable interfaces, clear boundaries, and structured outputs over quickly adding many models or pages.

When in doubt:

- freeze interfaces first
- implement the smallest useful vertical slice
- verify the slice end to end

### 3.3 Structured results over display text

Do not build downstream behavior on top of parsing printed summaries.
Any result that may be consumed by docs, notebooks, exports, or the desktop app should be represented as structured data.

Preferred public result concepts include:

- `glance`
- `tidy`
- `augment`
- structured warnings
- structured diagnostics

### 3.4 Teaching experience is a core requirement

Do not treat teaching-friendly behavior as optional polish.
Missing-value handling, sample-size changes, variable-role clarity, and readable warnings are first-class product requirements.

### 3.5 No silent invention

Do not fabricate:

- APIs that are not defined
- files that do not exist
- benchmark or test results that were not run
- unsupported product capabilities

If something is uncertain, state the assumption explicitly in code comments, docs, or the completion summary.

## 4. Required Work Sequence

Unless the user explicitly asks for a tiny isolated edit, follow this sequence.

### Phase 1: Understand the local truth

Before proposing or editing:

- inspect the relevant files
- inspect nearby docs
- identify the active subsystem
- align with existing repository direction

Do not guess repository structure if it can be read directly.

### Phase 2: Design before implementation

For any substantial feature, architectural change, workflow change, or new subsystem:

- define the scope
- identify boundaries
- choose the smallest viable vertical slice
- document the intended behavior before broad implementation

If the repository already contains a design or plan document for the work, follow it.
If not, create one before implementing broad changes.

### Phase 3: Implement minimally

Implement the narrowest change that satisfies the current milestone.

Avoid:

- speculative abstractions
- premature generalization
- side quests
- broad refactors unrelated to the current slice

### Phase 4: Verify before claiming success

Do not claim a task is done until you verify the relevant layer.

Examples:

- docs changed: verify paths, references, and consistency
- runtime schema changed: verify examples and naming consistency
- package code changed: run targeted tests where possible
- UI changed: verify the affected flow or at minimum the buildable structure

If verification was not possible, say so plainly.

### Phase 5: Leave the repo clearer

A completed change should improve at least one of:

- clarity
- structure
- documentation
- test coverage
- consistency of naming or boundaries

## 5. Rules for Agentic Flows

These rules apply to long-running agents and multi-step assistants.

### 5.1 Prefer explicit plans for substantial work

If the change touches multiple directories, interfaces, or subsystems, first create or update a written plan in `docs/`.

### 5.2 Make assumptions visible

When proceeding without user confirmation, record assumptions in one of:

- design doc
- implementation plan
- final summary
- short inline note where appropriate

### 5.3 Do not hide tradeoffs

If a decision affects future architecture, state the tradeoff clearly instead of burying it in code.

### 5.4 One concern per unit

Prefer small, focused files and modules with one clear responsibility.
Avoid giant mixed-responsibility files when introducing new code.

## 6. Rules for Tab Completion and Small Inline Suggestions

These rules apply even when the model is only offering autocomplete-like edits.

### 6.1 Match local patterns

Autocomplete must follow the naming, layout, and style already established in the active directory.
Do not inject a new style, framework pattern, or architectural assumption into unrelated code.

### 6.2 Do not smuggle architecture changes

Tab completion must not quietly introduce:

- new layers
- hidden dependencies
- cross-module shortcuts
- ad hoc configuration systems

Small suggestions must stay local unless the user explicitly asks for a broader change.

### 6.3 Prefer explicitness over magic

When completing code:

- choose readable names
- avoid opaque helper chains
- avoid reflection-heavy or "clever" patterns unless already established

### 6.4 Do not leave broken placeholders

Do not insert:

- `TODO`
- `TBD`
- fake implementations
- placeholder return values
- comments like "implement later"

unless the user explicitly asks for scaffolding and knows the code is incomplete.

## 7. Repository-Specific Direction

### 7.1 Current priority

The current repository direction is:

- platform-first architecture
- direct multi-package layout
- alpha validated by `Base -> OLS -> Output`
- desktop app and runtime planned in parallel

Work should support this direction unless the user explicitly changes strategy.

### 7.2 Core package expectations

`MetricaBase.jl` should define shared protocol, types, interfaces, structured results, model-frame semantics, and warning capability patterns.

It should not become a dumping ground for:

- estimator implementations
- UI logic
- output rendering internals
- heavyweight algorithm families unrelated to the protocol layer

### 7.3 Runtime expectations

`runtime/` should focus on:

- process orchestration
- environment management
- request/response schema handling
- logging and cancellation

It should not duplicate econometric logic that belongs in Julia packages.

### 7.4 App expectations

`apps/` should focus on:

- project workspace flows
- data import and inspection
- model configuration
- results presentation
- exports
- teaching-oriented explanations

It should consume structured outputs, not parse terminal text.

## 8. Documentation Rules

Any significant architectural or workflow change should update the relevant docs.

Prefer these locations:

- design docs: `docs/superpowers/specs/`
- implementation plans: `docs/superpowers/plans/`
- subsystem notes: `docs/architecture/`

When code changes invalidate an existing document, update the document in the same work session if feasible.

## 9. Testing and Validation Rules

AI assistants should prefer targeted validation over no validation.

Minimum expectations:

- verify file paths exist after creating docs or scaffolding
- verify naming consistency across protocol examples
- run focused tests for changed code when available
- avoid claiming broad correctness from narrow checks

For numerical or econometric code, prioritize:

- deterministic tests
- result-shape tests
- cross-tool alignment tests when available
- edge cases around missing data, singularity, and sample changes

## 10. Change Control Rules

Do not make unrelated edits.
Do not reformat large unrelated surfaces unless explicitly requested.
Do not rename or move files without necessity.
Do not overwrite user-authored work just to simplify the task.

If you encounter conflicting local changes:

- stop
- preserve the existing work
- explain the conflict clearly

## 11. Definition of Done

A task is only done when all applicable items are true:

- the change aligns with the repository architecture
- the smallest intended scope is implemented
- relevant docs are updated
- relevant validation was performed, or the limitation was stated
- no placeholder logic was silently left behind
- the result is understandable by the next human or agent

## 12. Preferred Output Style for AI Assistants

When reporting completed work:

- summarize the actual change
- mention verification performed
- mention important assumptions or remaining gaps
- keep the summary concise and concrete

Avoid exaggerated confidence.
Avoid saying something is production-ready unless it has truly been validated to that level.

## 13. Instruction Priority

If multiple instruction files exist:

1. direct user request
2. repository architecture and active design docs
3. this `AGENTS.md`
4. tool-specific adaptation files such as `CLAUDE.md`, `.cursorrules`, or editor settings

Tool-specific files should refine this file for compatibility, not override the project direction.
