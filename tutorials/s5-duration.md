# S5.8 久期模型：Cox 比例风险（首期）

本教程对应 `model_type: "duration_cox"` 与 App / CLI 动词 **`stcox`**。阅读前请已加载演示数据：

```text
use datasets/demo/duration_demo.csv
```

数据列含义：

- `time`：随访时间（须为正实数；右删失下为观察到的时间）。
- `fail`：事件指示（**1=事件发生，0=删失**）；亦支持布尔列。
- `x1`：协变量示例。

## 1. 命令形态

```text
stcox time fail x1
```

解析规则：

- 第 1 个位置参数 → `duration_time_column`
- 第 2 个位置参数 → `duration_event_column`
- 其余位置参数 → 协变量，拼为公式 **`ph ~ x1 + ...`**（`ph` 为占位，数据**不需要**名为 `ph` 的列）。

## 2. 与 OLS 系数的差别

- `tidy` 表中的 **`estimate` 为 log(风险比)**，即文献中的 \(\hat\beta\)。
- 顶层载荷中的 **`hazard_ratios`** 给出 **HR** 及基于正态近似的 **95% CI**（教学上更直观）。
- 删失比例、事件数等见 `result_payload.diagnostics`。

## 3. 首期限制与错误路径

- 时间须 **> 0**；负时间、非有限时间会返回结构化错误。
- 事件列仅接受 **0/1**（或布尔）；其它取值会报错。
- 若事件列**全为 0**（无事件），拟合会失败并给出明确提示。
- 并列事件时间采用 **Breslow** 近似（见 `diagnostics.risk_set_ties_method`）。
- **比例风险（PH）检验** 字段 `ph_diagnostics` 首期为 **`null`**，二期可填 Schoenfeld 等。

## 4. 复现检查清单

1. 执行 `stcox time fail x1`，确认结果含 `hazard_ratios` 与 `diagnostics.n_events`。
2. 将 `fail` 全改为 `0`，确认出现「无事件」类错误信息（结构化 `messages`）。
