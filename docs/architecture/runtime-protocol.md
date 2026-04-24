# Runtime 协议

第一阶段动作：

- `inspect_dataset`
- `fit_model`
- `export_result`
- `explain_warning`

每个请求必须包含 `task_id`、`action`、`project_context` 以及动作相关载荷。  
每个响应必须包含 `task_id`、`status`、`messages`，以及可选的 `result_payload`。

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

## Alpha 垂直切片

第一条可执行端到端切片为：

- 本地 CSV 输入 → `fit_model` 动作 → `ols` 模型类型
- 结构化的 `glance` 与 `tidy` 响应载荷
- 删行与拟合错误的警告/消息传播

完整切片设计与验收标准见：

- `docs/superpowers/specs/2026-04-24-metrica-alpha-vertical-slice-design.md`
- `docs/superpowers/plans/2026-04-24-metrica-alpha-vertical-slice-plan.md`

> 注意：成功响应中的 `augment_preview` 字段在当前 alpha 切片中恒为空数组，完整 `augment` 大表渲染在后续切片中启用。
