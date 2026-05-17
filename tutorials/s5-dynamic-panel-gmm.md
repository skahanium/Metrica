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
- `style(difference|system)`：可选；`difference` 为 Arellano-Bond 差分 GMM，`system` 为 Blundell-Bond 系统 GMM（差分+水平方程）。
- `collapse(true|false)`：可选；`true` 时将多级滞后合并为单列工具，缓解工具变量膨胀。

## System GMM 示例

```text
xtabond y x, id(firm) time(year) lags(2 4) style(system) weight(two_step)
```

System GMM 在差分方程基础上增加水平方程，使用滞后差分作为水平方程的工具。当因变量呈随机游走时，水平滞后是差分的弱工具；此时 System GMM 通过增加水平矩条件可提高效率。

## 与 `xtivreg` 的区别

- `xtivreg` 为**静态**面板 IV（去均值 2SLS）；`xtabond` 为**动态**设定下的一阶差分 GMM，工具由**因变量水平滞后层**生成，不由 `instruments(...)` 列表手工指定。

## 结果解读（结构化 `diagnostics`）

- **Hansen J**：过识别检验；矩条件过多、短面板时需谨慎解读。
- **AR(1) / AR(2)**：对**一阶差分残差**的序列相关检验；AR(1) 显著在差分设定下较常见，更应关注 AR(2)。
- **Diff-Hansen**：仅 System GMM 输出；检验新增水平矩条件的有效性。p < 0.05 提示新增工具可能无效。
- **`n_obs_diff`**：参与估计的差分堆叠行数，通常小于原面板行数。
- **dpgmm_style**：`difference` 或 `system`，标明当前估计方法。
- **collapse_instruments**：布尔值，标明是否启用工具折叠。

## 模型选择建议

| 场景 | 推荐 |
|------|------|
| 因变量高度持久（接近单位根） | System GMM |
| 样本 T 较短（< 5） | System GMM |
| 截面 N 较小（< 30） | 谨慎；GMM 渐近性不适用 |
| 工具变量过多（L > N） | 启用 `collapse` 或收紧 `lags` 上限 |

## 与总规、协议文档的关系

- 总规：`docs/roadmap/s5-advanced-research-topics.md(已删除)` §5。
- 协议字段与键名定稿：`docs/architecture/runtime-protocol.md` 中 `dynamic_panel_gmm` 专节。
