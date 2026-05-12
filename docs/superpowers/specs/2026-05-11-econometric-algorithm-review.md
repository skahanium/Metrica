# Metrica 计量算法审查报告

> **日期：** 2026-05-11  
> **审查范围：** Core 层计量算法与当前桌面命令到 Runtime/Julia 的执行路径。覆盖 `MetricaLinear`、`MetricaDiagnostics`、`MetricaPanel`、`MetricaDiscrete`、`MetricaTimeSeries`、`MetricaCausal`、`MetricaSurvey`，以及 `apps/`、`runtime/`、`scripts/` 中与模型命令相关的桥接实现。  
> **审查口径：** 从数学正确性、计量推断有效性、结构化命令可达性三个角度审查现有实现；不把未运行的完整基准或跨软件对齐测试写成已验证事实。  
> **补充说明：** 本报告基于源码审查，并对 Poisson IRLS 与 Ordered Logit 做了最小复现实验；其余问题以源码路径和计量定义为依据。

## 修复状态

- **2026-05-11 第一批修复已完成：** 问题 13（Poisson IRLS 均值截断）、问题 14（Ordered Logit 截距/阈值识别）、问题 24（`robust` 大小写静默退化）、问题 25 的命令协议部分（`xtivreg` 解析为 `panel_iv` 并传递 IV 字段）。
- **2026-05-11 Panel IV 数学修复已完成：** 问题 11 已改为在组内空间对因变量、外生变量、内生变量和工具变量做 2SLS，并去掉被固定效应吸收的截距列。
- **2026-05-11 Panel FE 自由度修复已完成：** 问题 7 已改为使用 `nobs - k - (n_ids - 1)` 作为 FE 残差自由度。
- **验证限制：** Panel IV 与 Panel FE 窄场景已验证通过；`MetricaPanel` 全量测试当前被缺失文件 `datasets/teaching/pwt_productivity_panel.csv` 阻塞，阻塞前 88 个断言通过。
- **验证记录：** 第一批修复的执行清单见 `docs/superpowers/plans/2026-05-11-econometric-first-fixes-plan.md`。

---

## 一、MetricaLinear.jl — 线性模型族

### 1.1 OLS/WLS

**基本判断：** OLS 核心路径基本可靠。正规方程求解、WLS 的 `sqrt(w)` 变换、HC1、Cluster 稳健标准误、条件数检查、满秩校验和 Cook's D 公式整体正确。

**问题 1：WLS 的预测区间口径混淆（中等）**

- **位置：** `packages/MetricaLinear.jl/src/ols.jl` 的 `predict` 方法。
- **描述：** WLS 估计在加权空间中完成，`sigma` 来自加权残差平方和，但预测区间使用原始 `X'X` 的逆矩阵。正确口径应使用 `(X'WX)^{-1}`。
- **影响：** WLS 的均值置信区间和预测区间可能错误，尤其在权重差异较大时。
- **修复方向：** 在结果中存储估计时使用的 bread 矩阵，或在 `predict` 中按原始权重重建 `(X'WX)^{-1}`。

### 1.2 IV/2SLS

**问题 2：第一阶段 F 统计量高估工具变量强度（严重）**

- **位置：** `packages/MetricaLinear.jl/src/iv.jl` 的第一阶段诊断。
- **描述：** 当前用完整工具矩阵对内生变量回归的 R² 构造 F 统计量。标准弱工具变量诊断应检验“排除工具变量”的增量解释力，即比较仅含外生变量的受约束模型和外生变量加工具变量的无约束模型。
- **影响：** 可能漏报弱工具变量，进而误导 IV 结果解释。
- **修复方向：** 计算 `R²_restricted` 与 `R²_unrestricted`，用增量 F 公式报告排除工具变量的联合显著性。

**问题 3：IV HC1 标准误的 bread 矩阵近似（中等）**

- **位置：** `packages/MetricaLinear.jl/src/ols.jl` 的 `compute_vcov` HC1 分支被 IV 复用。
- **描述：** 当前把第二阶段投影后的 `X_hat` 当作普通设计矩阵计算 HC1。严格 2SLS 异方差稳健方差需要使用 IV sandwich 口径，bread 与 meat 均应反映 `Z` 投影。
- **影响：** 异方差较强时标准误可能不准确。

### 1.3 GLS

**问题 4：GLS 的 R² 和预测区间在错误空间计算（中等）**

- **位置：** `packages/MetricaLinear.jl/src/gls.jl`。
- **描述：** GLS 最小化变换空间中的残差平方和，但当前 R² 使用原始残差构造；预测区间也使用原始 `X'X` 口径。
- **影响：** R² 的统计解释不清晰，预测区间可能错误。
- **修复方向：** 报告变换空间 R² 或明确标注为伪 R²；预测区间使用估计时的变换后矩阵。

---

## 二、MetricaDiagnostics.jl — 诊断检验

**基本判断：** Breusch-Pagan、Breusch-Godfrey、RESET、Jarque-Bera 的核心统计量实现基本正确。

**问题 5：White 检验自由度计算不完整（轻微）**

- **位置：** `packages/MetricaDiagnostics.jl/src/MetricaDiagnostics.jl` 的 White 检验。
- **描述：** 辅助回归矩阵包含原始变量与平方项，但自由度只按平方项计数。正确自由度应为辅助回归非截距列数。
- **影响：** p 值偏保守。

**问题 6：Durbin-Watson p 值使用过粗正态近似（中等）**

- **位置：** `packages/MetricaDiagnostics.jl/src/MetricaDiagnostics.jl` 的 Durbin-Watson 检验。
- **描述：** DW 分布依赖样本量和设计矩阵结构，不是简单的 `N(2, 4/n)`。
- **影响：** 小样本或复杂设计矩阵下 p 值可能严重失真。
- **修复方向：** 返回界限检验信息，或实现/委托精确近似；若暂时保留，应在结构化诊断中标记为粗略近似。

---

## 三、MetricaPanel.jl — 面板模型族

**基本判断：** FD、Between、CRE、HDFE 的核心方向是合理的；FE、RE、Hausman、Panel IV 的推断口径需要优先修正。

**问题 7：FE 的自由度未扣减吸收的固定效应（严重）**

- **位置：** `packages/MetricaPanel.jl/src/fe.jl` 调用 `ols_statistics`，而 `packages/MetricaPanel.jl/src/MetricaPanel.jl` 中自由度为 `nobs - k`。
- **状态：** 已于 2026-05-11 修复。FE 估计器现在显式传入 `nobs - k - (n_ids - 1)`。
- **原始问题：** 固定效应组内估计应扣减吸收的个体固定效应自由度。常见口径为 `n - k - (N - 1)`，具体还需与截距处理保持一致。
- **原始影响：** `sigma²` 和标准误偏小，t 统计量偏大，显著性被高估。
- **修复口径：** 让面板估计器显式传入残差自由度，不复用只适用于普通 OLS 的默认 `n-k`。

**问题 8：RE 实际为 Mundlak/CRE 路径，不是标准 GLS-RE（中等）**

- **位置：** `packages/MetricaPanel.jl/src/re.jl`。
- **描述：** 当前实现注释和逻辑均指向 Mundlak 方法，即在 pooled 回归中加入组均值。这不是 Swamy-Arora 类标准随机效应 GLS。
- **影响：** 用户预期的 RE 效率增益不存在；若 Hausman 与 FE 比较，检验解释会混乱。
- **修复方向：** 若保留 Mundlak，应在模型类型、`glance` 和文档中明确为 Mundlak/CRE；若需要传统 RE，应单独实现 GLS-RE。

**问题 9：Driscoll-Kraay 得分向量按期均化（轻微）**

- **位置：** `packages/MetricaPanel.jl/src/dk.jl`。
- **描述：** DK 常用期内得分求和，当前按期平均再缩放。不平衡面板下该处理可能与标准公式不一致。

**问题 10：Hausman 检验使用对角近似且说明与实现不一致（中等）**

- **位置：** `packages/MetricaPanel.jl/src/diagnostics.jl`。
- **描述：** 当前只使用 `fe_se² - re_se²` 的对角元素，没有使用完整协方差差矩阵；但诊断说明里提到“完整协方差”。同时 RE 路径又是 Mundlak，使比较对象本身不符合传统 Hausman 设定。
- **影响：** Hausman 统计量和 p 值不宜作为正式 FE/RE 选择依据。

**问题 11：Panel IV 未进行组内变换（严重）**

- **位置：** `packages/MetricaPanel.jl/src/panel_iv.jl`。
- **状态：** 已于 2026-05-11 修复。当前实现先按 `panel_id` 对 `y`、`X` 和工具变量去均值，再执行 2SLS。
- **原始问题：** 旧实现直接在 pooled 数据上构造 `X`、`Z` 并做 2SLS，没有对因变量、外生变量、内生变量和工具变量做组内去均值。
- **原始影响：** 结果是 Pooled IV，不是 FE-IV；若个体固定效应与解释变量相关，估计不一致。
- **修复口径：** 在 2SLS 前对所有相关列做同一组内变换，并使用 FE-IV 自由度和诊断口径。

**问题 12：不平衡面板 BP-LM 的 `T_star` 计算但未使用（轻微）**

- **位置：** `packages/MetricaPanel.jl/src/diagnostics.jl`。
- **描述：** 代码计算了不平衡面板修正量，但统计量没有使用它。

---

## 四、MetricaDiscrete.jl — 离散选择与计数模型

**问题 13：IRLS 中 `mu` 的 clamp 上限对 Poisson 不正确（严重）**

- **位置：** `packages/MetricaDiscrete.jl/src/irls.jl`。
- **描述：** `mu` 被统一截断到 `(1e-10, 1 - 1e-10)`。二元响应模型需要上界截断，但 Poisson 均值可以大于 1。
- **最小复现：** 对 `y = 2:11` 的 Poisson 回归，`max_fitted` 被截断为 `0.9999999999`，系数近似变成 `[0, 1]` 这一类无意义结果。
- **影响：** Poisson 路径在均值大于 1 的常见数据上不可用。
- **修复方向：** 按模型族分支：二元响应使用 `(eps, 1-eps)`，计数模型只设置正下界。

### 4.1 Logit / Probit

**基本判断：** 对二元 Logit/Probit，IRLS、MLE 方差、HC1/Cluster 三明治、Pseudo R²、AIC/BIC 和完全分离检测方向正确。

**问题 14：Ordered Logit 截距与阈值不可识别，阈值排序也未约束（严重）**

- **位置：** `packages/MetricaDiscrete.jl/src/ologit.jl`。
- **描述：** StatsModels 构造的设计矩阵包含截距，同时 Ordered Logit 又自由估计阈值。截距和所有阈值的共同平移不可分别识别。阈值也直接作为自由参数估计，没有用正增量等方式保证有序。
- **最小复现：** 一个 10 行三分类样本拟合后返回 `coef_names = ["(Intercept)", "x"]`，阈值和截距同时出现，标准误为 `[0.0, 0.0]`，但 `converged = true`。
- **影响：** 参数识别、标准误和收敛状态都不可靠；即使似然函数形式接近正确，模型对象也不能作为可解释估计结果。
- **修复方向：** Ordered 模型的 `X` 中移除截距，或固定一个阈值/截距作为归一化；阈值用累计正增量参数化，避免无序阈值。

**问题 15：多项 Logit 使用 one-vs-rest，而不是真正的 softmax MLE（严重）**

- **位置：** `packages/MetricaDiscrete.jl/src/mlogit.jl`。
- **描述：** 当前对每个非基准类别分别拟合二元 Logit。标准 MNL 应联合优化 softmax 似然。
- **影响：** 类别概率和不保证为 1，参数不一致，标准误忽略跨方程相关，似然值没有标准 MNL 解释。
- **修复方向：** 实现联合 softmax 对数似然和 Hessian/稳健方差，或在模型名称中明确标记为 one-vs-rest 分类器。

**问题 16：负二项 `alpha` 使用 6 点网格搜索（中等）**

- **位置：** `packages/MetricaDiscrete.jl/src/negbin.jl`。
- **描述：** 6 个候选点过粗，容易错过 profile likelihood 最优值。
- **修复方向：** 用一维优化器估计 `alpha`，或联合优化 `(beta, alpha)`。

**基本正确部分：** Logit/Probit 的 AME/MEM 公式和 Delta method 推导方向正确。

---

## 五、MetricaTimeSeries.jl — 时间序列

**基本判断：** 包内 ADF 委托成熟库是正确策略；ARIMA MLE 委托 `StateSpaceModels.jl`、VAR 方程 OLS、伴随矩阵稳定性检测和 Cholesky IRF 方向合理。但时间序列命令当前没有可靠接入 Runtime/Julia 执行链路。

**问题 17：Phillips-Perron p 值使用正态分布（严重）**

- **位置：** `packages/MetricaTimeSeries.jl/src/unitroot.jl`。
- **描述：** PP 统计量服从非标准 Dickey-Fuller 型分布，不能用标准正态分布计算 p 值。
- **影响：** 单位根检验结论可能系统性过度拒绝。
- **修复方向：** 使用 MacKinnon 响应面、查表近似，或委托成熟库。

**问题 18：Johansen 临界值硬编码且维度受限（中等）**

- **位置：** `packages/MetricaTimeSeries.jl/src/cointegration.jl`。
- **描述：** 临界值表仅覆盖很小维度，且数值不像标准 Osterwald-Lenum/MacKinnon-Haug-Michelis 表。
- **影响：** 多变量协整检验可能索引越界或给出错误结论。

---

## 六、MetricaCausal.jl — 因果推断

**问题 19：DID/TWFE 聚类标准误使用的 score 与吸收估计不一致（中等）**

- **位置：** `packages/MetricaCausal.jl/src/twfe.jl` 与 `packages/MetricaCausal.jl/src/did.jl`。
- **描述：** TWFE 点估计在去均值后的 `X`、`y` 上完成，但 DID 聚类分支用原始 `X_noint` 和 `y - X_noint * coefficients` 构造 score。
- **影响：** 聚类稳健方差没有对应实际估计方程，标准误可能错误。
- **修复方向：** 使用吸收后的设计矩阵和残差构造 cluster score，或委托同一套 FE 估计结果的方差计算。

**问题 20：IPW 的 ATU 标准误使用 ATE 标准误（轻微）**

- **位置：** `packages/MetricaCausal.jl/src/ipw.jl`。
- **描述：** `atu_se` 字段传入了 `ate_se`。

**问题 21：AIPW 结果模型未按处理组分别拟合（中等）**

- **位置：** `packages/MetricaCausal.jl/src/doubly_robust.jl`。
- **描述：** 标准 AIPW 需要估计 `E[Y|X,T=1]` 和 `E[Y|X,T=0]`。当前只拟合一个全样本结果模型，导致 `mu1_hat` 与 `mu0_hat` 不能表达潜在结果差异。
- **影响：** 双重稳健性质不成立，估计结果可能误导。

---

## 七、MetricaSurvey.jl — 调查模型

**基本判断：** Survey OLS 的 WLS 点估计加 Taylor 线性化方差是合理方向，但 Survey GLM 当前不应被视作完整调查加权 GLM。

**问题 22：Survey GLM 点估计先走未加权 Logit/Poisson，再套调查方差（严重）**

- **位置：** `packages/MetricaSurvey.jl/src/survey_glm.jl` 与 `packages/MetricaSurvey.jl/src/survey_design.jl`。
- **描述：** Survey Logit/Poisson 先调用普通未加权离散模型，再用调查设计权重计算方差。GLM 的 Taylor 线性化也复用了近似 OLS bread，而不是加权伪似然的 Hessian/score。
- **影响：** 点估计和标准误都可能不符合调查加权 GLM 定义。
- **修复方向：** 用 survey weights 进入 GLM 估计方程，并按 GLM score/Hessian 构造 Taylor 方差。

**问题 23：Survey OLS 权重与缺失行过滤可能错位（中等）**

- **位置：** `packages/MetricaSurvey.jl/src/survey_ols.jl`。
- **描述：** 若公式建模阶段因缺失值过滤行，随后用 `dataset[1:nobs, weight_col]` 取权重可能与保留样本不一致。
- **影响：** 有缺失数据时权重可能对应错误观测。
- **修复方向：** 从同一个 model frame 或保留行索引中抽取权重、分层和 PSU。

---

## 八、命令、协议与 Runtime 可达性

这一部分不属于单个估计算法，但直接决定“用户输入命令后实际运行的模型”是否与计量语义一致。

**问题 24：`robust` 选项大小写不一致，可能静默退化为 classical SE（严重）**

- **位置：** `apps/metrica-desktop/src-react/services/commandParser.ts`、`scripts/julia_daemon.jl`、`scripts/julia_bridge_entry.jl`。
- **描述：** 前端解析产生 `{ type: "hc1" }`，Julia 桥接只识别 `"HC1"`。不匹配时会走默认 classical 方差。
- **影响：** 用户显式要求稳健标准误，却可能得到普通标准误，且没有警告。
- **修复方向：** 在协议层统一枚举值并大小写归一化；未知方差类型应返回结构化错误或警告。

**问题 25：`xtivreg` 命令被路由为普通 panel，工具变量信息没有传到 Julia（严重）**

- **位置：** `apps/metrica-desktop/src-react/services/commandParser.ts` 与 `apps/metrica-desktop/src-react/services/runtimeClient.ts`。
- **描述：** `xtivreg` 映射到 `panel`，而 runtime client 的 panel 分支没有传递 `endogenous` 与 `instruments` 字段。
- **影响：** 用户以为运行 FE-IV，实际可能运行普通面板模型或丢失 IV 语义。
- **修复方向：** 为 panel IV 建立独立模型类型和 schema，端到端传递内生变量、工具变量、entity/time 列。

**问题 26：IPW/PSM/AIPW 命令缺少 propensity/outcome 公式（严重）**

- **位置：** `packages/MetricaCausal.jl/src/ipw.jl`、`psm.jl`、`doubly_robust.jl`，以及 `commandParser.ts`、`runtimeClient.ts`、`scripts/julia_daemon.jl`。
- **描述：** Julia 包方法需要 `propensity_formula`，AIPW 还需要 `outcome_formula`；前端和 Runtime 只传 treatment/outcome 列。
- **影响：** 因果模型命令路径无法表达核心建模公式，或只能失败/退化。
- **修复方向：** 在命令语法和 Runtime schema 中显式加入倾向得分公式与结果模型公式。

**问题 27：TimeSeries 包内模型没有接入当前 Julia daemon/oneshot 路径（严重）**

- **位置：** `scripts/julia_daemon.jl`、`scripts/julia_bridge_entry.jl`、`apps/metrica-desktop/src-react/services/commandGrammar.ts`、`commandParser.ts`。
- **描述：** 前端语法包含 `arima`、`var`、`dfuller`、`coint`，但 Julia daemon 中 TimeSeries 包加载和参数处理仍是注释状态；oneshot bridge 也没有加载 TimeSeries，非 panel/survey 路径最终回落到 OLS。
- **影响：** 用户命令和实际估计器之间存在断裂，时间序列功能即使包内存在也不可通过当前命令稳定运行。
- **修复方向：** 将 TimeSeries 加入 Julia bridge 依赖和模型分发；补齐 time column、变量列表、阶数等 schema，并增加端到端命令测试。

**问题 28：诊断/事后命令仍是解析占位，未形成执行语义（中等）**

- **位置：** `apps/metrica-desktop/src-react/services/commandParser.ts` 与命令处理路径。
- **描述：** 命令语法中已有部分诊断和 postest 命令，但处理函数没有端到端执行到 Julia 诊断结果。
- **影响：** UI 命令能力和 Core 诊断能力之间存在断层。
- **修复方向：** 先冻结诊断命令 schema，再把结果作为结构化诊断对象返回，而不是解析展示文本。

---

## 九、严重程度排序

### 优先修复

| # | 模块 | 问题 | 严重程度 |
| --- | --- | --- | --- |
| 13 | Poisson IRLS | `mu` 被 clamp 到 `(0,1)`，计数模型不可用 | 严重 |
| 14 | Ordered Logit | 截距与阈值不可识别，阈值无排序约束 | 严重 |
| 24 | Runtime robust | `robust` 可能静默退化为 classical SE | 严重 |
| 25 | `xtivreg` | 命令丢失 IV 语义，实际不是 panel IV | 严重 |
| 27 | TimeSeries runtime | 包内模型与命令执行链路断裂 | 严重 |
| 7 | Panel FE | 自由度未扣减固定效应，标准误偏小 | 严重 |
| 11 | Panel IV | 未组内变换，是 Pooled IV | 严重 |
| 15 | MLogit | one-vs-rest 不是 MNL MLE | 严重 |
| 17 | PP test | p 值使用错误分布 | 严重 |
| 22 | Survey GLM | 未加权点估计加近似方差，不是调查 GLM | 严重 |
| 2 | IV 第一阶段 | 弱工具变量 F 统计量可能高估 | 严重 |
| 26 | Causal commands | 缺少 propensity/outcome 公式 | 严重 |

### 中等问题

| # | 模块 | 问题 |
| --- | --- | --- |
| 1 | WLS predict | 预测区间 bread 口径错误 |
| 3 | IV HC1 | 2SLS sandwich 近似 |
| 4 | GLS | R² 和预测区间口径不清 |
| 6 | DW | p 值正态近似过粗 |
| 8 | Panel RE | Mundlak 与标准 GLS-RE 语义混淆 |
| 10 | Hausman | 对角近似且受 RE 实现影响 |
| 16 | NegBin | `alpha` 网格过粗 |
| 18 | Johansen | 临界值硬编码且维度受限 |
| 19 | DID/TWFE | 聚类 score 与吸收估计不一致 |
| 21 | AIPW | 结果模型未按处理组拟合 |
| 23 | Survey OLS | 缺失行过滤后权重可能错位 |
| 28 | Diagnostics commands | 命令解析与执行断层 |

### 轻微问题

| # | 模块 | 问题 |
| --- | --- | --- |
| 5 | White | 自由度计算不完整 |
| 9 | Driscoll-Kraay | 不平衡面板得分处理可能不一致 |
| 12 | BP-LM | `T_star` 计算但未使用 |
| 20 | IPW | ATU 标准误字段错误 |

---

## 十、推荐修复顺序

1. **先修协议静默错误：** `robust` 大小写归一化、`xtivreg` 路由、TimeSeries/Causal 命令 schema。原因是这些问题会让用户“以为运行了某模型”，但实际运行了不同模型。
2. **再修会产生明显错误结果的估计器：** Poisson IRLS、Ordered Logit、Survey GLM、Panel FE 自由度、Panel IV 组内变换。
3. **随后修推断完善度：** IV 第一阶段 F、DID/TWFE cluster、AIPW 结果模型、PP/Johansen 临界值。
4. **最后处理展示与边界口径：** WLS/GLS predict、DW 近似标注、White 自由度、DK 不平衡面板、BP-LM `T_star`。

---

## 十一、做得好的部分

- OLS 核心估计、HC1、Cluster、条件数检查和教学警告体系方向可靠。
- Breusch-Pagan、Breusch-Godfrey、RESET、Jarque-Bera 的核心统计量实现清晰。
- Logit/Probit 的二元响应路径和边际效应 Delta method 方向正确。
- ADF 委托成熟库、ARIMA MLE 委托 `StateSpaceModels.jl` 是正确工程选择。
- VAR 的方程 OLS、伴随矩阵稳定性检测和 Cholesky IRF 方向合理。
- FD、Between、CRE、HDFE 面板估计器的总体方向与项目架构一致。
- 项目已经坚持结构化结果、警告和模型协议的方向；当前最需要补强的是“命令到估计器”的一致性与若干关键模型的识别/方差口径。
