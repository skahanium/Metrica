import { Card, Statistic, Row, Col, Alert } from 'antd';
import type { ModelResult } from '../types/protocol';

interface DIDResultCardsProps {
  result: ModelResult;
}

export function DIDResultCards({ result }: DIDResultCardsProps) {
  if (result.glance.model !== 'did') return null;

  const te = result.treat_effect;
  const p = result.treat_effect_pvalue;
  const stars = p !== undefined ? (p < 0.01 ? '***' : p < 0.05 ? '**' : p < 0.1 ? '*' : '') : '';

  return (
    <Card size="small" title="DID 处理效应" style={{ marginBottom: 16 }}>
      <Row gutter={16}>
        <Col span={6}><Statistic title="处理效应" value={te?.toFixed(4)} suffix={stars} /></Col>
        <Col span={6}><Statistic title="标准误" value={result.treat_effect_se?.toFixed(4)} /></Col>
        <Col span={6}><Statistic title="p 值" value={p?.toFixed(4)} /></Col>
        <Col span={6}><Statistic title="处理组 / 对照组" value={`${result.n_treated} / ${result.n_control}`} /></Col>
      </Row>
      <Alert type="info" style={{ marginTop: 12 }}
        message="平行趋势假设是 DID 有效的前提。若有个体层面的预处理数据，建议使用事件研究检验平行趋势。" />
    </Card>
  );
}
