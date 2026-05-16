# S5.2 差分动态面板 GMM（Arellano–Bond）教程

## 前置条件

- 已启动 Metrica Runtime（HTTP 与本仓库 Julia 桥接/守护进程已就绪）。
- 数据集为**短面板** CSV：含个体列、时间列、因变量 \(y\) 及严格外生解释变量。

## CLI 示例（桌面应用命令行）

```text
use datasets/demo/dynamic_panel_gmm_demo.csv
xtabond y x, id(firm) time(year) lags(2 4) weight(two_step)
```

- `id` / `time`：面板索引，**必填**。
- `lags(min max)`：**必填**（与 Runtime `instrument_lags` 对齐）；省略时解析器会默认 `[2, 4]`，但建议显式写出。
- `weight(one_step|two_step)`：可选，与 `gmm_linear` 一致。
- `style(difference|system)`：可选；首期仅 `difference` 有实现，`system` 将在 Julia 端返回「未实现」结构化错误。
- `collapse(true|false)`：可选；首期未实现，传 `true` 将报错。

## 与 `xtivreg` 的区别

- `xtivreg` 为**静态**面板 IV（去均值 2SLS）；`xtabond` 为**动态**设定下的一阶差分 GMM，工具由**因变量水平滞后层**生成，不由 `instruments(...)` 列表手工指定。

## 结果解读（结构化 `diagnostics`）

- **Hansen J**：过识别检验；矩条件过多、短面板时需谨慎解读。
- **AR(1) / AR(2)**：对**一阶差分残差**的序列相关检验；AR(1) 显著在差分设定下较常见，更应关注 AR(2)。
- **`n_obs_diff`**：参与估计的差分堆叠行数，通常小于原面板行数。

## 与总规、协议文档的关系

- 总规：`S5-高级研究专题总施工规划.md` §5。
- 协议字段与键名定稿：`docs/architecture/runtime-protocol.md` 中 `dynamic_panel_gmm` 专节。
