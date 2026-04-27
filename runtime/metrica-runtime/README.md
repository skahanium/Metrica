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

## 当前 Alpha 运行方式

当前最小真实链路通过本地 HTTP 方式暴露 Runtime：

- 绑定地址默认：`127.0.0.1:47821`
- 入口：`POST /inspect_dataset`
- 入口：`POST /fit_model`
- 预检：`OPTIONS /inspect_dataset`
- 预检：`OPTIONS /fit_model`

启动命令：

```bash
cargo run --manifest-path /Users/skahanium/Metrica/runtime/metrica-runtime/Cargo.toml -- serve
```

该服务只负责：

- 接收结构化 `inspect_dataset` 请求
- 接收结构化 `fit_model` 请求
- 调用 Julia 子进程执行真实 OLS
- 调用 Julia 子进程执行真实数据检查
- 返回结构化成功或失败响应
