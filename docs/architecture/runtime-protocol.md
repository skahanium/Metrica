# Runtime 协议

## 动作列表

### 第一阶段动作（S1/S2）

- `inspect_dataset`
- `query_dataset`
- `fit_model`
- `transform`

### S3 项目系统动作

- `save_project` — 保存项目清单到 `.metrica/project.json`
- `load_project` — 从 `.metrica/project.json` 加载项目清单
- `list_runs` — 列出 `.metrica/runs/` 下的所有运行记录
- `rerun_task` — 根据历史运行记录重新执行任务
- `export_report` — 导出运行报告（Markdown / CSV）

每个请求必须包含 `task_id`、`action`、`project_context` 以及动作相关载荷。  
每个响应必须包含 `task_id`、`status`、`messages`，以及可选的 `result_payload`。

## 传输方式

### 当前实现（axum HTTP）

当前链路通过 axum HTTP 框架暴露 Runtime：

- 默认绑定：`127.0.0.1:47821`
- `POST /inspect_dataset`
- `OPTIONS /inspect_dataset`
- `POST /query_dataset`
- `OPTIONS /query_dataset`
- `POST /fit_model`
- `OPTIONS /fit_model`
- `POST /transform`
- `OPTIONS /transform`
- `POST /export_report`
- `OPTIONS /export_report`
- `GET /health`（会话状态）
- `GET /session/env`（变量环境）

该 HTTP 层只负责搬运结构化请求与响应，不承载计量逻辑本身。

## Julia 进程模型

### 当前实现（持久化进程）

应用启动时拉起 Julia 进程，持久运行，通过 stdin/stdout JSON lines 通信：

```
┌──────────────────────────────────────────────┐
│              axum HTTP 服务                   │
│  POST /fit_model     → 转发到 Julia 会话     │
│  POST /inspect_dataset → 转发到 Julia 会话   │
│  POST /query_dataset → 转发到 Julia 会话     │
│  POST /transform     → 转发到 Julia 会话      │
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
│  - [计划] 支持 cancel 信号                    │
│  - 进程崩溃自动重启（最多 3 次）              │
└──────────────────────────────────────────────┘
```

### stdin/stdout JSON Lines 协议

```json
// 请求（Runtime → Julia stdin，每行一个 JSON）
{"id": "req-001", "action": "fit_model", "params": {"dataset_path": "data/demo.csv", "formula": "y ~ x1 + x2", "model_type": "ols", "vcov": "classical"}}

{"id": "req-002", "action": "query_dataset", "params": {"dataset_path": "data/demo.csv", "kind": "summarize", "variables": ["y", "x1"], "limit": 200}}

// 响应（Julia stdout → Runtime，每行一个 JSON）
{"id": "req-001", "status": "success", "payload": {"glance": {...}, "tidy": [...], "warnings": [...]}}

// [计划] 进度通知（Julia stdout → Runtime）
// {"id": "req-001", "type": "progress", "message": "正在拟合模型...", "percent": 50}

// [计划] 取消信号（Runtime → Julia stdin）
// {"id": "req-001", "action": "cancel"}
```

### 关键设计点

1. **预热阶段**：应用启动时拉起 Julia 并加载所有包。前端显示"正在初始化 Julia 环境..."的加载状态。预热完成后才可交互。
2. **会话持久化**：数据集加载后留在 Julia 内存中。第二次拟合不同公式不需要重新读取 CSV。
3. **超时**：Julia 通信使用读线程 + channel 实现真实超时。超时后 kill 进程并返回错误。[计划] 取消信号和进度条尚未实现。
4. **崩溃恢复**：Julia 进程意外退出时，Runtime 自动重启并通知前端"Julia 环境已重置"。
5. **只读数据命令独立通道**：`describe`、`browse`、`summarize`、`tabulate` 统一走 `query_dataset`，不复用 `fit_model`，也不写模型运行记录。

## 请求示例

### 数据检查请求

`inspect_dataset` 可通过 `options.preview_rows` 请求返回指定数量的 `preview_rows`。桌面端“查看全部数据”会请求足够大的预览上限，用于在主面板展示完整小型数据集；Runtime 只透传该参数，实际取行由 Julia 数据检查函数完成。

```json
{
  "task_id": "uuid-inspect",
  "action": "inspect_dataset",
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
    "formula": "y ~ x1"
  },
  "options": {
    "drop_missing": false,
    "return_augment": false,
    "preview_rows": 1000000
  }
}
```

### 数据查看请求

`query_dataset` 专门承载 Stata 风格只读数据命令。当前只支持四类核心命令：

- `describe`：返回数据集规模与变量元数据列表
- `summarize`：返回每变量 `Obs / Mean / Std. dev. / Min / Max`
- `tabulate`：返回单变量频数、百分比与累计百分比
- `browse`：只返回只读浏览配置，不伪造统计结果

```json
{
  "task_id": "uuid-query",
  "action": "query_dataset",
  "project_context": {
    "project_id": "proj_001",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "data/demo.csv",
    "format": "csv"
  },
  "command": {
    "kind": "summarize",
    "variables": ["y", "x1"],
    "limit": 200
  }
}
```

### OLS / WLS 请求

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
    "weights": null,
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

### 面板模型请求

面板模型继续沿用 `fit_model` 信封，通过 `model_spec.model_type = "panel"` 与结构化面板索引字段进入 Julia 面板估计器。Runtime 只校验字段存在并转发请求，不在 Rust 侧实现面板计量逻辑。

```json
{
  "task_id": "uuid-panel",
  "action": "fit_model",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "/path/to/grunfeld.csv",
    "format": "csv"
  },
  "model_spec": {
    "model_type": "panel",
    "formula": "invest ~ mvalue + capital",
    "panel_id": "firm",
    "panel_time": "year",
    "panel_method": "fe"
  },
  "options": {
    "drop_missing": true,
    "return_augment": true
  }
}
```

### 数据变换请求

`/transform` 使用与 `fit_model` 一致的 Task 信封。Runtime 只负责解析项目工作目录、解析输入路径、生成派生 CSV 输出路径，并把结构化操作链转发给 Julia `MetricaData.jl`；具体数据语义不在 Rust 侧实现。

```json
{
  "task_id": "transform-001",
  "action": "transform",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "dataset_ref": {
    "source": "file",
    "path": "data/source.csv",
    "format": "csv"
  },
  "operations": [
    {
      "op": "filter",
      "args": {
        "condition": "year >= 2015"
      }
    },
    {
      "op": "generate",
      "args": {
        "name": "log_gdp",
        "expr": "log(gdp)"
      }
    }
  ],
  "options": {
    "preview_rows": 10,
    "persist_output": true
  }
}
```

当 `options.persist_output = true` 时，Runtime 将输出路径固定为：

```text
<working_dir>/.metrica/derived/<task_id>.csv
```

`.metrica/derived/` 是运行期派生数据目录，不进入版本控制。操作链具有事务语义：任一步失败时不写派生 CSV，响应中返回失败步骤序号和原因。

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

### 数据变换成功响应示例

```json
{
  "task_id": "transform-001",
  "status": "success",
  "messages": [],
  "artifacts": [],
  "result_payload": {
    "operation": "chain",
    "status": "ok",
    "result": {
      "nrows": 128,
      "ncols": 6,
      "notes": "执行 2 个数据操作。",
      "dataset_path": "/path/to/project/.metrica/derived/transform-001.csv"
    },
    "preview": {
      "columns": ["country", "year", "gdp", "log_gdp"],
      "rows": [
        {
          "country": "France",
          "year": 2015,
          "gdp": 2420.0,
          "log_gdp": 7.7915
        }
      ]
    },
    "warnings": [],
    "operations": [
      {
        "operation": "filter",
        "status": "ok",
        "result": {
          "nrows": 128,
          "ncols": 5,
          "notes": "保留满足条件 year >= 2015 的行。"
        },
        "warnings": []
      }
    ]
  }
}
```

### 数据查看成功响应示例

```json
{
  "task_id": "uuid-query",
  "status": "success",
  "messages": [],
  "artifacts": [],
  "result_payload": {
    "kind": "tabulate",
    "dataset_summary": {
      "row_count": 128,
      "column_count": 6
    },
    "variable": "region",
    "total": 128,
    "missing_count": 0,
    "truncated": false,
    "rows": [
      { "value": "east", "count": 40, "pct": 31.25, "cum_pct": 31.25 },
      { "value": "west", "count": 88, "pct": 68.75, "cum_pct": 100.0 }
    ]
  }
}
```

### 面板模型诊断响应片段

`model_type = "panel"` 的成功响应继续沿用同一个 `result_payload`，不新增 endpoint。面板诊断挂在 `result_payload.diagnostics` 下，当前包含 `hausman`、`fixed_effect_f`、`breusch_pagan_lm` 三个结构化诊断块。

```json
{
  "result_payload": {
    "glance": {
      "model_type": "panel",
      "method": "fe",
      "nobs": 200,
      "n_ids": 10,
      "n_times": 20
    },
    "tidy": [
      {
        "term": "mvalue",
        "estimate": 0.11,
        "std_error": 0.01,
        "statistic": 10.4,
        "p_value": 0.0
      }
    ],
    "augment_preview": [],
    "diagnostics": {
      "hausman": {
        "available": true,
        "statistic": 12.4,
        "pvalue": 0.002,
        "dof": 2,
        "method": "Hausman FE vs RE",
        "note": "教学版口径，比较 FE 与 RE 的共同斜率系数。"
      },
      "fixed_effect_f": {
        "available": true,
        "statistic": 18.6,
        "pvalue": 0.0,
        "dof": [9, 188],
        "method": "固定效应 F 检验",
        "note": "比较 pooled OLS 与个体固定效应模型。"
      },
      "breusch_pagan_lm": {
        "available": false,
        "statistic": null,
        "pvalue": null,
        "dof": null,
        "method": "Breusch-Pagan LM 随机效应检验",
        "note": "当前样本是不平衡面板，v1 不返回 LM 统计量。"
      }
    },
    "warnings": []
  }
}
```

不可用诊断必须显式返回 `available = false` 与 `note`，不得用 `0`、空字符串或展示层兜底文本伪造统计量。

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

### 数据变换错误响应示例

```json
{
  "task_id": "transform-001",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "DATA_TRANSFORM_FAILED",
      "text": "数据操作链执行失败。",
      "hint": "请检查失败步骤的字段名、表达式或外部文件路径。"
    }
  ],
  "result_payload": {
    "operation": "chain",
    "status": "error",
    "warnings": [],
    "error": {
      "op_index": 2,
      "message": "列 gdp 不存在。"
    },
    "operations": [
      {
        "operation": "filter",
        "status": "ok",
        "result": {
          "nrows": 128,
          "ncols": 5,
          "notes": "保留满足条件 year >= 2015 的行。"
        },
        "warnings": []
      }
    ]
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

## S3 项目系统端点

### POST /save_project

保存项目清单到 `<working_dir>/.metrica/project.json`。

**请求示例：**

```json
{
  "task_id": "save-project-001",
  "action": "save_project",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "manifest": {
    "project_id": "alpha-demo",
    "version": 1,
    "created_at": "2026-05-03T12:00:00Z",
    "updated_at": "2026-05-03T12:00:00Z",
    "source_dataset": "/path/to/source.csv",
    "active_dataset": "/path/to/active.csv",
    "saved_model_specs": [
      { "model_type": "ols", "formula": "y ~ x1 + x2" }
    ],
    "last_run_id": "run-001",
    "ui_state": { "active_tab": "glance" },
    "data_lineage": {
      "source_dataset": "/path/to/source.csv",
      "active_dataset": "/path/to/active.csv",
      "operations": [],
      "row_count_before": 100,
      "row_count_after": 100,
      "notes": []
    }
  }
}
```

**成功响应：**

```json
{
  "task_id": "save-project-001",
  "status": "success",
  "messages": [],
  "artifacts": ["/path/to/project/.metrica/project.json"],
  "result_payload": {
    "project_path": "/path/to/project/.metrica/project.json",
    "manifest": { ... }
  }
}
```

### POST /load_project

从 `<working_dir>/.metrica/project.json` 加载项目清单。

**请求示例：**

```json
{
  "task_id": "load-project-001",
  "action": "load_project",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  }
}
```

**成功响应：**

```json
{
  "task_id": "load-project-001",
  "status": "success",
  "messages": [],
  "artifacts": ["/path/to/project/.metrica/project.json"],
  "result_payload": {
    "project_path": "/path/to/project/.metrica/project.json",
    "manifest": { ... }
  }
}
```

**错误响应（项目不存在）：**

```json
{
  "task_id": "load-project-001",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "RUNTIME_PROJECT_NOT_FOUND",
      "text": "读取文件失败（/path/to/project/.metrica/project.json）",
      "hint": "请先保存项目。"
    }
  ]
}
```

### POST /list_runs

列出 `<working_dir>/.metrica/runs/` 下的所有运行记录，按 `finished_at` 降序排列。

**请求示例：**

```json
{
  "task_id": "list-runs-001",
  "action": "list_runs",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  }
}
```

**成功响应：**

```json
{
  "task_id": "list-runs-001",
  "status": "success",
  "messages": [],
  "result_payload": {
    "runs": [
      {
        "run_id": "run-001",
        "action": "fit_model",
        "started_at": "1714742400000",
        "finished_at": "1714742401000",
        "status": "success",
        "dataset_ref": { "source": "file", "path": "/path/to/data.csv", "format": "csv" },
        "model_spec": { "model_type": "ols", "formula": "y ~ x1" },
        "operations": null,
        "warnings": [],
        "messages": [],
        "artifacts": [],
        "result_summary": { "glance": { ... }, "tidy": [ ... ] },
        "request_payload": { ... }
      }
    ]
  }
}
```

### POST /rerun_task

根据历史运行记录重新执行任务。生成新的 `run_id`，若数据路径不存在则返回结构化错误。

**请求示例：**

```json
{
  "task_id": "rerun-001",
  "action": "rerun_task",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "run_id": "run-001"
}
```

**成功响应：** 与原始动作（`fit_model` / `transform` / `inspect_dataset`）的响应格式相同，但 `run_id` 更新。

**错误响应（数据路径失效）：**

```json
{
  "task_id": "rerun-001",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "RUNTIME_RERUN_DATASET_MISSING",
      "text": "重跑所需数据集不存在：/path/to/missing.csv",
      "hint": "请恢复数据文件后再重跑。"
    }
  ]
}
```

### POST /export_report

导出运行报告，支持 Markdown 和 CSV 格式。

**请求示例：**

```json
{
  "task_id": "export-001",
  "action": "export_report",
  "project_context": {
    "project_id": "alpha-demo",
    "working_dir": "/path/to/project"
  },
  "run_id": "run-001",
  "format": "markdown"
}
```

**支持的格式：**
- `markdown` — 完整 Markdown 运行报告
- `csv_tidy` — 系数表 CSV
- `csv_glance` — 摘要指标 CSV
- `csv_diagnostics` — 诊断结果 CSV

**成功响应：**

```json
{
  "task_id": "export-001",
  "status": "success",
  "messages": [],
  "result_payload": {
    "content": "# Metrica 单次运行报告\n...",
    "format": "markdown",
    "run_id": "run-001"
  }
}
```

**错误响应（运行记录无结果）：**

```json
{
  "task_id": "export-001",
  "status": "error",
  "messages": [
    {
      "level": "error",
      "code": "RUNTIME_NO_RESULT_SUMMARY",
      "text": "该运行记录没有结果摘要，无法导出报告。",
      "hint": "请确保运行成功后再导出。"
    }
  ]
}
```

## 当前稳定基线

当前可执行端到端链路为：

- 本地 CSV 输入 → `fit_model` 动作 → `ols`、`panel`、`iv` 或 `gls` 模型类型
- 本地 CSV 输入 → `transform` 动作 → 派生 CSV → `fit_model` 动作
- 结构化的 `glance` 与 `tidy` 响应载荷
- 面板模型的结构化 `diagnostics` 响应载荷
- 数据操作链的结构化 `preview`、`operations` 与错误定位
- 删行与拟合错误的警告/消息传播

### S3 项目系统端点（已实现，待端到端验证）

S3 端点已实现并通过单元测试，但尚未经过桌面端端到端流程验证：

- `POST /save_project` — 保存项目清单到 `.metrica/project.json`，含 manifest 字段校验
- `POST /load_project` — 从 `.metrica/project.json` 加载项目清单
- `POST /list_runs` — 列出运行记录，支持 `limit`/`offset`/`action_filter`/`status_filter`
- `POST /rerun_task` — 根据历史运行记录重新执行任务
- `POST /export_report` — 导出运行报告（Markdown / CSV 格式）

当前已知限制：

- S3 端点不经过 Julia Session — 保存/加载与 Julia 内存状态完全解耦
- 加载项目后不会自动恢复 Julia session 中的数据集
- "项目重开后可重跑"依赖数据集文件仍在原路径
- `rerun_task` 在 oneshot 回退模式下不可用
- `export_report` 在 oneshot 回退模式下不可用

主设计与阶段边界见：

- `Metrica.jl-计量经济学框架-完善版.md`
- `docs/roadmap/s1-foundation-and-workbench.md`
- `docs/roadmap/s2-core-empirical-workbench.md`
- `docs/superpowers/specs/2026-04-30-metrica-main-design.md`

当前实现路线补充约束：

- `fit_model` 必须通过 Runtime 调用 Julia 子进程真实执行
- 成功响应中的 `glance` 与 `tidy` 来自真实 Julia 拟合结果
- `fit_ols_demo` 或纯示例载荷不得作为当前完成标准

> 注意：成功响应中的 `augment_preview` 字段在 `options.return_augment = true` 时返回逐观测增强数据。OLS/WLS 包含拟合值、残差、标准化残差、杠杆值与 Cook's D；面板模型至少包含拟合值、残差与标准化残差。默认预览前 100 行。当 `return_augment = false` 时，该字段不包含在响应中。

当前默认基线为：

- `fit_model` 的默认模型类型是 `ols`
- 当前稳定协方差标签是 `classical`
- `model_spec.weights` 表示 WLS 权重变量名，值必须是数据集列名；缺省或 `null` 时保持 OLS
- `model_spec.panel_id`、`model_spec.panel_time`、`model_spec.panel_method` 仅在 `model_type = "panel"` 时使用；`panel_method` 当前支持 `fe`、`re`、`fd`、`between`，缺省由 Julia 桥接层按 `fe` 处理
- 面板 `diagnostics` 当前包含 `hausman`、`fixed_effect_f`、`breusch_pagan_lm`；诊断不可用时返回结构化不可用说明，而不是展示层推断
- 新增 `WLS`、`HC1`、`cluster` 等能力时，必须保持现有成功/失败响应信封不变

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
- Runtime 不传递 Julia 内部矩阵、分布对象或任意函数闭包；自定义计算能力必须先落为白名单动作、模板或结构化参数

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
