import { Card, Statistic, Row, Col } from 'antd';
import { useModelStore } from '../stores/modelStore';

export function TreatmentEffectSummary() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult) return null;

  const g = lastResult.glance.model;
  const isCausal = ['did', 'ipw', 'psm', 'aipw', 'event_study'].includes(g);
  if (!isCausal) return null;

  const labels: Record<string, string> = {
    did: 'DID 双重差分', ipw: 'IPW 逆概率加权',
    psm: 'PSM 倾向得分匹配', aipw: 'AIPW 双重稳健',
  };

  return (
    <Card size="small" title={`处理效应汇总 — ${labels[g] || g}`} style={{ marginBottom: 16 }}>
      <Row gutter={16}>
        {lastResult.ate !== undefined && <Col span={6}><Statistic title="ATE" value={lastResult.ate?.toFixed(4)} /></Col>}
        {lastResult.att !== undefined && <Col span={6}><Statistic title="ATT" value={lastResult.att?.toFixed(4)} /></Col>}
        {lastResult.atu !== undefined && <Col span={6}><Statistic title="ATU" value={lastResult.atu?.toFixed(4)} /></Col>}
        {lastResult.treat_effect !== undefined && <Col span={6}><Statistic title="处理效应" value={lastResult.treat_effect?.toFixed(4)} /></Col>}
        {lastResult.treat_effect_se !== undefined && <Col span={6}><Statistic title="SE" value={lastResult.treat_effect_se?.toFixed(4)} /></Col>}
        {lastResult.n_matched !== undefined && <Col span={6}><Statistic title="匹配数" value={lastResult.n_matched} /></Col>}
      </Row>
    </Card>
  );
}
