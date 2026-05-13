# 全模型输出指标补全 + use 命令 UX 修复 实施方案

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补全所有计量模型缺失的专业指标（95% CI、F/Wald/LR 检验、ANOVA 表、模型特有诊断），并修复 use 命令的 UX 问题，使 Metrica 输出达到 Stata 专业水准。

**Architecture:** 分三层修改——(1) MetricaBase 协议层扩展 CoefRow/ModelGlance 结构体，(2) 各计量包计算并序列化新指标，(3) 前端渲染新指标。use 命令修复在前端执行层完成。

**Tech Stack:** Julia (MetricaBase, MetricaLinear, MetricaPanel, MetricaDiscrete, MetricaTimeSeries, MetricaCausal, MetricaSurvey), TypeScript (React, commandExecutor, protocol types)

---

## 阶段一：协议层基础设施

### Task 1: CoefRow 添加置信区间字段

**文件：**
- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl:168-174`

**当前状态：**
```julia
struct CoefRow
    name::Symbol
    estimate::Float64
    stderror::Union{Nothing, Float64}
    statistic::Union{Nothing, Float64}
    pvalue::Union{Nothing, Float64}
end
```

**目标状态：**
```julia
struct CoefRow
    name::Symbol
    estimate::Float64
    stderror::Union{Nothing, Float64}
    statistic::Union{Nothing, Float64}
    pvalue::Union{Nothing, Float64}
    ci_lower::Union{Nothing, Float64}
    ci_upper::Union{Nothing, Float64}
end
```

- [ ] 修改 CoefRow 结构体，添加 ci_lower 和 ci_upper 字段
- [ ] 搜索所有 `CoefRow(` 构造调用，添加 `nothing, nothing` 默认值
- [ ] 运行 `julia --project=packages/MetricaBase.jl -e 'using MetricaBase; println("OK")'` 验证编译通过

### Task 2: 实现通用 confint 函数

**文件：**
- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl` — 添加 confint 函数

**实现：**
```julia
"""
    confint(result; level=0.95)

计算系数的置信区间。返回 (ci_lower, ci_upper) 向量。
默认 95% 置信水平。
"""
function confint(result; level::Float64=0.95)
    coef_vals = coef(result)
    se_vals = stderror(result)
    nobs_val = nobs(result)
    dof_val = dof(result)

    if isnothing(se_vals)
        return (fill(nothing, length(coef_vals)), fill(nothing, length(coef_vals)))
    end

    α = 1 - level
    t_crit = quantile(TDist(dof_val), 1 - α/2)

    ci_lower = coef_vals .- t_crit .* se_vals
    ci_upper = coef_vals .+ t_crit .* se_vals
    return (ci_lower, ci_upper)
end
```

- [ ] 在 MetricaBase.jl 中添加 confint 函数
- [ ] 导出 confint 符号
- [ ] 运行编译验证

### Task 3: ModelGlance 扩展标准键名约定

**文件：**
- Modify: `packages/MetricaBase.jl/src/MetricaBase.jl` — 添加文档注释

**标准键名约定（文档化）：**
```julia
# ModelGlance.metrics 标准键名约定：
#
# 线性模型（OLS/WLS/IV/GLS）：
#   :r2, :adj_r2, :rss, :tss, :sigma, :f_stat, :f_pvalue, :model_ss, :model_df, :model_ms, :resid_ss, :resid_df, :resid_ms, :total_ss, :total_df, :total_ms
#
# 面板模型（FE/RE/FD/Between/CRE/HDFE）：
#   :r2, :adj_r2, :rss, :tss, :sigma, :f_stat, :f_pvalue, :n_ids, :n_times, :r2_within, :r2_between, :r2_overall, :rho, :sigma_u, :sigma_e
#
# 离散模型（Logit/Probit/Poisson/NegBin）：
#   :pseudo_r2, :loglik, :aic, :bic, :deviance, :lr_chi2, :lr_pvalue, :iterations, :converged
#
# 时间序列（ARIMA/VAR）：
#   :loglik, :aic, :bic, :sigma2, :ljung_box_stat, :ljung_box_pvalue
#
# 因果推断（DID/IPW/PSM/AIPW）：
#   :ate, :att, :atu, :ate_se, :att_se, :atu_se
#
# 调查模型（Survey OLS/Logit/Probit/Poisson）：
#   :r2/:pseudo_r2, :loglik, :aic, :bic, :mean_deff, :wald_f, :wald_pvalue
```

- [ ] 在 ModelGlance 结构体上方添加标准键名约定文档
- [ ] 运行编译验证

### Task 4: 前端协议类型扩展

**文件：**
- Modify: `apps/metrica-desktop/src-react/types/protocol.ts` — TidyRow 添加 ci_lower/ci_upper

**当前状态：**
```typescript
export interface TidyRow {
  name: string;
  estimate: number;
  stderror?: number;
  statistic?: number;
  pvalue?: number;
  ci_lower?: number;  // 已预留但从未填充
  ci_upper?: number;  // 已预留但从未填充
}
```

- [ ] 确认 TidyRow 已有 ci_lower/ci_upper 字段（已预留）
- [ ] 确认 GlanceMetrics 类型支持新键名
- [ ] 运行 `cd apps/metrica-desktop && npx tsc --noEmit` 验证类型检查

---

## 阶段二：线性模型族（OLS/WLS/IV/GLS）

### Task 5: OLS/WLS 补全 F 检验和 ANOVA 表

**文件：**
- Modify: `packages/MetricaLinear.jl/src/ols.jl:440-465` — fit 函数
- Modify: `packages/MetricaLinear.jl/src/serialize.jl:52-58` — glance 序列化

**计算公式：**
```julia
# F 检验
k = length(coefficients)  # 含截距
model_ss = tss - rss
model_df = k - 1  # 不含截距的自由度（或 k-1 for 有截距模型）
resid_df = dof
f_stat = (model_ss / model_df) / (rss / resid_df)
f_pvalue = 1 - cdf(FDist(model_df, resid_df), f_stat)

# ANOVA 表
model_ms = model_ss / model_df
resid_ms = rss / resid_df
total_ms = tss / (nobs - 1)
```

- [ ] 在 ols.jl 的 fit 函数中计算 f_stat, f_pvalue, model_ss, model_df, model_ms, resid_ms, total_ss, total_df, total_ms
- [ ] 添加到 ModelGlance.metrics
- [ ] 在 serialize.jl 中序列化新指标
- [ ] 添加测试：验证 F 统计量与 Stata 输出一致
- [ ] 运行 `julia --project=packages/MetricaLinear.jl -e 'using Pkg; Pkg.test()'`

### Task 6: OLS/WLS 补全 95% 置信区间

**文件：**
- Modify: `packages/MetricaLinear.jl/src/ols.jl:364-386` — assemble_tidy_table 函数

**实现：**
```julia
function assemble_tidy_table(coefficients, stderror, coefficient_names, dof, vcov)
    α = 0.05
    t_crit = quantile(TDist(dof), 1 - α/2)

    rows = CoefRow[]
    for i in eachindex(coefficients)
        se_i = stderror[i]
        t_stat = coefficients[i] / se_i
        p_val = 2 * (1 - cdf(TDist(dof), abs(t_stat)))
        ci_l = coefficients[i] - t_crit * se_i
        ci_u = coefficients[i] + t_crit * se_i
        push!(rows, CoefRow(coefficient_names[i], coefficients[i], se_i, t_stat, p_val, ci_l, ci_u))
    end
    vcov_label = vcov === :HC1 ? "HC1" : vcov === :cluster ? "cluster" : "classical"
    return TidyTable(rows, vcov_label)
end
```

- [ ] 修改 assemble_tidy_table 计算并填充 ci_lower, ci_upper
- [ ] 运行测试验证

### Task 7: IV/2SLS 补全置信区间和 F 检验

**文件：**
- Modify: `packages/MetricaLinear.jl/src/iv.jl:230-265` — fit 函数

- [ ] 在 iv.jl 的 tidy 构造中计算 ci_lower, ci_upper
- [ ] 添加结构方程整体 F 检验
- [ ] 运行测试验证

### Task 8: GLS 补全置信区间和 Wald 检验

**文件：**
- Modify: `packages/MetricaLinear.jl/src/gls.jl`

- [ ] 在 gls.jl 的 fit 函数中计算 ci_lower, ci_upper
- [ ] 添加 Wald 检验
- [ ] 运行测试验证

---

## 阶段三：面板模型族

### Task 9: Panel FE/RE/FD/Between/CRE 补全 loglikelihood/aic/bic

**文件：**
- Modify: `packages/MetricaPanel.jl/src/fe.jl`
- Modify: `packages/MetricaPanel.jl/src/re.jl`
- Modify: `packages/MetricaPanel.jl/src/fd.jl`
- Modify: `packages/MetricaPanel.jl/src/between.jl`
- Modify: `packages/MetricaPanel.jl/src/cre.jl`
- Modify: `packages/MetricaPanel.jl/src/serialize.jl`

**计算公式：**
```julia
# loglikelihood (正态假设)
n = nobs
loglik = -n/2 * (1 + log(2π) + log(rss/n))

# AIC/BIC
k = length(coefficients) + 1  # 含截距
aic = -2 * loglik + 2 * k
bic = -2 * loglik + k * log(n)
```

- [ ] 在每个面板模型的 fit 函数中计算 loglik, aic, bic
- [ ] 在 serialize.jl 中序列化 loglik, aic, bic
- [ ] 运行测试验证

### Task 10: Panel RE 补全 rho/sigma_u/sigma_e

**文件：**
- Modify: `packages/MetricaPanel.jl/src/re.jl`
- Modify: `packages/MetricaPanel.jl/src/serialize.jl`

**计算公式：**
```julia
# 方差分量
sigma_e² = rss / dof  # 残差方差
sigma_u² = (tss - rss) / (n_ids - 1) - sigma_e² / n_times  # 个体效应方差
sigma_u² = max(sigma_u², 0.0)
rho = sigma_u² / (sigma_u² + sigma_e²)
sigma_u = sqrt(sigma_u²)
sigma_e = sqrt(sigma_e²)
```

- [ ] 在 re.jl 中计算 rho, sigma_u, sigma_e
- [ ] 在 serialize.jl 中序列化
- [ ] 运行测试验证

### Task 11: Panel FE/RE 补全 within/between/overall R²

**文件：**
- Modify: `packages/MetricaPanel.jl/src/fe.jl`
- Modify: `packages/MetricaPanel.jl/src/re.jl`

**计算公式：**
```julia
# Within R² (FE 特有)
r2_within = 1 - rss / tss_within

# Between R²
r2_between = 1 - rss_between / tss_between

# Overall R²
r2_overall = 1 - rss / tss
```

- [ ] 在 fe.jl 和 re.jl 中计算三种 R²
- [ ] 在 serialize.jl 中序列化
- [ ] 运行测试验证

### Task 12: Panel 补全置信区间

**文件：**
- Modify: `packages/MetricaPanel.jl/src/MetricaPanel.jl` — assemble_tidy_table 或等价函数

- [ ] 在面板模型的 tidy 构造中计算 ci_lower, ci_upper
- [ ] 运行测试验证

### Task 13: Panel IV 补全 result_to_payload（当前丢失 first_stage_stats）

**文件：**
- Modify: `packages/MetricaPanel.jl/src/serialize.jl` — 为 PanelIVFitResult 添加专用序列化

- [ ] 检查 PanelIVFitResult 是否有专用 result_to_payload
- [ ] 如果没有，添加专用序列化函数，保留 first_stage_stats 和 weak_instrument_warnings
- [ ] 运行测试验证

---

## 阶段四：离散模型族

### Task 14: 所有离散模型补全置信区间

**文件：**
- Modify: `packages/MetricaDiscrete.jl/src/logit.jl`
- Modify: `packages/MetricaDiscrete.jl/src/probit.jl`
- Modify: `packages/MetricaDiscrete.jl/src/poisson.jl`
- Modify: `packages/MetricaDiscrete.jl/src/negbin.jl`
- Modify: `packages/MetricaDiscrete.jl/src/ologit.jl`
- Modify: `packages/MetricaDiscrete.jl/src/mlogit.jl`

**实现：** 在每个模型的 tidy 构造中计算 ci_lower, ci_upper。

- [ ] 修改 logit.jl 的 tidy 构造
- [ ] 修改 probit.jl 的 tidy 构造
- [ ] 修改 poisson.jl 的 tidy 构造
- [ ] 修改 negbin.jl 的 tidy 构造
- [ ] 修改 ologit.jl 的 tidy 构造
- [ ] 修改 mlogit.jl 的 tidy 构造
- [ ] 运行测试验证

### Task 15: Logit/Probit/Poisson/NegBin 补全 LR chi2

**文件：**
- Modify: `packages/MetricaDiscrete.jl/src/logit.jl`
- Modify: `packages/MetricaDiscrete.jl/src/probit.jl`
- Modify: `packages/MetricaDiscrete.jl/src/poisson.jl`
- Modify: `packages/MetricaDiscrete.jl/src/negbin.jl`

**计算公式：**
```julia
# LR 检验
ll_null = null_loglikelihood(y)  # 仅截距模型的对数似然
ll_full = loglikelihood
lr_chi2 = 2 * (ll_full - ll_null)
lr_pvalue = 1 - cdf(Chisq(length(coefficients)), lr_chi2)
```

- [ ] 在每个离散模型中计算 lr_chi2, lr_pvalue
- [ ] 添加到 ModelGlance.metrics
- [ ] 运行测试验证

### Task 16: OrderedLogit/MultinomialLogit/NegBin 添加 result_to_payload

**文件：**
- Modify: `packages/MetricaDiscrete.jl/src/serialize.jl`

- [ ] 为 OrderedLogitFitResult 添加 result_to_payload 函数
- [ ] 为 MultinomialLogitFitResult 添加 result_to_payload 函数
- [ ] 为 NegBinFitResult 添加 result_to_payload 函数
- [ ] 运行测试验证

---

## 阶段五：时间序列模型族

### Task 17: ARIMA 补全 Ljung-Box 检验

**文件：**
- Modify: `packages/MetricaTimeSeries.jl/src/arima.jl`

**计算公式：**
```julia
# Ljung-Box Q 统计量
function ljung_box_test(residuals::Vector{Float64}, lags::Int)
    n = length(residuals)
    acf_vals = autocor(residuals, 1:lags)
    Q = n * (n + 2) * sum(acf_vals[k]^2 / (n - k) for k in 1:lags)
    p_value = 1 - cdf(Chisq(lags), Q)
    return (Q, p_value)
end
```

- [ ] 在 arima.jl 的 fit 函数中计算 Ljung-Box Q 和 p 值
- [ ] 添加到 ModelGlance.metrics
- [ ] 运行测试验证

### Task 18: VAR 补全 Granger/IRF/FEVD 序列化

**文件：**
- Modify: `packages/MetricaTimeSeries.jl/src/var.jl`

- [ ] 检查 granger_causality() 函数是否存在
- [ ] 将 Granger 因果检验结果纳入 payload
- [ ] 将 IRF 结果纳入 payload
- [ ] 将方差分解结果纳入 payload
- [ ] 运行测试验证

### Task 19: ARIMA/VAR 补全置信区间

**文件：**
- Modify: `packages/MetricaTimeSeries.jl/src/arima.jl`
- Modify: `packages/MetricaTimeSeries.jl/src/var.jl`

- [ ] 在 ARIMA 的 tidy 构造中计算 ci_lower, ci_upper
- [ ] 在 VAR 的 tidy 构造中计算 ci_lower, ci_upper
- [ ] 运行测试验证

---

## 阶段六：因果推断和调查模型

### Task 20: DID/EventStudy 补全 R²/F 统计量

**文件：**
- Modify: `packages/MetricaCausal.jl/src/did.jl`
- Modify: `packages/MetricaCausal.jl/src/event_study.jl`

- [ ] 在 DID 的 fit 函数中计算 R² 和 F 统计量
- [ ] 在 EventStudy 的 fit 函数中计算 R² 和 F 统计量
- [ ] 运行测试验证

### Task 21: 所有因果模型补全置信区间

**文件：**
- Modify: `packages/MetricaCausal.jl/src/did.jl`
- Modify: `packages/MetricaCausal.jl/src/event_study.jl`
- Modify: `packages/MetricaCausal.jl/src/ipw.jl`
- Modify: `packages/MetricaCausal.jl/src/psm.jl`
- Modify: `packages/MetricaCausal.jl/src/doubly_robust.jl`

- [ ] 在每个因果模型的 tidy 构造中计算 ci_lower, ci_upper
- [ ] 运行测试验证

### Task 22: Survey 模型补全 Wald F 检验

**文件：**
- Modify: `packages/MetricaSurvey.jl/src/survey_ols.jl`
- Modify: `packages/MetricaSurvey.jl/src/survey_glm.jl`

**计算公式：**
```julia
# Survey-adjusted Wald F 检验
# 使用 sandwich 方差和 F 分布
wald_f = (coefficients' * inv(vcov_matrix) * coefficients) / length(coefficients)
wald_pvalue = 1 - cdf(FDist(length(coefficients), dof), wald_f)
```

- [ ] 在 survey_ols.jl 中计算 Wald F
- [ ] 在 survey_glm.jl 中计算 Wald chi2
- [ ] 在 serialize.jl 中序列化
- [ ] 运行测试验证

### Task 23: Survey 模型补全置信区间

**文件：**
- Modify: `packages/MetricaSurvey.jl/src/survey_ols.jl`
- Modify: `packages/MetricaSurvey.jl/src/survey_glm.jl`

- [ ] 在 Survey 模型的 tidy 构造中计算 ci_lower, ci_upper
- [ ] 运行测试验证

---

## 阶段七：前端展示

### Task 24: 前端结果展示渲染新指标

**文件：**
- Modify: 前端结果展示组件（需要检查具体组件路径）

**需要渲染的新指标：**
- ANOVA 表（Model SS/df/MS, Residual SS/df/MS, Total SS/df/MS）
- 整体检验（F/Wald/LR 统计量 + p 值）在 glance 区域展示
- 置信区间在 tidy 表中展示（ci_lower, ci_upper 列）
- 模型特有指标（rho, sigma_u, sigma_e, within/between/overall R²）在 glance 区域展示

- [ ] 检查前端结果展示组件
- [ ] 添加 ANOVA 表渲染
- [ ] 添加整体检验渲染
- [ ] 添加置信区间列渲染
- [ ] 添加模型特有指标渲染
- [ ] 运行 `cd apps/metrica-desktop && npm run build` 验证

---

## 阶段八：use 命令 UX 修复

### Task 25: use 命令需要两次回车问题

**文件：**
- Modify: `apps/metrica-desktop/src-react/components/CommandLine.tsx:464-470` — Enter 键处理

**根因：** 当输入完全匹配某个命令动词时，补全菜单仍然显示（因为 `use` 以 `use` 开头），第一次 Enter 选择补全项，第二次才执行。

**修复方案：** 在 Enter 键处理中，如果输入完全匹配某个命令动词且没有更多位置参数需要补全，直接执行命令。

```typescript
// 当前代码
if (e.key === 'Enter' && !showCompletions) {
    e.preventDefault();
    const trimmed = input.trim();
    if (trimmed) {
        submitCommand(trimmed);
    }
}

// 修改后：如果输入完全匹配命令动词，直接执行
if (e.key === 'Enter') {
    const trimmed = input.trim();
    // 如果补全菜单显示但输入完全匹配命令动词，直接执行
    if (showCompletions && trimmed && isCompleteCommand(trimmed)) {
        e.preventDefault();
        hideCompletions();
        submitCommand(trimmed);
        return;
    }
    if (!showCompletions) {
        e.preventDefault();
        if (trimmed) {
            submitCommand(trimmed);
        }
    }
}
```

- [ ] 添加 isCompleteCommand 辅助函数
- [ ] 修改 Enter 键处理逻辑
- [ ] 运行 `cd apps/metrica-desktop && npm run test` 验证

### Task 26: use 命令导入成功反馈和自动 describe

**文件：**
- Modify: `apps/metrica-desktop/src-react/services/commandExecutor.ts:49-102` — handleUse 函数

**变更：**
1. 成功加载后调用 `feedback('success', ...)` 显示导入成功提示
2. 自动调用 `api.describeDataset()` 获取数据集信息并推入消息流
3. 错误时调用 `feedback('error', ...)` 向 CLI 反馈
4. `use clear` 成功后反馈"已清空当前数据集"

```typescript
// 成功路径示例
const r = await api.inspectDataset(filePath);
const ds = useDatasetStore.getState();
ds.setSourceAndActivePath(filePath, filePath);
ds.setSummary(r);
ds.clearBrowseContext();
useAppStore.getState().setDataFullscreen(false);
setError(null);

// 新增：成功反馈
const fileName = filePath.split('/').pop() || filePath;
feedback('success', `已加载 ${fileName}（${r.nrows} 行 × ${r.ncols} 列）`);

// 新增：自动 describe
try {
    const desc = await api.describeDataset(filePath);
    // 推入消息流（不显示 describe 命令本身）
    addMessageToFlow({ type: 'data', command: 'describe', result: desc });
} catch (_) { /* describe 失败不影响主流程 */ }
```

- [ ] 修改 handleUse 成功路径，添加 feedback 调用
- [ ] 修改 handleUse 错误路径，添加 feedback 调用
- [ ] 修改 handleUse clear 路径，添加 feedback 调用
- [ ] 添加自动 describe 调用
- [ ] 运行 `cd apps/metrica-desktop && npm run test` 验证

---

## 验证策略

每个 Task 完成后：
1. 运行相关包的测试套件
2. 对比 Stata 输出验证数值一致性（关键模型）
3. 运行前端 TypeScript 编译检查

## 依赖关系

```
阶段一（协议层）→ 阶段二~六（各模型族，可并行）→ 阶段七（前端渲染）→ 阶段八（use 命令）
```

## 预估工作量

| 阶段 | Tasks | 预估时间 |
|------|-------|----------|
| 一：协议层 | 1-4 | 0.5 天 |
| 二：线性模型 | 5-8 | 1 天 |
| 三：面板模型 | 9-13 | 1 天 |
| 四：离散模型 | 14-16 | 1 天 |
| 五：时间序列 | 17-19 | 0.5 天 |
| 六：因果/调查 | 20-23 | 0.5 天 |
| 七：前端渲染 | 24 | 0.5 天 |
| 八：use 命令 | 25-26 | 0.5 天 |
| **总计** | **26** | **5.5 天** |
