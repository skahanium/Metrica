import { useModelStore } from '../stores/modelStore';
import { EmptyState } from './EmptyState';
import { Descriptions, Card } from 'antd';
import type { GlanceResult } from '../types/protocol';

const METRIC_LABELS: Record<string, string> = {
  r2: 'R²',
  adj_r2: '调整 R²',
  sigma: '残差标准误',
  rss: 'RSS',
  tss: 'TSS',
  n_ids: '个体数',
  n_times: '时期数',
};

function formatMetric(key: string, value: number): string {
  if (['r2', 'adj_r2'].includes(key)) return value.toFixed(4);
  if (key === 'sigma') return value.toFixed(4);
  if (['rss', 'tss'].includes(key)) return value.toFixed(2);
  if (['n_ids', 'n_times'].includes(key)) return String(Math.round(value));
  return value.toFixed(4);
}

export function GlanceTable() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult) return <EmptyState title="尚未运行模型" description="请配置参数后点击运行。" />;

  const { glance } = lastResult;

  return (
    <Card size="small">
      <Descriptions bordered size="small" column={3}>
        <Descriptions.Item label="模型">{glance.model.toUpperCase()}</Descriptions.Item>
        <Descriptions.Item label="样本量">{glance.nobs}</Descriptions.Item>
        <Descriptions.Item label="自由度">{glance.dof}</Descriptions.Item>
        {Object.entries(glance.metrics).map(([key, value]) => (
          <Descriptions.Item key={key} label={METRIC_LABELS[key] ?? key}>
            {formatMetric(key, value)}
          </Descriptions.Item>
        ))}
      </Descriptions>
    </Card>
  );
}
