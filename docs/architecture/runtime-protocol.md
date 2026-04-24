# Runtime Protocol

First-phase actions:

- `inspect_dataset`
- `fit_model`
- `export_result`
- `explain_warning`

Every request must contain `task_id`, `action`, `project_context`, and action-specific payload.
Every response must contain `task_id`, `status`, `messages`, and optional `result_payload`.

## Request Example

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

## Success Response Example

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

## Error Response Example

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

## Alpha vertical slice (draft)

The first end-to-end slice aligns request/response `result_payload` with structured `glance` / `tidy` (and minimal warnings) as defined in:

- `docs/superpowers/specs/2026-04-24-metrica-alpha-vertical-slice-design.md`
- `docs/superpowers/plans/2026-04-24-metrica-alpha-vertical-slice-plan.md`

TODO: extend the success-response example in this document with the finalized field-level JSON for that slice once implemented in `runtime/metrica-runtime`.
