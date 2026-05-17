# 决策记录流程

Metrica 使用轻量 ADR/RFC 流程记录少数重要决策。普通 Bug 修复、测试补充和文档改进不需要写决策记录。

## 什么时候需要记录

以下变更需要先写 Issue 或决策记录：

- Core / Runtime / App 边界调整。
- Runtime 协议、结构化结果字段或 `model_type` 语义变化。
- 版本策略、支持策略、维护者权限或发布流程变化。
- 破坏性变更。
- 会显著增加长期维护成本的自动化或新子系统。

## 存放位置

已接受的记录放在 `docs/governance/records/`，文件名格式为：

```text
YYYY-MM-DD-short-title.md
```

## 模板

```markdown
# 决策：标题

日期：YYYY-MM-DD
状态：proposed | accepted | superseded

## 背景

为什么现在需要做决定。

## 决定

最终选择是什么。

## 权衡

保留主要收益、成本和被放弃的替代方案。

## 影响

影响哪些包、协议、文档、测试或发布流程。
```

状态为 `accepted` 的记录代表当前项目规则。若未来改变，应新增记录并标明取代关系，而不是直接抹掉历史。
