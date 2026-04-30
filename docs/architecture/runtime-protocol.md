# Runtime 协议

第一阶段动作：

- `inspect_dataset`
- `fit_model`
- `export_result`
- `explain_warning`

每个请求必须包含 `task_id`、`action`、`project_context` 以及动作相关载荷。  
每个响应必须包含 `task_id`、`status`、`messages`，以及可选的 `result_payload`。

## 传输方式

### 当前实现（手写 HTTP）

当前最小真实链路通过本地 HTTP 传输协议暴露 Runtime：

- 默认绑定：`127.0.0.1:47821`
- `POST /inspect_dataset`
- `OPTIONS /inspect_dataset`
- `POST /fit_model`
- `OPTIONS /fit_model`

该 HTTP 层只负责搬运结构化请求与响应，不承载计量逻辑本身。

### 目标架构（axum + 持久化 Julia）

升级为 axum HTTP 框架 + 持久化 Julia 进程：

- 保留现有 HTTP 端点兼容性
- 新增 `GET /health`（会话状态）
- 新增 `GET /session/env`（变量环境）

## Julia 进程模型

### 当前实现（进程/请求）

每次请求启动一个 Julia 子进程，用完即杀。优点是崩溃隔离清晰；缺点是每次冷启动 3-30 秒，无会话状态。

### 目标架构（持久化进程）

应用启动时拉起 Julia 进程，持久运行，通过 stdin/stdout JSON lines 通信：

```
┌──────────────────────────────────────────────┐
│              axum HTTP 服务                   │
│  POST /fit_model     → 转发到 Julia 会话     │
│  POST /inspect_dataset → 转发到 Julia 会话   │
│  GET  /health        → 返回会话状态          │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────┴───────────────────────────┐
│           Julia 会话管理器                    │
│  ┌────────────────────────────────────────┐  │
│  │  Julia 进程 (持久化)                    │  │
│  │  stdin  ← JSON Request (逐行)          │  │
│  │  stdout → JSON Response (逐行)         │  │
│  │  stderr → 日志/警告                    │  │
│  └────────────────────────────────────────┘  │
│  - 启动时加载 MetricaBase + MetricaLinear    │
│  - 首次预热完成后通知前端就绪                  │
│  - 支持 cancel 信号                          │
│  - 进程崩溃自动重启（最多 3 次）              │
└──────────────────────────────────────────────┘
```

### stdin/stdout JSON Lines 协议

```json
// 请求（Runtime → Julia stdin，每行一个 JSON）
{"id": "req-001", "action": "fit_model", "params": {"dataset_path": "data/demo.csv", "formula": "y ~ x1 + x2", "model_type": "ols", "vcov": "classical"}}

// 响应（Julia stdout → Runtime，每行一个 JSON）
{"id": "req-001", "status": "success", "payload": {"glance": {...}, "tidy": [...], "warnings": [...]}}

// 进度通知（Julia stdout → Runtime）
{"id": "req-001", "type": "progress", "message": "正在拟合模型...", "percent": 50}

// 取消信号（Runtime → Julia stdin）
{"id": "req-001", "action": "cancel"}
```

### 关键设计点

1. **预热阶段**：应用启动时拉起 Julia 并加载所有包。前端显示"正在初始化 Julia 环境..."的加载状态。预热完成后才可交互。
2. **会话持久化**：数据集加载后留在 Julia 内存中。第二次拟合不同公式不需要重新读取 CSV。
3. **超时与取消**：`tokio::time::timeout` 包裹 Julia 通信，超时后发送取消信号。前端可显示进度条。
4. **崩溃恢复**：Julia 进程意外退出时，Runtime 自动重启并通知前端"Julia 环境已重置"。

## 请求示例

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

## 成功响应示例

```json
{
  "task_id": "uuid",
  "status": "success",
  "messages": [
    {
      "level": "info",
      "code": "INFO_ROWS_DROPPED",
      "text": "因缺失值已移除 12 行。"
    }
  ],
  "artifacts": [],
  "result_payload": {
    "glance": {},
    "tidy": [],
    "augment_preview": [],
    "diagnostics": [],
    "warnings": [],
    "summary_text": "model=ols, nobs=128, dof=124, r2=0.81"
  }
}
```

## 数据检查成功响应示例

```json
{
  "task_id": "uuid",
  "status": "success",
  "messages": [],
  "result_payload": {
    "dataset_summary": {
      "row_count": 8,
      "column_count": 3
    },
    "columns": [
      {
        "name": "y",
        "inferred_type": "Int64",
        "missing_count": 0
      }
    ],
    "preview_rows": [
      {
        "y": 10,
        "x1": 1,
        "x2": 5
      }
    ],
    "warnings": []
  }
}
```

## 错误响应示例

```json
{
  "task_id": "uuid",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "NUM_SINGULAR_MATRIX",
      "text": "设计矩阵奇异，无法估计模型。",
      "hint": "请检查是否存在某一预测变量是其他变量的线性组合。"
    }
  ]
}
```

## 当前稳定基线

当前可执行端到端链路为：

- 本地 CSV 输入 → `fit_model` 动作 → `ols` 模型类型
- 结构化的 `glance` 与 `tidy` 响应载荷
- 删行与拟合错误的警告/消息传播

主设计与当前实施顺序见：

- `docs/superpowers/specs/2026-04-30-metrica-main-design.md`
- `docs/superpowers/plans/2026-04-30-metrica-current-plan.md`

当前实现路线补充约束：

- `fit_model` 必须通过 Runtime 调用 Julia 子进程真实执行
- 成功响应中的 `glance` 与 `tidy` 来自真实 OLS 拟合结果
- `fit_ols_demo` 或纯示例载荷不得作为当前完成标准

> 注意：成功响应中的 `augment_preview` 字段当前可为空数组，完整 `augment` 大表渲染在后续切片中启用。

当前默认基线为：

- `fit_model` 的默认模型类型是 `ols`
- 当前稳定协方差标签是 `classical`
- 后续新增 `WLS`、`HC1`、`cluster` 等能力时，必须保持现有成功/失败响应信封不变

## 后续高级能力的协议预留

后续高级功能只预留两层扩展方向：

### 第一层：受控自定义公式与选项

这层继续沿用当前 `fit_model` 信封：

- `model_spec.formula`
- `model_spec.vcov`
- `options.*`

扩展原则：

- 新能力优先通过新增结构化字段表达
- 不以自由命令字符串替代 `model_spec` / `options`
- Runtime 只搬运并校验 schema，不解释计量语义

### 第二层：受控自定义动作 / 自定义分析模板

这层允许未来在 `action` 上做受控扩展，例如：

- 新的白名单动作
- 以模板标识符驱动的分析流程

扩展约束：

- 新动作必须有明确 schema
- 模板必须映射到 Runtime 已注册的执行路径
- 响应仍返回结构化 `status`、`messages`、`result_payload`

### 当前明确不开放

当前协议不应扩展为：

- 任意 Julia 代码执行入口
- 任意 shell 命令执行入口
- 仅靠一段自由文本命令决定执行逻辑的产品接口
