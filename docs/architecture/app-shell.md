# App Shell

The desktop shell is a Tauri-based workbench focused on a teaching-friendly econometrics workflow.

The shell must consume structured result payloads and may not parse terminal summary text.

## MVP Pages

- Home
- Project
- Data Inspector
- Model Builder
- Results
- Learn

## MVP Acceptance

The desktop alpha is successful if a user can:

1. Open a project
2. Import a dataset
3. Configure and run one OLS model
4. View structured results
5. Export a result summary
6. Receive readable warnings and error explanations

## Out of Scope for MVP

- Panel-model UI
- Multi-model comparison dashboards
- Cloud sync
- Plugin marketplace
- Full diagnostics suite

## Related Documents

- Runtime payloads are owned by `docs/architecture/runtime-protocol.md`.
- Project-level layering is owned by `docs/superpowers/specs/2026-04-24-metrica-dual-track-design.md`.
- The first executable end-to-end slice is owned by `docs/superpowers/specs/2026-04-24-metrica-alpha-vertical-slice-design.md`.
