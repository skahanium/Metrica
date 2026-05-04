import { Card, Statistic, Row, Col, Typography } from 'antd';
import { useMemo } from 'react';
import { useModelStore } from '../stores/modelStore';

export function ClassificationPreview() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult) return null;

  const g = lastResult.glance;
  const isBinary = ['logit', 'probit'].includes(g.model);
  if (!isBinary) return null;

  const aug = lastResult.augment_preview as any;
  if (!aug?.fitted) {
    return (
      <Card size="small" title="分类预览" style={{ marginBottom: 16 }}>
        <Typography.Text type="secondary">augment 数据不可用。</Typography.Text>
      </Card>
    );
  }

  const fitted: number[] = Array.isArray(aug.fitted) ? aug.fitted : Object.values(aug.fitted);
  const n = fitted.length;
  const avgProb = fitted.reduce((a: number, b: number) => a + b, 0) / n;
  const minProb = Math.min(...fitted);
  const maxProb = Math.max(...fitted);

  return (
    <Card size="small" title="分类预览" style={{ marginBottom: 16 }}>
      <Row gutter={16}>
        <Col span={8}><Statistic title="预测概率均值" value={avgProb.toFixed(3)} /></Col>
        <Col span={8}><Statistic title="最小概率" value={minProb.toFixed(3)} /></Col>
        <Col span={8}><Statistic title="最大概率" value={maxProb.toFixed(3)} /></Col>
      </Row>
    </Card>
  );
}
