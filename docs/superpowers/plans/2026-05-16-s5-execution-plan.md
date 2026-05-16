# S5 执行计划（活跃）

> **状态：当前唯一活跃 `superpowers` 实施计划。** 分期目标、非目标与验收细节以仓库根目录 [`S5-高级研究专题总施工规划.md`](../../../S5-高级研究专题总施工规划.md) 为权威来源；本文件仅维护**执行顺序、文档锚点与跨层检查清单**，不重复总规全文。

## 文档锚点

| 用途 | 路径 |
|------|------|
| 总规 | [`S5-高级研究专题总施工规划.md`](../../../S5-高级研究专题总施工规划.md) |
| 路线图分期 | [`docs/roadmap/s5-advanced-research-topics.md`](../../roadmap/s5-advanced-research-topics.md) |
| 主设计 | [`docs/superpowers/specs/2026-04-30-metrica-main-design.md`](../specs/2026-04-30-metrica-main-design.md) |
| Runtime 协议 | [`docs/architecture/runtime-protocol.md`](../../architecture/runtime-protocol.md) |
| App 壳层 | [`docs/architecture/app-shell.md`](../../architecture/app-shell.md) |

## S5.0 文档治理与阶段基线（本计划前置）

- [x] 路线图 `s5-advanced-research-topics.md` 与总规对齐；历史对照矩阵改为非活跃快照说明。
- [x] 主设计更新为 `S1`–`S4` + CLI-first + `S5` 边界；`superpowers` 下已完成 spec/plan 结论并回主设计后删除原文件。
- [x] `app-shell.md` / `runtime-protocol.md` 与 **Runtime + 桌面宿主（`tao`/`wry` + `src-react`）** 源码对齐；补充 `model_type` 表与 `S5` 扩展规则。
- [x] 根目录 `ui-project-button-system-plan.md` 并回壳层「愿景」叙述后删除。
- [x] `README.md`、`apps/metrica-desktop/README.md`、`runtime/metrica-runtime/README.md`、`CLAUDE.md` 同步阶段说明。

## 后续分期（执行顺序）

按总规优先级：`S5.1` GMM → `S5.2` 动态面板 GMM → `S5.3` SUR / 系统方程 → `S5.4` 分位数 → `S5.5`–`S5.9` 见总规。

每分期开工前更新总规对应小节，并在本文件增加 **Task 清单**（文件路径、关键函数、测试断言各一行级），遵守 `AGENTS.md` 对 plan 篇幅约束。

## S5.1 线性 IV-GMM 与过识别检验（已完成）

- [x] `packages/MetricaGMM.jl`：一步/两步权重、Hansen J、`glance`/`tidy`/`serialize`、确定性测试。
- [x] `scripts/julia_bridge_entry.jl` / `julia_daemon.jl`：`gmm_linear` 分支与 `MetricaGMM.result_to_payload`。
- [x] Runtime：`ModelSpec.gmm_weight`、`validate_model_request`、`vertical_slice` 测例；`julia_bridge_entry` 仓库根解析修复（`-e` 下可靠 `include` MetricaDaemon）。
- [x] App：`gmm` CLI、`gmm_weight` 透传、`GmmDiagnosticsPanel`、协议类型与 Vitest。
- [x] 文档：`runtime-protocol` 本节、`tutorials/s5-gmm.md`。

**已验证（本阶段）：** `Pkg.test(MetricaGMM)`（Julia）；`cargo test --test vertical_slice fit_model_runs_gmm_linear`（Runtime + 桥接）；`apps/metrica-desktop` 下 `npm test`（Vitest）。

## 验证与未覆盖风险（`S5.0`）

- **已做：** 全仓 `grep` 旧 `spec`/`plan` 路径与 `ui-project-button-system-plan.md`；`docs/superpowers` 目录仅剩本计划与主设计；Runtime 路由与 `julia_bridge_entry.jl` / `julia_daemon.jl` 对照更新协议文档。
- **未做 / 风险：** 未运行自动化外链检查 CI；若外部 Wiki 仍链接已删除的 `plan` 文件，需人工更新。后续 `S5.x` 代码变更后须再次同步 `runtime-protocol` 中的端点表与 `model_type` 表。

## 验证习惯

- 文档删除后全仓 `grep` 旧路径；Julia/Runtime 变更后更新 `runtime-protocol` 端点表与 `model_type` 表。
- 阶段完成说明须列出**已验证范围**与**未覆盖风险**（见 `AGENTS.md` 完成定义）。
