# 审计整改实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复深度审计发现的 P0/P1 问题，使 Metrica 在 OLS→Output 主链路上达到数值正确、协议一致、进程可靠的标准。

**Architecture:** 按子系统分 4 个阶段：Julia 包正确性 → Runtime 可靠性 → 协议统一 → 前端修正。每个 Task 独立可验证，完成后主链路可信度提升一级。

**Tech Stack:** Julia 1.12 + Rust (tokio/axum) + React 19 + TypeScript 5 + Ant Design 5

---

## 文件结构

```
packages/MetricaLinear.jl/src/
  iv.jl                  ← MODIFY: 修正 2SLS 拟合值/残差/vcov 口径
  ols.jl                 ← MODIFY: 近奇异矩阵处理；WLS/GLS 诊断口径
  serialize.jl           ← MODIFY: tidy 字段名统一；augment 改行数组
  test/runtests.jl       ← MODIFY: 增加 IV/OLS/WLS 边界测试

packages/MetricaDiscrete.jl/src/
  logit.jl               ← MODIFY: cluster 使用过滤后数据；vcov 校验
  probit.jl              ← MODIFY: 同 logit
  poisson.jl             ← MODIFY: 同 logit + 整数计数检查

packages/MetricaBase.jl/src/
  MetricaBase.jl         ← MODIFY: 公式解析边界；MetricValue 允许 missing

runtime/metrica-runtime/src/
  julia_session.rs       ← MODIFY: 读线程 + 真实超时
  server.rs              ← MODIFY: 请求队列；路径安全；health 不阻塞
  lib.rs                 ← MODIFY: ID 白名单；模型注册表来源统一

scripts/
  julia_daemon.jl        ← MODIFY: 字段提取入 try；schema 校验

apps/metrica-desktop/src-react/
  components/App.tsx     ← MODIFY: 命令分流；字段无损传递
  services/commandParser.ts  ← MODIFY: 非模型命令不返回 modelSpec
  services/runtimeClient.ts  ← MODIFY: IV instruments 统一为数组
  components/ResultBlock.tsx ← MODIFY: 子组件传 props 不读全局
  components/TidyTable.tsx   ← MODIFY: 缺失统计量显示 —
  components/AugmentPreview.tsx ← MODIFY: 消费行数组
  types/protocol.ts      ← MODIFY: tidy/augment 字段对齐

docs/
  architecture/runtime-protocol.md ← MODIFY: 标注未实现能力
  SETUP.md               ← MODIFY: Julia 版本要求
```

---

## 阶段 1：Julia 包结果正确性（P0）

### Task 1: IV/2SLS 拟合值与残差口径修正

**Files:**
- Modify: `packages/MetricaLinear.jl/src/iv.jl:197-237`
- Modify: `packages/MetricaLinear.jl/src/iv.jl:234-237`（IVFitResult 构造）
- Test: `packages/MetricaLinear.jl/test/runtests.jl`

**目标:** 2SLS 的 fitted/residuals/R²/vcov 使用原始解释变量口径，而非第二阶段预测值。

- [ ] **Step 1: 写失败测试 — IV 结构残差口径**

在 `test/runtests.jl` 增加：
```julia
@testset "IV residual口径" begin
    # 使用 demo.csv 或构造数据
    result = fit(IVModel, "y ~ x1 + x2", csv_path; instruments=["z1"], endog=["x1"])
    # 手算: 用原始 X=[1,x1,x2] * beta 计算 fitted，对比 result.fitted
    # 断言: result.fitted ≈ [1 x1_actual x2_actual] * result.coefficients
    # 断言: result.residuals ≈ y - result.fitted
end
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/MetricaLinear.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: IV residual 口径测试失败

- [ ] **Step 3: 修正 iv.jl**

在第二阶段后，用原始解释变量计算 fitted/residuals：
```julia
# 第二阶段系数
X_second = hcat(X_exog, X_endog_hat)
coefficients = X_second \ y

# 修正: 用原始 X 计算拟合值和残差
X_original = hcat(X_exog, X_endog)
fitted = X_original * coefficients
residuals = y - fitted
```

vcov 改用标准 IV sandwich 公式（`X_original` 的投影版本），不直接复用 OLS `compute_vcov`。

存储 `X_original` 和 `X_second` 到 `IVFitResult`，predict 使用 `X_original`。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/MetricaLinear.jl && julia --project -e 'using Pkg; Pkg.test()'`
Expected: 全部测试通过

- [ ] **Step 5: Commit**

```bash
git add packages/MetricaLinear.jl/src/iv.jl packages/MetricaLinear.jl/test/runtests.jl
git commit -m "fix(iv): 修正 2SLS 拟合值/残差/vcov 口径为原始解释变量"
```

---

### Task 2: IV 识别条件与秩校验

**Files:**
- Modify: `packages/MetricaLinear.jl/src/iv.jl:150-195`
- Test: `packages/MetricaLinear.jl/test/runtests.jl`

**目标:** 欠识别、秩亏、自由度不足时返回结构化 ModelError，不崩溃。

- [ ] **Step 1: 写失败测试**

```julia
@testset "IV 欠识别" begin
    # instruments 数量 < endog 数量
    result = fit(IVModel, "y ~ x1", csv_path; instruments=["z1"], endog=["x1", "x2"])
    @test result isa MetricaBase.ModelError
    @test result.code == :underidentified_model
end

@testset "IV 秩亏" begin
    # Z 矩阵秩亏（完全共线工具变量）
    # ...
end
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 在 iv.jl 第一阶段前增加校验**

```julia
# 欠识别: 工具变量数 < 内生变量数
length(inst_syms) >= length(endog_syms) || return MetricaBase.ModelError(
    :underidentified_model, "模型欠识别",
    "工具变量数量 ($(length(inst_syms))) 少于内生变量数量 ($(length(endog_syms)))。",
    "请增加工具变量或减少内生变量。",
)

# 秩校验
rank(Z) >= size(X_second, 2) || return MetricaBase.ModelError(
    :weak_rank_condition, "设计矩阵秩不足",
    "工具变量矩阵的秩不足以识别模型参数。",
    "请检查工具变量是否线性相关，或增加有效工具变量。",
)

# 自由度
dof_val = nobs - ncoef
dof_val > 0 || return MetricaBase.ModelError(
    :insufficient_degrees_of_freedom, "自由度不足",
    "有效样本量 ($nobs) 不足以支撑参数个数 ($ncoef)。",
    "请减少参数或增加样本。",
)
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

### Task 3: 离散模型 cluster 使用过滤后数据

**Files:**
- Modify: `packages/MetricaDiscrete.jl/src/logit.jl:23-74`
- Modify: `packages/MetricaDiscrete.jl/src/probit.jl:17-67`
- Modify: `packages/MetricaDiscrete.jl/src/poisson.jl:16-65`
- Test: `packages/MetricaDiscrete.jl/test/runtests.jl`

**目标:** cluster vcov 使用 `prepare_model_data` 返回的过滤后 cluster 向量，不从原始 dataset 取。

- [ ] **Step 1: 写失败测试 — 含缺失值 + cluster**

```julia
@testset "离散模型 cluster 删样后一致" begin
    # 构造含缺失值的数据，指定 cluster_column
    result = fit(LogitModel, "y ~ x1 x2", data_with_missing; cluster_column=:group)
    # 断言: 未崩溃，cluster_vec 长度 == nobs（过滤后）
    @test result isa MetricaBase.ModelError || length(result.residuals) == result.glance.nobs
end
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 修正 logit.jl**

从 `prepare_model_data` 的返回值中取 `cluster_values`，不从 `dataset` 取：

```julia
prepared = MetricaLinear.prepare_model_data(...)
(_, model_frame, _, X, y, _, cluster_values, n_total, n_effective) = prepared

# cluster vcov 使用 cluster_values（已过滤），不从 dataset 取
if vcov == :cluster
    if isnothing(cluster_values)
        return MetricaBase.ModelError(:missing_cluster_variable, ...)
    end
    # 使用 cluster_values 而非 dataset[!, cluster_sym]
end
```

对 probit.jl、poisson.jl 做同样修正。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

### Task 4: 离散模型 unsupported vcov 显式报错

**Files:**
- Modify: `packages/MetricaDiscrete.jl/src/logit.jl:52-74`
- Modify: `packages/MetricaDiscrete.jl/src/probit.jl:49-72`
- Modify: `packages/MetricaDiscrete.jl/src/poisson.jl:47-70`
- Test: `packages/MetricaDiscrete.jl/test/runtests.jl`

**目标:** 不支持的 vcov 类型返回结构化 ModelError，不静默忽略。

- [ ] **Step 1: 写失败测试**

```julia
@testset "离散模型 unsupported vcov" begin
    result = fit(LogitModel, "y ~ x1", csv_path; vcov=:gmm)
    @test result isa MetricaBase.ModelError
    @test result.code == :unsupported_vcov
end
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 在 HC1/cluster 分支后增加 else**

```julia
elseif vcov == :cluster
    if isnothing(cluster_column)
        return MetricaBase.ModelError(:missing_cluster_variable, ...)
    end
    # ... cluster 计算
else
    return MetricaBase.ModelError(
        :unsupported_vcov,
        "协方差类型暂不支持",
        "离散模型当前仅支持 classical、HC1 与 cluster。",
        "请使用 :classical、:HC1 或 :cluster。",
    )
end
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

### Task 5: 协议字段统一 — tidy 字段名与 augment 行数组

**Files:**
- Modify: `packages/MetricaLinear.jl/src/serialize.jl:60-85`
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts:97-121`
- Modify: `apps/metrica-desktop/src-react/components/TidyTable.tsx:16-24`
- Modify: `apps/metrica-desktop/src-react/components/AugmentPreview.tsx:17-27`
- Test: `apps/metrica-desktop/src-react/__tests__/TidyTable.test.tsx`

**目标:** Julia 输出 canonical 字段名；augment 统一为行数组；前端直接消费。

- [ ] **Step 1: 写失败测试 — tidy 字段名**

```typescript
it('renders tidy with canonical field names (name/stderror/pvalue)', () => {
  const result: ModelResult = {
    glance: { model: 'ols', nobs: 7, dof: 4, metrics: {} },
    tidy: [
      { name: '(Intercept)', estimate: 2.91, stderror: 4.78, statistic: 0.61, pvalue: 0.57 },
    ],
    diagnostics: {},
    warnings: [],
  };
  const { container } = render(<TidyTable result={result} />);
  expect(screen.getByText('(Intercept)')).toBeDefined();
  expect(screen.getByText('2.910000')).toBeDefined();
});
```

- [ ] **Step 2: 运行确认失败（当前 normalize 会消费 name/stderror/pvalue 但类型不匹配）**

- [ ] **Step 3: 修正**

Julia `serialize.jl` — tidy 字段保持 `name/stderror/pvalue`（不改后端输出）。

前端 `protocol.ts` — TidyRow 改为兼容两种字段：
```typescript
export interface TidyRow {
  name?: string;
  term?: string;
  estimate: number;
  stderror?: number;
  std_error?: number;
  statistic: number;
  pvalue?: number;
  p_value?: number;
}
```

`TidyTable.tsx` normalize 保持不变（已兼容）。

Julia `serialize.jl` — augment 改为行数组：
```julia
if include_augment
    augment_table = MetricaBase.augment(result)
    max_preview = min(100, augment_table.nobs)
    augment_preview = [
        Dict(String(key) => values[i] for (key, values) in augment_table.columns)
        for i in 1:max_preview
    ]
    payload["result_payload"]["augment_preview"] = augment_preview
end
```

前端 `AugmentPreview.tsx` — 不再依赖 `.length` 判断行数组。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

## 阶段 2：Runtime 可靠性（P0）

### Task 6: Julia 会话真实超时

**Files:**
- Modify: `runtime/metrica-runtime/src/julia_session.rs:56-93,149-185`

**目标:** 超时判断不依赖循环内 read_line 阻塞返回，改用读线程 + channel。

- [ ] **Step 1: 重构 startup 阶段**

将 stdout 读取放入独立线程，通过 `mpsc::channel` 传递行：

```rust
let (tx, rx) = std::sync::mpsc::channel();
let reader_handle = std::thread::spawn(move || {
    let mut reader = BufReader::new(stdout);
    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => { let _ = tx.send(Err("EOF".into())); break; }
            Ok(_) => { let _ = tx.send(Ok(line.clone())); }
            Err(e) => { let _ = tx.send(Err(e.to_string())); break; }
        }
    }
});
```

startup 和 send_request 均从 `rx.recv_timeout(Duration::from_secs(...))` 读取，实现真实超时。

- [ ] **Step 2: 重构 send_request**

超时后 kill child 进程并尝试重启。

- [ ] **Step 3: 运行现有测试 + 手动验证超时场景**

- [ ] **Step 4: Commit**

---

### Task 7: 请求队列化，health 不阻塞

**Files:**
- Modify: `runtime/metrica-runtime/src/server.rs:260-263,59-63`

**目标:** Julia 请求通过 channel 串行发送，HTTP handler 不持有 Mutex 等待 I/O。

- [ ] **Step 1: 引入命令 channel**

```rust
type JuliaCommand = (String, Value, oneshot::Sender<Result<Value, String>>);
```

启动时 spawn 一个 Julia actor 任务，从 `mpsc::Receiver<JuliaCommand>` 读取并执行。

- [ ] **Step 2: 改造 dispatch_model_to_julia**

HTTP handler 通过 `mpsc::Sender` 发送命令，用 `oneshot::Receiver` 等待结果。外层 `tokio::time::timeout` 包裹。

- [ ] **Step 3: health 使用独立原子状态**

health handler 不再 lock Julia session，改为读取 `AtomicBool` 健康标志。

- [ ] **Step 4: 测试：并发请求不阻塞 health**

- [ ] **Step 5: Commit**

---

### Task 8: 路径安全加固

**Files:**
- Modify: `runtime/metrica-runtime/src/server.rs:479-480,586-587,850-853`
- Modify: `runtime/metrica-runtime/src/lib.rs`（增加 ID 白名单函数）

**目标:** task_id/run_id 白名单校验，路径 canonicalize 后确认在允许范围内。

- [ ] **Step 1: 增加 ID 白名单校验函数**

```rust
fn sanitize_id(id: &str) -> Result<String, String> {
    if id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        Ok(id.to_string())
    } else {
        Err(format!("ID '{}' 包含非法字符，仅允许 A-Za-z0-9_-。", id))
    }
}
```

- [ ] **Step 2: 在 persist_run_record / rerun / export 入口调用**

- [ ] **Step 3: working_dir canonicalize 后确认为绝对路径且不逃出项目根**

- [ ] **Step 4: 写测试：含 `../` 的 run_id 被拒绝**

- [ ] **Step 5: Commit**

---

### Task 9: Julia daemon 字段提取入 try

**Files:**
- Modify: `scripts/julia_daemon.jl:46-52,249-268`

**目标:** 缺少 id/action/params 的请求返回结构化 error，不崩溃 daemon。

- [ ] **Step 1: 将字段提取移入 try 块**

```julia
try
    id = get(req, "id", nothing)
    action = req["action"]
    params = get(req, "params", Dict{String,Any}())
    # ...
catch e
    # 有 id 则返回 error response；无 id 则输出通用 error
    error_response = isnothing(id) ?
        Dict("type" => "error", "message" => string(e)) :
        Dict("id" => id, "status" => "error", ...)
    println(JSON3.write(error_response))
end
```

- [ ] **Step 2: 测试：发送缺少 action 的 JSON，daemon 不退出**

- [ ] **Step 3: Commit**

---

## 阶段 3：数值稳定性（P1）

### Task 10: OLS 近奇异矩阵处理

**Files:**
- Modify: `packages/MetricaLinear.jl/src/ols.jl:196-213,249-309`
- Test: `packages/MetricaLinear.jl/test/runtests.jl`

**目标:** 近奇异设计矩阵返回结构化警告或错误，不产生 NaN/Inf 标准误。

- [ ] **Step 1: 写失败测试**

```julia
@testset "近共线 OLS" begin
    # x2 = 2*x1 + 微小噪声
    data = DataFrame(x1=rand(100), x2=2*rand(100) .+ 1e-10*randn(100), y=rand(100))
    result = fit(OLSModel, "y ~ x1 x2", data)
    # 断言: 返回 ModelError 或 result.warnings 包含近奇异警告
    @test result isa MetricaBase.ModelError || any(w.code == :near_singular_design for w in result.glance.warnings)
end
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 修正 validate_design**

使用 QR 分解判断有效秩，替代 `rank(X) == ncoef`。增加条件数阈值检查：
```julia
function validate_design(X, ncoef, nobs)
    F = qr(X)
    # 用对角线 R 矩阵的条件数判断
    r_diag = abs.(diag(F.R))
    cond = maximum(r_diag) / max(minimum(r_diag), eps())
    if cond > 1e12
        return ModelError(:near_singular_design, ...)
    end
    # ... 原有 rank/dof 检查
end
```

vcov 改用 `\` 求解替代 `inv(xtx)`。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

### Task 11: Poisson 整数计数检查

**Files:**
- Modify: `packages/MetricaDiscrete.jl/src/poisson.jl:29-35`
- Test: `packages/MetricaDiscrete.jl/test/runtests.jl`

**目标:** 非整数响应变量应返回结构化错误。

- [ ] **Step 1: 写失败测试**

```julia
@testset "Poisson 非整数响应" begin
    data = DataFrame(y=[0.2, 1.7, 3.1, 2.0], x1=rand(4))
    result = fit(PoissonModel, "y ~ x1", data)
    @test result isa MetricaBase.ModelError
    @test result.code == :invalid_count_response
end
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 在负值检查后增加整数检查**

```julia
if !all(y .== floor.(y))
    return MetricaBase.ModelError(
        :invalid_count_response, "响应变量不是计数数据",
        "Poisson 模型要求响应变量为非负整数。当前数据包含非整数值。",
        "请检查响应变量或考虑使用其他模型。",
    )
end
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

## 阶段 4：前端正确性（P1）

### Task 12: 命令分流 — 非模型命令不走 fit_model

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/App.tsx:71-128`
- Modify: `apps/metrica-desktop/src-react/services/commandParser.ts:116-140`
- Test: `apps/metrica-desktop/src-react/__tests__/commandParser.test.ts`

**目标:** `summarize`、`describe`、`tabulate` 等非模型命令不发送到 `/fit_model`。

- [ ] **Step 1: 写失败测试**

```typescript
it('summarize does not produce a ModelSpec', () => {
  const parsed = parse('summarize y x1');
  const spec = parseToModelSpec(parsed);
  expect('error' in spec).toBe(true);
});
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 在 commandParser 中增加 verb category 判断**

```typescript
const MODEL_VERBS = new Set(['regress','ivregress','gls','xtreg','xtivreg','logit','probit','poisson','ologit','mlogit','nbreg','did','eventstudy','ipw','psm','aipw','arima','var','dfuller','coint','svy']);

export function parseToModelSpec(parsed): ModelSpec | { error: string } {
  if (!MODEL_VERBS.has(parsed.verb)) {
    return { error: `命令 "${parsed.verb}" 暂不支持，请使用模型命令（如 regress）。` };
  }
  // ...
}
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

### Task 13: 命令字段无损传递

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/App.tsx:76-98`
- Modify: `apps/metrica-desktop/src-react/services/runtimeClient.ts:85-141`
- Test: `apps/metrica-desktop/src-react/__tests__/runtimeClient.test.ts`

**目标:** IV instruments、DID treated_column、Survey weights 等字段在全链路无损传递。

- [ ] **Step 1: 写失败测试 — IV instruments 数组传递**

```typescript
it('passes IV instruments as array without joining/splitting', () => {
  const req = buildFitModelRequest({
    datasetPath: 'data.csv',
    formula: 'y ~ x1',
    modelType: 'iv',
    instruments: 'z1, z2',
    endogColumns: 'x1',
    vcovType: 'classical',
  });
  expect(req.model_spec.instruments).toEqual(['z1', 'z2']);
});
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 修正 App.tsx**

将 `parseToModelSpec` 的完整输出传递给 `fitModel`，不在 App 中手工映射字段。`runtimeClient.ts` 对 instruments/endog_columns 始终按逗号 split。

DID 的 `treated_column` 统一：parser 输出 `treated_column`，App 传递 `treated_column`。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

### Task 14: 结果历史展示修正 — 子组件不读全局 lastResult

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/ResultBlock.tsx:51-65`
- Modify: `apps/metrica-desktop/src-react/components/DiscreteGlanceCards.tsx`
- Modify: `apps/metrica-desktop/src-react/components/OddsRatioTable.tsx`
- Modify: `apps/metrica-desktop/src-react/components/DIDResultCards.tsx`
- Modify: `apps/metrica-desktop/src-react/components/SurveyDesignPanel.tsx`
- Test: `apps/metrica-desktop/src-react/__tests__/ResultBlock.test.tsx`（新建）

**目标:** 所有结果展示子组件通过 props 接收 result，不读全局 store。

- [ ] **Step 1: 写失败测试**

```typescript
it('each history block shows its own result, not global lastResult', () => {
  const resultA = { glance: { model: 'ols', nobs: 10, dof: 8, metrics: {} }, tidy: [], diagnostics: {}, warnings: [] };
  const resultB = { glance: { model: 'logit', nobs: 20, dof: 18, metrics: {} }, tidy: [], diagnostics: {}, warnings: [] };
  // 渲染两个 ResultBlock，各自传不同 result
  // 断言: 第一个块显示 "OLS"，第二个显示 "LOGIT"
});
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 逐个组件改为 props 传递**

每个子组件增加 `result` prop，删除内部 `useModelStore` 调用。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

### Task 15: TidyTable 缺失统计量显示

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/TidyTable.tsx:16-24`
- Test: `apps/metrica-desktop/src-react/__tests__/TidyTable.test.tsx`

**目标:** 缺失的标准误/统计量/p 值显示 `—`，不显示 `0.0000`。

- [ ] **Step 1: 写失败测试**

```typescript
it('displays — for missing statistics, not 0', () => {
  const result = {
    glance: { model: 'ols', nobs: 3, dof: 1, metrics: {} },
    tidy: [{ name: 'x1', estimate: 1.5 }],  // 无 stderror/statistic/pvalue
    diagnostics: {}, warnings: [],
  };
  render(<TidyTable result={result} />);
  expect(screen.queryByText('0.0000')).toBeNull();
  expect(screen.getByText('—')).toBeDefined();
});
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 修正 normalizeRows**

```typescript
function normalizeRows(raw) {
  return raw.map((r) => ({
    term: (r.name ?? r.term ?? '') as string,
    estimate: r.estimate ?? null,
    std_error: r.stderror ?? r.std_error ?? null,
    statistic: r.statistic ?? null,
    p_value: r.pvalue ?? r.p_value ?? null,
  }));
}
```

COLUMNS 增加 render 处理 null：
```typescript
{ dataIndex: 'std_error', title: '标准误', align: 'right',
  render: (v: number | null) => v != null ? v.toFixed(6) : '—' },
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

---

## 阶段 5：文档对齐

### Task 16: 文档修正

**Files:**
- Modify: `docs/architecture/runtime-protocol.md:67-92`
- Modify: `SETUP.md:5`
- Modify: `packages/MetricaLinear.jl/README.md`

**目标:** 文档准确反映当前已实现能力。

- [ ] **Step 1: runtime-protocol.md — 标注 cancel/progress/session/env 为未实现**

在相关段落前加 `[未实现]` 标签，或移入"计划能力"小节。

- [ ] **Step 2: SETUP.md — Julia 版本改为 1.12+**

- [ ] **Step 3: MetricaLinear.jl/README.md — 更新已实现能力列表**

- [ ] **Step 4: Commit**

---

## 验收标准

完成全部 Task 后，以下场景应通过：

1. `regress y x1 x2` — 系数表显示正确，上下框风格一致
2. `ivregress y x1, endogenous(x1) instruments(z1)` — 结构残差口径正确
3. `logit y x1 x2, cluster(group)` — 含缺失值时不崩溃
4. 近共线 OLS — 返回结构化警告，不输出 NaN
5. 非整数 Poisson — 返回结构化错误
6. 并发两个模型请求 — health 仍可响应
7. 连续运行 OLS 和 logit — 历史块各自显示正确结果
8. `summarize y` — 不发送到 fit_model
