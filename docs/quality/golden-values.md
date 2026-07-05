# Golden 验证政策

当前仓库已移除所有未经 Stata / statsmodels / R / 闭式公式交叉验证的 `datasets/golden/*.json` 期望结果文件。因此，`datasets/golden/` 目录下现存 CSV **不是已验证 golden 标准答案**，而是后续手动外部验证的输入数据。

## 当前口径

- `datasets/golden/*.csv`：待验证输入数据，地位平等。
- `datasets/golden/*.json`：当前不允许保留；未交叉验证结果不得写入 JSON 并称为 golden。
- `scripts/dev/test-golden.sh`：只检查 `datasets/golden/` 下不存在 JSON 期望文件，并确认 CSV 可解析。
- 包内旧 `test_golden.jl`：已退役，避免继续把内部结果当成标准答案。

## 何时才可称为真正 golden

某个模型或命令路径只有满足以下条件后，才可升级为 external golden：

1. 有固定输入数据。
2. 有 Stata、statsmodels/Python、R 或可审查闭式公式生成的参考结果。
3. 参考结果记录了软件版本、命令、样本处理、容差和比较字段。
4. Metrica 输出与参考结果在明确容差内一致。
5. 文档同步更新 [package-status.md](package-status.md) 与 [credibility-tiers.md](credibility-tiers.md)。

## 手动验证入口

命令级覆盖表见 [manual-golden-command-coverage.md](manual-golden-command-coverage.md)。该表列出每条 Metrica CLI 命令对应的数据路径、Stata 验证方式、statsmodels/Python 验证方式与目标证据类型。

本地检查：

```bash
make test-golden
```

该命令不证明数值正确，只证明当前输入数据目录没有伪 golden JSON，且 CSV 文件可被解析。
