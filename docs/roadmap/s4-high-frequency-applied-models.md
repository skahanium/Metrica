# `S4` 施工指引：高频应用研究模型

## 阶段目标

`S4` 的目标是覆盖常见应用研究中最常用、教学和论文都高频的模型族，使 Metrica 从“线性与面板工作台”扩展为“常见应用研究工作台”。

## 纳入能力

- GLM / 有限因变量：Logit、Probit、Poisson、边际效应
- 因果推断：DID、event study、IPW、matching、treatment effects
- 基础时间序列：ARIMA、VAR、单位根、协整、预测
- 复杂抽样：pweights、strata、PSU、survey-aware regression

## 明确排除项

- 不以全量跨软件互验或命令覆盖率为目标
- 不提前展开高复杂专题，如动态面板 GMM、SUR、空间、贝叶斯
- 不让 App 退化为通用参数堆叠界面

## 历史映射

- 对应旧 `M10-M13`

## 阶段验收

- 每个模型族至少有一个教学数据集和一个端到端工作流示例
- 输出系统能与 `S1-S3` 的结果对象并列工作
- 结构化 warning 能覆盖该阶段模型族的常见误用
