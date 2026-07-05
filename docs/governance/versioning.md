# 版本策略

Metrica 在进入稳定研究可用状态前采用轻量 SemVer 规则。目标不是制造发布负担，而是让外部用户知道一次变更可能影响什么。

## 当前状态

当前版本线为 `0.x`。项目仍处于回顾完善阶段，不承诺 API、数值结果或桌面 App 行为已经稳定到正式研究或生产使用级别。

## 版本号规则

- `0.MINOR.0`：用户可见能力、协议字段、CLI 行为、包级 API 或文档承诺有实质变化。
- `0.MINOR.PATCH`：Bug 修复、测试补充、文档修正或开发脚本改进。
- 进入 `1.0.0` 前，minor 版本允许破坏性变更，但必须在 `CHANGELOG.md` 和 release notes 中明确说明。

## 破坏性变更

以下变更视为破坏性变更：

- 删除或重命名公开 `model_type`、协议字段、CLI 命令或结构化结果键。
- 改变 `glance`、`tidy`、`augment`、`diagnostics`、`warnings` 的语义。
- 改变 Runtime 请求/响应 schema 或 App 依赖的结构化数据契约。
- 改变默认估计方法、缺失值处理、权重语义或随机算法默认 seed 行为。

破坏性变更不得作为顺手修复混入 PR。若确有必要，应先在 Issue 或决策记录中说明原因、迁移影响和验证方式。

## 仓库内版本来源

- `CHANGELOG.md` 是用户可读的发布事实来源。
- `CITATION.cff` 记录当前引用版本和发布日期（与 GitHub「Cite this repository」一致）。
- Julia 包、Runtime、App 的内部 `version` 字段应在正式发布时与上述发布线一致。

除非进入独立发布阶段，Metrica 先按单仓库 release 处理，不为每个包单独维护公开 release 流程。

## 仓库内须同步的版本字段

一次**整体抬版本**（例如 `0.1.0` → `0.1.1`）时，至少核对并修改下列位置的 `version`（或等价字段），避免仓库内出现不一致：

| 位置 | 说明 |
|------|------|
| `CITATION.cff` | `version`；同时更新 `date-released` |
| `packages/*/Project.toml` | 各 Julia 包的 `version = "…"` |
| `scripts/daemon/Project.toml` | 守护进程辅助环境的 `version` |
| `runtime/metrica-runtime/Cargo.toml` | `[package].version` |
| `apps/metrica-desktop/src-tauri/Cargo.toml` | `[package].version`（桌面对外版本以此为准） |
| `README.md` | 顶部 shields **Version** 徽章 URL 中的 `version-X.Y.Z` 段；「版本与引用」小节的发布线文字 |

`apps/metrica-desktop/package.json` **不**维护 npm `version`；若将来需要单独的前端包版本，再在文档中另立约定。

README 中的「当前仓库整体发布线」、顶部版本徽章应与 `CHANGELOG.md` 最新已发布条目、`CITATION.cff` 保持一致。
