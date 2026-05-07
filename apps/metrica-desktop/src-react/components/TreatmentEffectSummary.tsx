import { Card, Statistic, Row, Col } from 'antd';
import type { ModelResult } from '../types/protocol';

interface TreatmentEffectSummaryProps {
  result: ModelResult;
}

export function TreatmentEffectSummary({ result }: TreatmentEffectSummaryProps) {
  const g = result.glance.model;
  const isCausal = ['did', 'ipw', 'psm', 'aipw', 'event_study'].includes(g);
  if (!isCausal) return null;

  const labels: Record<string, string> = {
    did: 'DID 双重差分', ipw: 'IPW 逆概率加权',
    psm: 'PSM 倾向得分匹配', aipw: 'AIPW 双重稳健',
  };

  return (
    <Card size="small" title={`处理效应汇总 — ${labels[g] || g}`} style={{ marginBottom: 16 }}>
      <Row gutter={16}>
        {result.ate !== undefined && <Col span={6}><Statistic title="ATE" value={result.ate?.toFixed(4)} /></Col>}
        {result.att !== undefined && <Col span={6}><Statistic title="ATT" value={result.att?.toFixed(4)} /></Col>}
        {result.atu !== undefined && <Col span={6}><Statistic title="ATU" value={result.atu?.toFixed(4)} /></Col>}
        {result.treat_effect !== undefined && <Col span={6}><Statistic title="处理效应" value={result.treat_effect?.toFixed(4)} /></Col>}
        {result.treat_effect_se !== undefined && <Col span={6}><Statistic title="SE" value={result.treat_effect_se?.toFixed(4)} /></Col>}
        {result.n_matched !== undefined && <Col span={6}><Statistic title="匹配数" value={result.n_matched} /></Col>}
      </Row>
    </Card>
  );
}
