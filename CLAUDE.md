# CLAUDE.md

本文件是 Claude Code 的项目级指令源。所有规则以 `AGENTS.md` 为权威来源，本文件仅作简洁引用。

## 核心规则

请严格遵循 `AGENTS.md` 中定义的所有规则，特别是：

- 尊重 Core / Runtime / App 三层架构边界，不得混淆
- 结构化结果优先于展示文本
- 教学体验是核心要求，非可选润色
- 禁止静默捏造 API、文件或测试结果
- 注释与文档正文使用简体中文

## 当前阶段

里程碑 1–5 已全部完成；**`S5` 高级研究专题已全量成熟化**，所有模型族达到 `implemented` 状态。

- 里程碑 1：Base Alpha ✅
- 里程碑 2：教学向 OLS ✅
- 里程碑 3：面板基础 ✅
- 里程碑 4：离散 / 因果 / 时间序列 / 复杂抽样等 `S4` 模型族 ✅
- 里程碑 5：地基升级与数据能力 ✅
- **S5.1**：线性 IV-GMM + iterated GMM + CUE + C-stat + Cragg-Donald ✅
- **S5.2**：动态面板 GMM（Difference + System + Collapsed + Diff-Hansen）✅
- **S5.3**：SUR / System 2SLS / 3SLS + Wald/LR/LM + robust cov ✅
- **S5.4**：分位数回归（多 τ + bootstrap + rank/sparsity + IV quantile）✅
- **S5.5**：NLS（exp_growth/logistic/power/gompertz + 多起点）+ 多门限 + sup-Wald ✅
- **S5.6**：ARCH/GARCH/GJR/EGARCH + Student-t/skewed-t + forecast/VaR/ES ✅
- **S5.7**：SAR/SEM/SDM/SDEM/SAC/SLX/GWR/GTWR/Probit + LM + 权重构造 ✅
- **S5.8**：Cox PH（Efron/strata/cluster/weights/counting-process）+ Schoenfeld + AFT 四分布 ✅
- **S5.9**：Bayesian 线性（NIG 共轭 + MCMC）+ logistic/probit + 层级模型 ✅
- **统一协议**：全部 S5 包实现 model_capabilities + augment_status + WARNING_CODE ✅

总体蓝图：`Metrica.jl-计量经济学框架-完善版.md`  
施工基准：`S5-模型族全量成熟化施工方案.md`  
设计文档：`docs/superpowers/specs/`  
实施计划：`docs/superpowers/plans/`

Core 层 Julia 包（20 个）：MetricaBase / MetricaData / MetricaDiagnostics / MetricaLinear / MetricaPanel / MetricaOutput / MetricaDiscrete / MetricaCausal / MetricaTimeSeries / MetricaSurvey / MetricaGMM / MetricaQuantile / MetricaNonlinear / MetricaSystem / MetricaSpatial / MetricaDuration / MetricaBayes / MetricaRuntime（以 `packages/` 为准）  
App 层：桌面宿主 **tao + wry** + React 19 + TypeScript 5 + Ant Design；**CLI-first 命令消息流**  
Runtime 层：Rust + axum + tokio + 持久化 Julia 进程（stdin/stdout JSON lines）
