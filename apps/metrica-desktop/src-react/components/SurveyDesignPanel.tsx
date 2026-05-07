import { Card, Descriptions, Typography } from 'antd';
import type { ModelResult } from '../types/protocol';

interface SurveyDesignPanelProps {
  result: ModelResult;
}

export function SurveyDesignPanel({ result }: SurveyDesignPanelProps) {
  if (!result.design_effects) return null;

  const glance = result.glance;
  const deffEntries = result.design_effects;
  const strataEntries = result.strata_summary;

  const meanDeff = deffEntries.length > 0
    ? deffEntries.reduce((sum: number, d: { deff: number }) => sum + d.deff, 0) / deffEntries.length
    : 1.0;
  const totalEffectiveN = deffEntries.length > 0
    ? deffEntries.reduce((sum: number, d: { n_eff: number }) => sum + d.n_eff, 0) / deffEntries.length
    : glance?.nobs ?? 0;

  const nStrata = strataEntries ? strataEntries.length : 0;
  const hasFpc = strataEntries
    ? strataEntries.some((s: { max_weight: number }) => s.max_weight > 0)
    : false;

  return (
    <Card size="small" title="抽样设计概览" style={{ marginBottom: 16 }}>
      <Descriptions size="small" column={3}>
        <Descriptions.Item label="总样本量">{glance?.nobs ?? '-'}</Descriptions.Item>
        <Descriptions.Item label="层数">{nStrata > 0 ? nStrata : '未分层'}</Descriptions.Item>
        <Descriptions.Item label="FPC">{hasFpc ? '已应用' : '未应用'}</Descriptions.Item>
        <Descriptions.Item label="平均 DEFF">{meanDeff.toFixed(3)}</Descriptions.Item>
        <Descriptions.Item label="有效样本量">{Math.round(totalEffectiveN)}</Descriptions.Item>
        <Descriptions.Item label="方差方法">
          <Typography.Text code>Taylor linearization</Typography.Text>
        </Descriptions.Item>
      </Descriptions>
    </Card>
  );
}
