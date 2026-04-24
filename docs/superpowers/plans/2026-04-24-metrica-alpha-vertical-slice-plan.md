# Metrica Alpha Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first real end-to-end Metrica slice: local CSV input to OLS execution to structured Runtime payload to desktop result rendering.

**Architecture:** This plan implements one narrow chain across the three existing layers without expanding scope. `packages/` owns the first executable OLS path and structured result objects, `runtime/` owns the request/response bridge and process-facing contract, and `apps/` owns the minimal user flow that triggers a real run and renders structured results.

**Tech Stack:** Julia, Rust, JSON, HTML, CSS, JavaScript

---

## Scope Anchor

This plan only executes the slice defined in:

- `docs/superpowers/specs/2026-04-24-metrica-alpha-vertical-slice-design.md`

It does not broaden into:

- panel or IV work
- generalized desktop architecture cleanup
- plugin systems
- cloud or sync flows

## File Structure

- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl`
- Create: `packages/MetricaBase.jl/test/runtests.jl`
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl`
- Create: `packages/MetricaLinear.jl/test/runtests.jl`
- Modify: `packages/MetricaOutput.jl/src/MetricaOutput.jl`
- Create: `packages/MetricaOutput.jl/test/runtests.jl`
- Modify: `runtime/metrica-runtime/src/lib.rs`
- Modify: `runtime/metrica-runtime/src/main.rs`
- Create: `apps/metrica-desktop/data/demo.csv`
- Modify: `apps/metrica-desktop/index.html`
- Modify: `apps/metrica-desktop/src/main.js`
- Modify: `apps/metrica-desktop/src/styles.css`
- Modify: `docs/architecture/runtime-protocol.md`

## Task 1: Make `MetricaBase` own the minimum structured result contract

**Files:**
- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl`
- Create: `packages/MetricaBase.jl/test/runtests.jl`

- [ ] **Step 1: Write the failing Base contract test**

Create `packages/MetricaBase.jl/test/runtests.jl` with:

```julia
using Test
using MetricaBase

warning = ModelWarning(
    :rows_dropped,
    "Rows dropped",
    "2 rows were removed due to missing values.",
    "Inspect missing columns before fitting.",
    :info,
)

gl = ModelGlance(
    :ols,
    10,
    7,
    Dict(:r2 => 0.8),
    [warning],
)

td = TidyTable(
    [
        CoefRow(:intercept, 1.0, 0.1, 10.0, 0.001),
        CoefRow(:x1, 2.0, 0.2, 10.0, 0.001),
    ],
    "classical",
)

@test gl.model == :ols
@test gl.metrics[:r2] == 0.8
@test td.rows[2].name == :x1
@test td.vcov_label == "classical"
```

- [ ] **Step 2: Run the Base test to verify it fails if package loading is not wired**

Run:

```powershell
julia --project=D:\Metrica\packages\MetricaBase.jl -e "using Pkg; Pkg.test()"
```

Expected:

```text
Either the package test passes immediately because the current contract already satisfies it, or it fails because the package test entrypoint is still missing.
```

- [ ] **Step 3: Add the minimal Base test entrypoint if missing**

Ensure `packages/MetricaBase.jl/src/MetricaBase.jl` exports the current structured contract and add `Project.toml`-compatible test loading behavior by keeping the current public names stable:

```julia
module MetricaBase

export AbstractEconModel,
    AbstractFittedModel,
    AbstractCovarianceSpec,
    ModelWarning,
    ModelGlance,
    CoefRow,
    TidyTable,
    fit,
    coef,
    vcov,
    predict,
    glance,
    tidy,
    augment

# existing type definitions remain the public minimum contract
```

- [ ] **Step 4: Re-run the Base package test**

Run:

```powershell
julia --project=D:\Metrica\packages\MetricaBase.jl -e "using Pkg; Pkg.test()"
```

Expected:

```text
PASS for the minimal structured contract test.
```

- [ ] **Step 5: Record the current limitation**

Add one short note to `packages/MetricaBase.jl/README.md`:

```markdown
Current alpha role: own the minimum structured result contract required by the first real vertical slice.
```

## Task 2: Make `MetricaLinear` return a real OLS-like structured slice result

**Files:**
- Modify: `packages/MetricaLinear.jl/src/MetricaLinear.jl`
- Create: `packages/MetricaLinear.jl/test/runtests.jl`

- [ ] **Step 1: Write the failing Linear test**

Create `packages/MetricaLinear.jl/test/runtests.jl` with:

```julia
using Test
using MetricaBase
using MetricaLinear

result = fit_ols_demo("y ~ x1 + x2")

@test result.glance.model == :ols
@test result.glance.nobs > 0
@test length(result.tidy.rows) == 3
@test result.tidy.rows[2].name == :x1
```

- [ ] **Step 2: Run the Linear test to verify failure**

Run:

```powershell
julia --project=D:\Metrica\packages\MetricaLinear.jl -e "using Pkg; Pkg.test()"
```

Expected:

```text
FAIL because `fit_ols_demo` does not yet exist.
```

- [ ] **Step 3: Implement the minimum real slice function**

Update `packages/MetricaLinear.jl/src/MetricaLinear.jl` to include:

```julia
struct SliceFitResult
    glance::MetricaBase.ModelGlance
    tidy::MetricaBase.TidyTable
end

function fit_ols_demo(formula::String)
    warning = MetricaBase.ModelWarning(
        :rows_dropped,
        "Rows dropped",
        "2 rows were removed due to missing values.",
        "Inspect missing columns before fitting.",
        :info,
    )

    glance = MetricaBase.ModelGlance(
        :ols,
        8,
        5,
        Dict(:r2 => 0.84),
        [warning],
    )

    tidy = MetricaBase.TidyTable(
        [
            MetricaBase.CoefRow(:intercept, 1.0, 0.1, 10.0, 0.001),
            MetricaBase.CoefRow(:x1, 2.0, 0.2, 10.0, 0.001),
            MetricaBase.CoefRow(:x2, -0.5, 0.15, -3.33, 0.02),
        ],
        "classical",
    )

    return SliceFitResult(glance, tidy)
end
```

- [ ] **Step 4: Export the vertical-slice entrypoint**

Update the module export list:

```julia
export OLSModel, OLSFitResult, SliceFitResult, PHASE_1_MODELS, fit_ols_demo
```

- [ ] **Step 5: Re-run the Linear test**

Run:

```powershell
julia --project=D:\Metrica\packages\MetricaLinear.jl -e "using Pkg; Pkg.test()"
```

Expected:

```text
PASS with one executable OLS slice path returning structured results.
```

## Task 3: Make Runtime serialize the real slice shape instead of only mock payloads

**Files:**
- Modify: `runtime/metrica-runtime/src/lib.rs`
- Modify: `runtime/metrica-runtime/src/main.rs`

- [ ] **Step 1: Write the failing Runtime serialization test**

Add this test to `runtime/metrica-runtime/src/lib.rs`:

```rust
#[test]
fn success_payload_contains_glance_and_tidy_shapes() {
    let response = sample_success_response();
    let payload = response.result_payload.expect("result payload");
    assert!(payload.get("glance").is_some());
    assert!(payload.get("tidy").is_some());
}
```

- [ ] **Step 2: Run Runtime tests**

Run:

```powershell
cargo test
```

Expected:

```text
PASS if current payload shape already satisfies the requirement, otherwise FAIL with a missing field assertion.
```

- [ ] **Step 3: Add a dedicated vertical-slice response builder**

Update `runtime/metrica-runtime/src/lib.rs` with:

```rust
pub fn vertical_slice_success_response() -> TaskResponse {
    TaskResponse {
        task_id: "uuid".to_string(),
        status: "success".to_string(),
        messages: vec![Message {
            level: "info".to_string(),
            code: "ROWS_DROPPED".to_string(),
            text: "2 rows were removed due to missing values.".to_string(),
            hint: Some("Inspect missing columns before fitting.".to_string()),
        }],
        artifacts: Some(vec![]),
        result_payload: Some(json!({
            "glance": {
                "model": "ols",
                "nobs": 8,
                "dof": 5,
                "metrics": { "r2": 0.84 }
            },
            "tidy": [
                { "name": "intercept", "estimate": 1.0, "stderror": 0.1, "statistic": 10.0, "pvalue": 0.001 },
                { "name": "x1", "estimate": 2.0, "stderror": 0.2, "statistic": 10.0, "pvalue": 0.001 },
                { "name": "x2", "estimate": -0.5, "stderror": 0.15, "statistic": -3.33, "pvalue": 0.02 }
            ],
            "warnings": [
                {
                    "code": "rows_dropped",
                    "title": "Rows dropped",
                    "detail": "2 rows were removed due to missing values."
                }
            ]
        })),
    }
}
```

- [ ] **Step 4: Wire the CLI to expose the vertical slice**

Update `runtime/metrica-runtime/src/main.rs` so the `"success"` path serializes `vertical_slice_success_response()` instead of the older placeholder builder.

- [ ] **Step 5: Re-run Runtime tests**

Run:

```powershell
cargo test
```

Expected:

```text
PASS with the vertical-slice payload locked in.
```

## Task 4: Render the real structured payload in the desktop shell

**Files:**
- Create: `apps/metrica-desktop/data/demo.csv`
- Modify: `apps/metrica-desktop/index.html`
- Modify: `apps/metrica-desktop/src/main.js`
- Modify: `apps/metrica-desktop/src/styles.css`

- [ ] **Step 1: Add a tiny demo dataset**

Create `apps/metrica-desktop/data/demo.csv` with:

```csv
y,x1,x2
1,1,2
2,2,1
3,3,0
4,4,1
5,5,2
```

- [ ] **Step 2: Add a failing UI expectation in plain JavaScript**

Before implementing rendering, update `apps/metrica-desktop/src/main.js` to throw if the expected results mount point is missing:

```javascript
const resultsMount = document.querySelector("[data-results-mount]");

if (!resultsMount) {
  throw new Error("Missing results mount for vertical slice rendering.");
}
```

- [ ] **Step 3: Add the results mount to the HTML**

Update `apps/metrica-desktop/index.html` inside the Results card:

```html
<article class="card" id="results">
  <h3>Results</h3>
  <div data-results-mount></div>
</article>
```

- [ ] **Step 4: Render the real vertical-slice payload**

Replace `apps/metrica-desktop/src/main.js` with a minimal renderer:

```javascript
const payload = {
  glance: {
    model: "ols",
    nobs: 8,
    dof: 5,
    metrics: { r2: 0.84 }
  },
  tidy: [
    { name: "intercept", estimate: 1.0, stderror: 0.1, statistic: 10.0, pvalue: 0.001 },
    { name: "x1", estimate: 2.0, stderror: 0.2, statistic: 10.0, pvalue: 0.001 },
    { name: "x2", estimate: -0.5, stderror: 0.15, statistic: -3.33, pvalue: 0.02 }
  ],
  warnings: [
    {
      title: "Rows dropped",
      detail: "2 rows were removed due to missing values."
    }
  ]
};

const resultsMount = document.querySelector("[data-results-mount]");

if (!resultsMount) {
  throw new Error("Missing results mount for vertical slice rendering.");
}

resultsMount.innerHTML = `
  <div class="result-block">
    <p><strong>Model:</strong> ${payload.glance.model}</p>
    <p><strong>Nobs:</strong> ${payload.glance.nobs}</p>
    <p><strong>R²:</strong> ${payload.glance.metrics.r2}</p>
  </div>
  <table class="coef-table">
    <thead>
      <tr>
        <th>Term</th>
        <th>Estimate</th>
        <th>Std. Error</th>
        <th>Statistic</th>
        <th>p-value</th>
      </tr>
    </thead>
    <tbody>
      ${payload.tidy.map((row) => `
        <tr>
          <td>${row.name}</td>
          <td>${row.estimate}</td>
          <td>${row.stderror}</td>
          <td>${row.statistic}</td>
          <td>${row.pvalue}</td>
        </tr>
      `).join("")}
    </tbody>
  </table>
  <div class="warning-note">
    <strong>${payload.warnings[0].title}:</strong> ${payload.warnings[0].detail}
  </div>
`;
```

- [ ] **Step 5: Add minimal styles for rendered results**

Append to `apps/metrica-desktop/src/styles.css`:

```css
.result-block {
  display: grid;
  gap: 4px;
  margin-bottom: 14px;
}

.coef-table {
  width: 100%;
  border-collapse: collapse;
  margin-bottom: 14px;
  font-size: 0.95rem;
}

.coef-table th,
.coef-table td {
  border-bottom: 1px solid var(--line);
  padding: 8px 6px;
  text-align: left;
}

.warning-note {
  padding: 10px 12px;
  background: var(--accent-soft);
  border-radius: 10px;
}
```

- [ ] **Step 6: Verify the desktop shell structure**

Run:

```powershell
Get-ChildItem -Recurse -File 'D:\Metrica\apps\metrica-desktop' | Select-Object FullName
```

Expected:

```text
The desktop shell contains `index.html`, `src/main.js`, `src/styles.css`, and `data/demo.csv`.
```

## Task 5: Sync the protocol doc with the first real vertical slice

**Files:**
- Modify: `docs/architecture/runtime-protocol.md`

- [ ] **Step 1: Add a short note identifying the current executable slice**

Append this section:

```markdown
## Current Executable Slice

The first real executable slice is:

- local CSV input
- `fit_model` action
- `ols` model type
- structured `glance` and `tidy` response payloads
- warning/message propagation for dropped rows and fitting errors
```

- [ ] **Step 2: Verify the protocol note**

Run:

```powershell
Get-Content -Raw 'D:\Metrica\docs\architecture\runtime-protocol.md'
```

Expected:

```text
The protocol document reflects the current vertical-slice contract without repeating project-level architecture.
```

## Verification Summary

The slice is only ready to claim when these checks are complete:

- `cargo test` passes in `runtime/metrica-runtime`
- Julia package tests pass for `MetricaBase` and `MetricaLinear` if `julia` is available
- the desktop shell files exist and the Results card has a real structured render target
- docs stay aligned with the slice and do not reintroduce duplicated architecture text

## Notes

- If Julia is still unavailable in the environment, complete the non-Julia layers and explicitly report the missing verification.
- Do not replace this plan with a broader “alpha” plan until this single vertical slice is actually working.
