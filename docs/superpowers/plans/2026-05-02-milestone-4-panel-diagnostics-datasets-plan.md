# 里程碑 4 实施计划：面板诊断与教学数据集

> **状态：当前实施依据。** 本计划定义里程碑 4 的第一个垂直切片：在已贯通的面板模型链路上增加结构化诊断，并补充可追踪的教学数据集入口。

**目标：** 实现 Hausman、固定效应 F、Breusch-Pagan LM 三类面板诊断，并新增 Penn World Table 教学面板子集与 NLSY 导入模板。

**架构：** 诊断计算属于 `MetricaPanel.jl`，Runtime 只转发结构化结果，App 只展示 `diagnostics` payload，不解析文本摘要。

## 实施步骤

- [x] 新增 `MetricaPanel.jl` 面板诊断入口 `panel_diagnostics(panel_data, formula)`
- [x] 实现 Hausman（FE vs RE）教学口径结构化诊断
- [x] 实现 pooled OLS vs FE 的固定效应 F 检验
- [x] 实现平衡面板 Breusch-Pagan LM 随机效应检验
- [x] 在 Runtime Julia bridge / daemon 中附加面板诊断 payload
- [x] 在 App 诊断区展示 Hausman / F / LM 结果与不可用说明
- [x] 新增 PWT 10.01 教学子集与元数据
- [x] 新增 PWT 教学数据生成脚本
- [x] 新增 NLSY public-use 导入模板脚本与元数据模板
- [x] 补充 Julia、Runtime、App 测试

## 验收标准

1. 面板模型响应包含 `diagnostics.hausman`、`diagnostics.fixed_effect_f`、`diagnostics.breusch_pagan_lm`
2. 不平衡面板 LM 返回 `available = false` 与教学说明
3. PWT 教学子集可用于 FE 面板拟合与诊断
4. App 可渲染可用诊断和不可用诊断
5. `cargo test`、`npm test`、`MetricaPanel.jl` 测试通过

## 后续切片

1. 将 Hausman 从对角近似升级为完整协方差矩阵口径
2. 增加面板诊断解释卡片与教学链接
3. 根据用户选择的 NLSY Investigator 导出生成真实 NLSY 教学子集
4. 评估是否进入 IV / GLS 或动态面板 GMM
