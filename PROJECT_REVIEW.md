# Metrica 项目独立技术评估

> **⚠️ 历史快照 — 勿作当前 backlog 依据。** 最新可信度评估与「下一步 30 天」见 **[docs/quality/project-assessment.md](docs/quality/project-assessment.md)**（2026-06-01 起维护）。包级矩阵见 [docs/quality/package-status.md](docs/quality/package-status.md)。

> **评估日期：** 2026-05-24（历史快照）  
> **最新可信度评估：** 见 [docs/quality/project-assessment.md](docs/quality/project-assessment.md)（2026-06-01）  
> **评估基准：** 已合并至 `main` 的质量完善提交（含 golden 体系扩展前）  
> **评估方法：** 源码逐层审查 + 与本地门禁脚本对照，不依赖旧版文档表述  
> **评估范围：** 架构、Core / Runtime / App、测试与 golden、开源就绪度  

---

## 一、总体评价

Metrica 的三层隔离（Core → Runtime → App）与结构化协议（`glance` / `tidy` / `augment`、结构化警告与错误）在代码中**持续落地**。`oss-maturity` 上已完成一轮「完善阶段」关键项：嵌套 `ModelSpec.params`、P0 本地门禁、薄弱包测试扩充、Runtime 校验分族、OLS golden 外部参考脚本等。

**一句话判断（2026-05-24）：** 架构与协议为 **A-**；实现深度 **B+**；验证与门禁 **B-**（较初评明显抬升，但距「可宣称正式研究可用」仍有缺口）；开源就绪度 **B+**。

README 仍写明「不可用于生产或正式研究」——与当前证据一致，不宜过度乐观。

---

## 二、架构评价：A-

### 已验证优势

1. **三层边界清晰。** `packages/` 承载估计与协议；`runtime/` 为 Julia 进程编排与 schema；`apps/` 消费结构化 JSON，无计量求解开在 UI。
2. **ModelSpec 嵌套化（Phase 1，已落地）。** Rust `ModelSpec` 现为 6 个顶层字段 + `params: serde_json::Value`（族参数在 `model_params.rs` 的 `*Params` 与 `ValidatedModelParams` 枚举中）。TypeScript 侧 `ModelSpec.params` 为 `ModelFamilyParams`（`ModelSpecVariant` 去掉公共字段的联合类型）。**不再是** 70 字段扁平巨结构。
3. **MODEL_REGISTRY 全覆盖。** 各模型族包在 `__init__()` 中注册；`scripts/check_model_type_alignment.jl` 含 **params 字段名** Rust ↔ TS 对齐检查。
4. **本地质量门禁。**
   - `scripts/dev/test-p0.sh`：18 个 Julia 包矩阵 `Pkg.test()`、Rust 检查（含 **`vertical_slice --test-threads=1`**）、App 测试、model-type 对齐与 lint（clippy + `npm run build`）。
   - `make test-p0`：封装完整 P0 本地门禁。

### 仍存问题

| 问题 | 严重程度 | 说明 |
|------|----------|------|
| TS 协议文件体量大 | 中 | `protocol.ts` ~1080 行：含完整 `ModelSpecVariant` 联合与 App 类型；无 codegen，改字段仍须 Rust + TS 同步（有对齐脚本） |
| `ModelSpec.params` 在 Rust 仍为 `Value` | 低 | 校验后收敛为 `ValidatedModelParams`；编译期族内字段安全主要在 Rust 解析层，非 wire JSON 层 |
| MetricaData 未接入 MetricaBase | 中 | 数据命令返回自有 `Dict` 信封，非 `ModelGlance` / `ModelWarning`（与计量结果协议未统一） |
| 目录名 `src-tauri` | 低 | 实际为 wry + tao；README / CONTRIBUTING 已说明，非 Tauri 框架 |

### 对旧版「ModelSpec 膨胀」结论的修正

初评将「70 字段扁平 ModelSpec」列为架构主要债务。**在 `oss-maturity` 上该债务已结构性缓解**；剩余成本主要在协议镜像维护与 `params` 在边界处的 `Value` 类型。

---

## 三、Core 包评价

### 协议层 MetricaBase.jl：A-

| 维度 | 现状 |
|------|------|
| 测试规模 | `test/runtests.jl` 471 行（含 `test_serialize.jl`） |
| serialize.jl | **已有** 专项测试：`warning_to_dict`、`build_glance_envelope`、`build_tidy_rows`（含 NaN stderror）、`build_messages`、`build_augment_status`、`build_augment_preview`、`try_capabilities` 等 |
| `parse_metrica_formula` | **已有** 边界测试（空公式、缺因变量、多 `~` 等） |
| `AugmentTable()` | **已修复** 零参构造器 `AugmentTable(Dict(), 0)`；`augment(::BayesFitResult)` 等返回空表不再 MethodError |
| `WARNING_CODE` | 含 `:tau_near_boundary`、`:extreme_quantile` 等；Quantile 生产路径使用 `:tau_near_boundary` |

### 模型包分级（`test/runtests.jl` 行数，2026-05-24）

| 等级 | 包 | 测试行数 | 说明 |
|------|-----|---------|------|
| 金标准 | MetricaLinear | 901 | golden OLS/IV/GLS、系数恢复、多种 vcov、augment 数值恒等式 |
| 优良 | MetricaTimeSeries | 772 | 多模型主路径、ARIMA/VAR/波动率 |
| 优良 | MetricaCausal | 609 | DID/IPW/PSM/AIPW、DGP |
| 优良 | MetricaPanel | 606 | FE/RE/GMM 等 |
| 良好 | MetricaDiscrete | 564 | 六类离散模型 |
| 良好 | MetricaSurvey | 437 | 复杂抽样设计 |
| 良好 | MetricaBase | 471 | 协议 + serialize + confint |
| 中等 | MetricaSpatial | 182 | 多模型；部分 demo 样本偏小 |
| 中等 | MetricaGMM | 140 | GMM 主路径 |
| 中等 | MetricaDuration | 135 | Cox + AFT |
| 中等 | MetricaDiagnostics | 131 | 功能性测试 |
| 中等 | MetricaNonlinear | 101 | NLS + 门限 |
| 中等 | MetricaOutput | 94 | 输出格式化 |
| **已补强** | **MetricaBayes** | **237** | 含 logistic/probit/hierarchical、MCMC、DGP/边界、单观测 |
| **已补强** | **MetricaSystem** | **249** | 含 3SLS、SUR DGP 系数方向、2SLS/3SLS capabilities |
| **已补强** | **MetricaQuantile** | **233** | 多 τ、DGP 回收、`:tau_near_boundary`（τ=0.01）、augment |
| 薄弱 | MetricaData | 21 | 数据操作测试远少于计量包 |
| 占位 | MetricaRuntime | 6 | 薄包装 |

**相对初评：** Bayes / System / Quantile 已从「严重不足（34–40 行）」升至 **200+ 行**，满足完善阶段 Phase 5 目标量级。

---

## 四、数值与可信度

### 已缓解

1. **`det(bread) > eps` 杠杆值判定** — **已移除**。MetricaLinear / MetricaGMM 使用 `_invertible_bread`：以 `1/cond(bread)` 作逆条件数近似（注释标明 Julia 无 `rcond`），替代行列式阈值。
2. **OLS golden** — `datasets/golden/linear_ols.json` 注明独立 complete-case OLS，再生脚本 `scripts/golden/compute_ols_reference.jl`；与 R `lm` 同设计下数值等价。IV/GLS 仍有 fixture，外部参考扩展仍属 planned（见 `docs/quality/golden-values.md`）。

### 仍存风险

| 风险 | 程度 | 说明 |
|------|------|------|
| 直接 `inv(X'X)` 等 | 中 | 多包仍存在；学术软件常见，大样本下多数可接受 |
| Golden 覆盖面 | 中 | 仅线性族 3 个案有 JSON；其余模型族无独立 golden |
| MCMC / 随机路径 | 中 | Bayes MCMC 测试固定 seed，但未形成 golden 数值夹具 |

---

## 五、Runtime 层：A-

### 事实数据（约 2026-05-24）

| 模块 | 行数（约） | 职责 |
|------|-----------|------|
| `handlers.rs` | 954 | HTTP / 任务分派 |
| `types.rs` | 413 | 含精简 `ModelSpec` |
| `model_params.rs` | 297 | 族 `*Params`、`ValidatedModelParams`、`flatten` |
| `julia_session.rs` | 456 | 持久化 Julia 子进程 |
| `validation/` | 637 合计 | `mod.rs`（薄分派）、`kind.rs`（`validate_*` + `dispatch`）、`model_rules.rs`、`required.rs` |
| `vertical_slice.rs` | 集成测试 | 28 项（须 `--test-threads=1`） |

### 校验结构（Phase 1 / 用户 P2）

```text
validate_model_request → dispatch(spec)
  → validate_linear / validate_panel / validate_quantile / …（12 个族入口）
  → validate_impl：解析 params、必填字段、model_rules
```

`validate_model_request` 本体 **≤5 行**；族专属规则在 `model_rules.rs`（quantile τ、GMM、ARCH/GARCH 互斥、空间 GWR 等）。

**不含计量逻辑**；Julia 桥仍接收扁平化后的 JSON params（`flatten`）。

---

## 六、App 层：B+

| 项 | 现状 |
|----|------|
| 规模 | ~77 个 TS/TSX 源文件；`protocol.ts` ~1080 行 |
| 命令流 | `commandParser` + `runtimeClient.buildFamilyParams` 输出嵌套 `params` |
| 测试 | `src-react/__tests__/` **21** 个文件；`npm test` 约 **235** 项 |
| 计量逻辑 | 无；消费 `result_payload` |

---

## 七、测试与质量基础设施：B-

### 已具备

- P0 本地门禁：**18/18** Julia 包 + Rust + App + alignment + lint。
- P0 本地门禁：`bash scripts/dev/test-p0.sh`。
- MetricaLinear golden 框架 + OLS 外部参考脚本。
- MetricaBase serialize / formula 测试。
- Runtime 集成测试覆盖多模型族路径。

### 仍缺

| 项 | 现状 |
|----|------|
| MetricaData 测试 | 21 行，与数据产品面不匹配 |
| 全模型族 golden | 除 linear 三案外未系统化 |
| App ESLint | **未配置**；lint 用 `npm run build` 作类型检查（CONTRIBUTING 已写明） |
| 全量与快路径 | P0 本地门禁覆盖全量核心检查；普通改动仍可按影响范围运行最小验证 |

---

## 八、完善阶段完成度（对照内部 Phase / 门禁优先级）

以下为仓库**实际采用的优先级口径**（与《全面质量修复方案》Phase 编号一致，**不同于**本文件初版「学术可信度 P1」表述）。

| 优先级 | 含义 | 状态（oss-maturity） |
|--------|------|----------------------|
| **P0** | 18 包 `Pkg.test()` + `vertical_slice` 串行纳入本地门禁 | **已完成**（`test-p0.sh`） |
| **P1** | Phase 5：Quantile `:tau_near_boundary`、System/Bayes DGP 与边界 | **已完成**（三包测试 230+ 行；Quantile 警告码已统一为 `:tau_near_boundary`） |
| **P2** | Phase 1 结构债：`validate_*` 分族、`ModelFamilyParams` | **已完成**（`validation/kind.rs` + TS 联合类型） |
| **P3** | Phase 3/4/6 字面：`1/cond` 注释、npm build ≠ ESLint、serialize 补例 | **已完成**（`b808241`）；README 原生壳说明此前已有 |

### Phase 逐项快照

| Phase | 内容 | 状态 |
|-------|------|------|
| 1 | 嵌套 ModelSpec、Rust 校验分族、TS `ModelFamilyParams`、vertical_slice 嵌套 JSON | 完成 |
| 2 | `AugmentTable()` 零参构造 | 完成 |
| 3 | `det(bread)` → 条件数判定 | 完成（实现为 `1/cond`，非 `rcond` 字面 API） |
| 4 | `test_serialize.jl` + formula 边界 | 完成 |
| 5 | Bayes / System / Quantile 扩测 | 完成（达 ~200+ 行量级） |
| 6 | lint + README 壳说明 | 完成（lint = clippy + build，非 ESLint） |

---

## 九、初评争议点复核（2026-05-24）

| 初评声明 | 复核结果 |
|----------|----------|
| Bayes/Duration/Spatial 未注册 MODEL_REGISTRY | **不成立**（已注册） |
| gjr_garch / egarch 未注册 | **不成立** |
| augment 必触发 MethodError | **已修复**（零参构造器；正常序列化仍多走 `build_augment_status`） |
| 运行时调度断裂 | **不成立** |
| ModelSpec 70 字段债务 | **oss-maturity 已嵌套化** |
| serialize.jl 零测试 | **不成立**（`test_serialize.jl`） |
| lint 缺失 | **不成立**（有 clippy 与 npm build；无 ESLint） |
| 最弱三包 &lt;50 行测试 | **已过时**（现 230+ 行） |

---

## 十、后续建议（按收益排序）

1. **扩展 golden** — IV/GLS 接 R 或固定参考实现；登记 `docs/quality/golden-values.md`。
2. **MetricaData 协议对齐** — `describe` / `inspect` 等返回 `ModelGlance` + `ModelWarning`，与 App 警告链打通。
3. **MetricaData 测试** — 与 `query.jl` / `transform` 规模匹配。
4. **可选：Rust `params` 强类型 wire 格式** — 在 `Value` 之上增加 serde 标签枚举（破坏性小、收益中）。
5. **数值卫生** — 逐步将关键路径 `inv(X'X)` 换为 `\` 或 Cholesky（非阻塞发版）。

---

## 十一、综合评分

| 维度 | 评分 | 说明 |
|------|------|------|
| 架构设计 | **A-** | 嵌套 ModelSpec、分族校验、三层边界；TS 镜像仍大 |
| 实现深度 | **B+** | 主流模型族可用；Data 层与部分空间/诊断仍薄 |
| 数值可信度 | **B-** | OLS golden 有外部参考；全族 golden 与 inv 习惯仍拖累 |
| 测试覆盖 | **B** | 全包本地门禁 + 薄弱包已补强；Data / 全族 golden 不足 |
| 开源就绪度 | **B+** | P0 门禁、lint、CONTRIBUTING、alignment 脚本齐备 |
| **总体** | **B+** | 完善阶段主项已落地；README「非正式研究」声明仍合理 |

---

## 十二、关键提交（oss-maturity，便于审计）

| 提交 | 摘要 |
|------|------|
| `aed05a7` | 嵌套 ModelSpec、Julia 桥、多包修复、Phase 5 扩测等 |
| `1ae2c07` | P0：`test-p0.sh`、18 包测试、vertical_slice 串行、CONTRIBUTING |
| `b132020` | OLS golden 元数据与再生脚本、文档 |
| `b808241` | `:tau_near_boundary`、`validation/kind.rs`、P3 注释与 serialize 补例 |

---

## 十三、评估局限

- 本报告**未**在评估日重跑完整 `test-p0.sh`（耗时数分钟至数十分钟）；结论基于代码结构与最近一次完善阶段验证记录。
- 未安装 R/Stata 复核 golden；OLS 等价性依据脚本注释与同设计代数一致性。
- `PROJECT_REVIEW.md` 为工作区文档，**未**纳入版本控制；若需团队共享请自行决定是否提交。

---

*文档版本：2.0（对齐 oss-maturity @ 2026-05-24）*
