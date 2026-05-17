# 发布流程

Metrica 当前采用手动 release 流程。暂不引入自动发布流水线，避免在质量信号尚未完全稳定前增加维护负担。

## 发布前

1. 根据 [版本策略](versioning.md) 选择版本号。
2. 完成 [发布前质量门禁](../quality/release-checklist.md)。
3. 更新 `CHANGELOG.md`，明确新增、修复、破坏性变更和已知限制。
4. 更新 `CITATION.cff` 的 `version` 与 `date-released`。
5. 确认 README、SUPPORT、SECURITY 和质量文档没有过度宣称。

## 发布命令

发布者在本地完成验证后创建 tag：

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

随后在 GitHub 创建 release，release notes 应包含：

- 版本摘要
- 主要变更
- 破坏性变更
- 已运行的质量门禁
- 未解决的已知限制

## 不做的事

当前阶段不自动发布 Julia 包、不自动签名桌面 App、不自动生成安装包，也不承诺 GitHub release 等同于正式研究可用版本。
