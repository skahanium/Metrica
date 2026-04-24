# Document Boundaries

This file defines the responsibility of each major project document.

Its purpose is to prevent duplication, contradictory guidance, and scope bleed across docs.

## Rules

- Each document owns one level of decision-making.
- Higher-level documents define direction, not low-level payload details.
- Lower-level documents define subsystem details, not project strategy.
- Implementation plans describe ordered execution, not architecture rationale.
- If a detail already has an owning document, other docs should link to it instead of repeating it.

## Current Ownership

### `README.md`

Owns:

- repository identity
- current repo shape
- links to canonical docs

Does not own:

- architecture detail
- protocol payloads
- implementation task lists

### `AGENTS.md`

Owns:

- AI collaboration rules
- workflow expectations for agents and inline completion
- repository-wide execution discipline

Does not own:

- product design
- runtime schema details
- subsystem feature specs

### `Metrica.jl-计量经济学框架-完善版.md`

Owns:

- long-horizon product vision
- ecosystem direction
- strategic package decomposition

Does not own:

- current sprint scope
- runtime wire protocol examples
- desktop MVP execution detail

### `docs/superpowers/specs/2026-04-24-metrica-dual-track-design.md`

Owns:

- project-level dual-track architecture
- Core / Runtime / App layering
- cross-platform product positioning

Does not own:

- field-level runtime request and response schema
- page-by-page desktop MVP detail
- step-by-step implementation sequencing

References:

- `docs/architecture/runtime-protocol.md`
- `docs/architecture/app-shell.md`
- future vertical-slice specs

### `docs/architecture/runtime-protocol.md`

Owns:

- runtime action names
- request/response payload examples
- serialization boundary between Runtime and consumers

Does not own:

- project strategy
- package responsibilities
- desktop product scope beyond what is needed to explain payloads

### `docs/architecture/app-shell.md`

Owns:

- desktop workbench information architecture
- MVP pages
- MVP acceptance and out-of-scope boundaries

Does not own:

- runtime payload schema
- Core package semantics
- repository-wide delivery plan

### `docs/superpowers/plans/2026-04-24-metrica-foundation-plan.md`

Owns:

- first-stage execution order
- task sequencing
- concrete scaffold work items

Does not own:

- long-form architectural explanation
- deep subsystem rationale
- future-slice design decisions not yet scheduled

### `docs/superpowers/specs/2026-04-24-metrica-alpha-vertical-slice-design.md`

Owns:

- the first end-to-end executable slice
- exact user flow for dataset -> OLS -> structured result -> runtime -> desktop rendering
- boundaries for what the first real chain includes and excludes

Does not own:

- long-horizon roadmap
- all future model families
- general AI workflow policy

### `docs/superpowers/plans/2026-04-24-metrica-alpha-vertical-slice-plan.md`

Owns:

- execution order for the first real end-to-end slice
- task grouping across Core, Runtime, and App
- verification checkpoints for the first real chain

Does not own:

- high-level product architecture
- generic repository scaffolding work
- unrelated future milestones

## Editing Policy

When changing docs:

1. Update the owning document first.
2. In non-owning documents, replace repeated detail with a short pointer when feasible.
3. Do not copy request examples, page lists, or milestone definitions into multiple files.
4. If a new topic does not fit an existing document cleanly, create a new focused document and add it here.
