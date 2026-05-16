# Metrica Runtime

桌面应用与 Julia Core 之间的桥接层。

## 职责

- 启动与管理 Julia 进程
- 接收结构化任务请求
- 返回结构化结果与警告
- 处理日志、取消与失败传播

## 非职责

- UI 渲染
- 计量模型语义
- 直接面向用户的流程设计

## HTTP 入口（持久化会话模式）

默认绑定 `127.0.0.1:47821`。完整路径表、CORS 行为、`--oneshot` 回退子集与 **`model_type` 白名单** 以仓库内 [`docs/architecture/runtime-protocol.md`](../../docs/architecture/runtime-protocol.md) 与 `src/server.rs` 为准。

摘要（持久化 `build_router`）：

- `GET /health`、`GET /session/env`
- `POST /inspect_dataset`、`/query_dataset`、`/fit_model`、`/transform`、`/run_diagnostic`
- `POST /save_project`、`/load_project`、`/list_runs`、`/rerun_task`、`/export_report`

启动示例：

```bash
cargo run --manifest-path /path/to/Metrica/runtime/metrica-runtime/Cargo.toml -- serve
```

该服务负责接收结构化请求、调用持久化 Julia 会话执行真实任务，并返回结构化成功或失败响应；**不**在 Rust 层实现计量估计。
