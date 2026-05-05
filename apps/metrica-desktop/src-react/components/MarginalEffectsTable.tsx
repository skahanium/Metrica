import { Card, Typography } from 'antd';
import { useModelStore } from '../stores/modelStore';

export function MarginalEffectsTable() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult) return null;

  const g = lastResult.glance;
  const isDiscrete = ['logit', 'probit'].includes(g.model);
  if (!isDiscrete) return null;

  return (
    <Card size="small" title="边际效应" style={{ marginBottom: 16 }}>
      <Typography.Text type="secondary">
        边际效应（AME/MEM）在 Core 层已就绪，可通过 daemon 扩展端到端展示。
      </Typography.Text>
    </Card>
  );
}
