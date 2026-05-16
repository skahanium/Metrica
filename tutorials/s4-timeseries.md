# S4 教学：时间序列（CLI 主路径）

> 约定：在**本仓库根目录**启动应用，或保证 `working_dir` 指向仓库根。

## 数据

- 路径：`datasets/teaching/s4_timeseries_demo.csv`
- 主要列：`time`、`y`、`x1`、`x2`

## 最小命令序列

```text
use "datasets/teaching/s4_timeseries_demo.csv"
describe time y x1 x2
dfuller y, time(time) lags(2) deterministic(constant)
arima y, time(time) ar(1) i(0) ma(0)
var y x1, time(time) lags(1)
```

> 说明：`dfuller` 映射为 `unitroot`；`arima` / `var` 需显式 `time(...)` 以匹配桥接脚本对时间列的要求。

## 预期结构化输出

- 单位根：`glance` / `tidy` 中含检验统计量、p 值、所用滞后等**结构化字段**（具体键名以 `MetricaTimeSeries.result_to_payload` 为准）。
- ARIMA / VAR：`glance.model` 可包含 `arima`、`var` 等子串或规范名；垂直切片见 `runtime/metrica-runtime/tests/vertical_slice.rs`。

## 常见 warning 解读

- 样本短、滞后过大：可能出现不收敛或无效检验；见 `docs/architecture/s4-warning-coverage.md` TimeSeries 一节。

## 导出

```text
runs
export csv_tidy <run_id>, using("exports/arima_tidy.csv")
```
