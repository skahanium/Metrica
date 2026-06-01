# Golden-Value 验证政策

Golden-value 测试用于证明 Metrica 的结构化结果与确定性参考值一致。第一阶段先建立格式和 OLS 样例，不追求一次覆盖全部模型族。

## 文件布局

- 数据：`datasets/golden/<case>.csv`
- 参考值：`datasets/golden/<case>.json`
- 测试入口：对应包的 `test/runtests.jl`

## JSON 字段

每个 golden JSON 必须包含：

- `id`：稳定用例名。
- `dataset`：相对 `datasets/` 的路径。
- `model_type`：协议中的模型类型。
- `formula` 或等价模型配置。
- `reference`：参考来源、生成日期、注意事项。
- `tolerances`：按字段类别声明绝对容差。
- `expected`：结构化期望值，至少覆盖 `glance`、核心 `metrics` 和核心 `tidy` 字段。

## 容差规则

- 协议字段、模型标签、样本量、自由度必须精确匹配。
- 系数、标准误、统计量、拟合指标使用显式 `atol`，不得隐藏在测试代码中。
- 随机或 MCMC 路径必须固定 seed，或只验证 R-hat、ESS、均值区间等稳定摘要。
- 如果参考值来自 Metrica 自身，必须在 `reference.notes` 中说明，后续再替换或补充外部软件对齐。

## 第一批覆盖

| Area | Status | Reference target |
|---|---|---|
| OLS | covered | 独立 complete-case OLS 参考（`scripts/golden/compute_ols_reference.jl`），与 R `lm` 数值等价 |
| IV / GLS | covered | 独立 complete-case 2SLS / GLS 参考（`scripts/golden/compute_iv_reference.jl`、`scripts/golden/compute_gls_reference.jl`） |
| Logit / Probit / Poisson | planned | R `glm` |
| ARIMA / VAR / unitroot | planned | 公开稳定示例或主流生态实现 |
| GMM / dynamic panel / spatial / bayes | planned | 先登记缺口，再分模型族补齐 |

## 未来事项

### Rust params 强类型 wire 格式

当前 `ModelSpec.params` 在 Rust 侧为 `serde_json::Value`，校验后收敛为 `ValidatedModelParams` 枚举。编译期族内字段安全已在 Rust 解析层保障，wire JSON 层不做额外编解码约束。未来可将 `Value` 替换为 serde 标签枚举，使族参数形状在反序列化阶段即获得类型安全。该改动破坏性小（TS 侧已发送结构化 `ModelFamilyParams`）、对现有校验路径无感知影响。延后至下一开发阶段考虑。
