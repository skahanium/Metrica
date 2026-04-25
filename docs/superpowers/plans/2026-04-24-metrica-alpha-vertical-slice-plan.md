# Metrica Alpha 垂直切片实施计划

> **状态：已被后续真实实现计划细化。** 本文件保留为早期 alpha 垂直切片实施草案，其中 `fit_ols_demo` 与示例载荷路线不再作为当前实施依据。当前活跃实施计划为 `docs/superpowers/plans/2026-04-25-metrica-alpha-real-ols-full-chain-plan.md`。

> **面向代理工作者：** 须使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans，按任务逐步执行本计划。步骤使用复选框语法（`- [ ]`）跟踪。

**目标：** 交付第一条真实端到端 Metrica 切片：本地 CSV → OLS 执行 → 结构化 Runtime 载荷 → 桌面结果渲染。

**架构：** 本计划在既有三层上实现一条窄链路，不扩大范围。`packages/` 拥有第一条可执行 OLS 路径与结构化结果对象；`runtime/` 拥有请求/响应桥与面向进程的契约；`apps/` 拥有触发真实运行并渲染结构化结果的最小用户流。

**技术栈：** Julia、Rust、JSON、HTML、CSS、JavaScript

---

## 范围锚定

本计划仅执行以下文档所定义的切片：

- `docs/superpowers/specs/2026-04-24-metrica-alpha-vertical-slice-design.md`

不扩展到：

- 面板或 IV 工作
- 泛化的桌面架构整理
- 插件体系
- 云或同步流程

## 文件结构

- 修改：`packages/MetricaBase.jl/src/MetricaBase.jl`
- 创建：`packages/MetricaBase.jl/test/runtests.jl`
- 修改：`packages/MetricaLinear.jl/src/MetricaLinear.jl`
- 创建：`packages/MetricaLinear.jl/test/runtests.jl`
- 修改：`packages/MetricaOutput.jl/src/MetricaOutput.jl`
- 创建：`packages/MetricaOutput.jl/test/runtests.jl`
- 修改：`runtime/metrica-runtime/src/lib.rs`
- 修改：`runtime/metrica-runtime/src/main.rs`
- 创建：`apps/metrica-desktop/data/demo.csv`
- 修改：`apps/metrica-desktop/index.html`
- 修改：`apps/metrica-desktop/src/main.js`
- 修改：`apps/metrica-desktop/src/styles.css`
- 修改：`docs/architecture/runtime-protocol.md`

## 任务 1：使 `MetricaBase` 拥有最小结构化结果契约

**涉及文件：**
- 修改：`packages/MetricaBase.jl/src/MetricaBase.jl`
- 创建：`packages/MetricaBase.jl/test/runtests.jl`

- [ ] **步骤 1：编写会先失败的 Base 契约测试**

创建 `packages/MetricaBase.jl/test/runtests.jl`，内容为：

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

- [ ] **步骤 2：运行 Base 测试以验证加载/入口是否就绪**

运行：

```powershell
julia --project=D:\Metrica\packages\MetricaBase.jl -e "using Pkg; Pkg.test()"
```

预期：

```text
要么因当前契约已满足而立即通过，要么因缺少测试入口等原因失败。
```

- [ ] **步骤 3：若缺失则添加最小 Base 测试入口**

确保 `packages/MetricaBase.jl/src/MetricaBase.jl` 导出当前结构化契约，并保持公开名称稳定，以兼容 `Project.toml` 与测试加载：

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

# 既有类型定义仍为对外的最小契约
```

- [ ] **步骤 4：再次运行 Base 包测试**

运行：

```powershell
julia --project=D:\Metrica\packages\MetricaBase.jl -e "using Pkg; Pkg.test()"
```

预期：

```text
最小结构化契约测试通过。
```

- [ ] **步骤 5：记录当前阶段定位**

在 `packages/MetricaBase.jl/README.md` 增加一句简短说明：

```markdown
当前 alpha 角色：承载第一条真实垂直切片所需的最小结构化结果契约。
```

## 任务 2：使 `MetricaLinear` 返回类 OLS 的结构化切片结果

**涉及文件：**
- 修改：`packages/MetricaLinear.jl/src/MetricaLinear.jl`
- 创建：`packages/MetricaLinear.jl/test/runtests.jl`

- [ ] **步骤 1：编写会先失败的 Linear 测试**

创建 `packages/MetricaLinear.jl/test/runtests.jl`，内容为：

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

- [ ] **步骤 2：运行 Linear 测试以确认失败形态**

运行：

```powershell
julia --project=D:\Metrica\packages\MetricaLinear.jl -e "using Pkg; Pkg.test()"
```

预期：

```text
失败，因为 `fit_ols_demo` 尚不存在。
```

- [ ] **步骤 3：实现最小真实切片函数**

更新 `packages/MetricaLinear.jl/src/MetricaLinear.jl`，加入：

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

- [ ] **步骤 4：导出垂直切片入口**

更新模块 `export` 列表：

```julia
export OLSModel, OLSFitResult, SliceFitResult, PHASE_1_MODELS, fit_ols_demo
```

- [ ] **步骤 5：再次运行 Linear 测试**

运行：

```powershell
julia --project=D:\Metrica\packages\MetricaLinear.jl -e "using Pkg; Pkg.test()"
```

预期：

```text
通过：存在一条可执行的 OLS 切片路径并返回结构化结果。
```

## 任务 3：使 Runtime 序列化真实切片形状，而非仅 mock 载荷

**涉及文件：**
- 修改：`runtime/metrica-runtime/src/lib.rs`
- 修改：`runtime/metrica-runtime/src/main.rs`

- [ ] **步骤 1：编写会先失败的 Runtime 序列化测试**

将以下测试加入 `runtime/metrica-runtime/src/lib.rs`：

```rust
#[test]
fn success_payload_contains_glance_and_tidy_shapes() {
    let response = sample_success_response();
    let payload = response.result_payload.expect("result payload");
    assert!(payload.get("glance").is_some());
    assert!(payload.get("tidy").is_some());
}
```

- [ ] **步骤 2：运行 Runtime 测试**

运行：

```powershell
cargo test
```

预期：

```text
若当前载荷形状已满足要求则通过，否则因缺少字段断言失败。
```

- [ ] **步骤 3：添加垂直切片专用响应构造器**

更新 `runtime/metrica-runtime/src/lib.rs`，加入：

```rust
pub fn vertical_slice_success_response() -> TaskResponse {
    TaskResponse {
        task_id: "uuid".to_string(),
        status: "success".to_string(),
        messages: vec![Message {
            level: "info".to_string(),
            code: "ROWS_DROPPED".to_string(),
            text: "因缺失值已移除 2 行。".to_string(),
            hint: Some("拟合前请检查缺失列。".to_string()),
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
                    "title": "已删行",
                    "detail": "因缺失值已移除 2 行。"
                }
            ]
        })),
    }
}
```

- [ ] **步骤 4：将 CLI 接到垂直切片**

更新 `runtime/metrica-runtime/src/main.rs`，使 `"success"` 路径序列化 `vertical_slice_success_response()`，而非旧占位构造器。

- [ ] **步骤 5：再次运行 Runtime 测试**

运行：

```powershell
cargo test
```

预期：

```text
通过：垂直切片载荷已固定。
```

## 任务 4：在桌面壳中渲染真实结构化载荷

**涉及文件：**
- 创建： `apps/metrica-desktop/data/demo.csv`
- 修改： `apps/metrica-desktop/index.html`
- 修改： `apps/metrica-desktop/src/main.js`
- 修改： `apps/metrica-desktop/src/styles.css`

- [ ] **步骤 1：添加最小演示数据集**

创建 `apps/metrica-desktop/data/demo.csv`，内容为：

```csv
y,x1,x2
1,1,2
2,2,1
3,3,0
4,4,1
5,5,2
```

- [ ] **步骤 2：在纯 JavaScript 中加入会先失败的 UI 断言**

在实现渲染前，更新 `apps/metrica-desktop/src/main.js`：若缺少结果挂载点则抛出错误：

```javascript
const resultsMount = document.querySelector("[data-results-mount]");

if (!resultsMount) {
  throw new Error("缺少垂直切片渲染所需的结果挂载点。");
}
```

- [ ] **步骤 3：在 HTML 中加入结果挂载点**

在 `apps/metrica-desktop/index.html` 的 Results 卡片内更新为：

```html
<article class="card" id="results">
  <h3>Results</h3>
  <div data-results-mount></div>
</article>
```

- [ ] **步骤 4：渲染真实垂直切片载荷**

将 `apps/metrica-desktop/src/main.js` 替换为最小渲染器：

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
      title: "已删行",
      detail: "因缺失值已移除 2 行。"
    }
  ]
};

const resultsMount = document.querySelector("[data-results-mount]");

if (!resultsMount) {
  throw new Error("缺少垂直切片渲染所需的结果挂载点。");
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

- [ ] **步骤 5：为渲染结果添加最小样式**

追加到 `apps/metrica-desktop/src/styles.css`：

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

- [ ] **步骤 6：验证桌面壳文件结构**

运行：

```powershell
Get-ChildItem -Recurse -File 'D:\Metrica\apps\metrica-desktop' | Select-Object FullName
```

预期：

```text
桌面壳包含 `index.html`、`src/main.js`、`src/styles.css` 与 `data/demo.csv`。
```

## 任务 5：将协议文档与第一条真实垂直切片对齐

**涉及文件：**
- 修改： `docs/architecture/runtime-protocol.md`

- [ ] **步骤 1：追加短文说明当前可执行切片**

追加以下小节：

```markdown
## 当前可执行切片

第一条真实可执行切片为：

- 本地 CSV 输入
- `fit_model` 动作
- `ols` 模型类型
- 结构化的 `glance` 与 `tidy` 响应载荷
- 删行与拟合错误的警告/消息传播
```

- [ ] **步骤 2：验证协议说明**

运行：

```powershell
Get-Content -Raw 'D:\Metrica\docs\architecture\runtime-protocol.md'
```

预期：

```text
协议文档反映当前垂直切片契约，且不重复项目级架构叙述。
```

## 验证摘要

仅当以下检查均完成时，方可宣称切片就绪：

- 在 `runtime/metrica-runtime` 中 `cargo test` 通过
- 若环境中有 `julia`，则 `MetricaBase` 与 `MetricaLinear` 的包测试通过
- 桌面壳文件存在，且 Results 卡片具备真实结构化渲染挂载点
- 文档与切片保持一致，不重新引入重复的架构正文

## 说明

- 若环境中仍不可用 Julia，应先完成非 Julia 层，并明确报告缺失的验证项。
- 在该单一垂直切片实际工作之前，勿用更泛化的「alpha」计划替换本计划。
