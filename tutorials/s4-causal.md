# S4 教学：因果推断（CLI 主路径）

> 约定：在**本仓库根目录**启动应用，或保证 `working_dir` 指向仓库根。

## 数据

- 本教程使用演示 DID 面板：`datasets/demo/did_demo.csv`
- 主要列：`id`（个体）、`time`（时期）、`treated`、`post`、`y`、`x1`

## 最小命令序列（DID）

```text
use "datasets/demo/did_demo.csv"
describe id time treated post y x1
did y x1, id(id) time(time) treat(treated) post(post)
```

## 预期结构化输出

- 成功拟合后，`result` 中含 `glance.model`（应为 `did` 族 wire 名）、处理效应相关字段（如 `treat_effect` 等，以当前 Core 序列化为准）。
- 若缺 `id`/`time`/`treat`/`post` 选项，CLI 或 Runtime 会给出**结构化**校验提示，而非静默失败。

## IPW / PSM / AIPW

需在**自有数据**上提供 `treat(...)`、`outcome(...)`、`propensity(...)`（及 AIPW 的 `outcome_model(...)`），且列名与公式必须与 CSV 一致。教学上建议先完成小样本桌面实验，再对照 `packages/MetricaCausal.jl/test/runtests.jl` 中的 IPW/AIPW 用例核对 `glance` 与 `tidy` 字段。

## 常见 warning 解读

- 数据集路径不一致导致 `compare` 拒绝：见 `docs/architecture/s4-warning-coverage.md` Causal 一节。
- 倾向得分接近 0/1：IPW 实现中通常做数值裁剪；关注 `warnings` 数组。

## 导出

```text
runs
export markdown <run_id>, using("exports/did_run.md")
```
