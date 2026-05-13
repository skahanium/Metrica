import { Card, Statistic, Row, Col } from 'antd';
import type { ModelResult } from '../types/protocol';

interface DiscreteGlanceCardsProps {
  result: ModelResult;
}

export function DiscreteGlanceCards({ result }: DiscreteGlanceCardsProps) {
  const g = result.glance;
  const m = g.metrics;

  const isDiscrete = ['logit', 'probit', 'poisson', 'ordered_logit', 'multinomial_logit', 'negbin'].includes(g.model);

  if (!isDiscrete) return null;

  return (
    <Card size="small" title="模型摘要" style={{ marginBottom: 16 }}>
      <Row gutter={16}>
        <Col span={6}><Statistic title="样本量" value={g.nobs} /></Col>
        <Col span={6}><Statistic title="自由度" value={g.dof} /></Col>
        {m.pseudo_r2 !== undefined && <Col span={6}><Statistic title="Pseudo R²" value={m.pseudo_r2.toFixed(4)} /></Col>}
        {m.loglik !== undefined && <Col span={6}><Statistic title="Log-Likelihood" value={m.loglik.toFixed(2)} /></Col>}
        {m.aic !== undefined && <Col span={6}><Statistic title="AIC" value={m.aic.toFixed(2)} /></Col>}
        {m.bic !== undefined && <Col span={6}><Statistic title="BIC" value={m.bic.toFixed(2)} /></Col>}
        {m.lr_chi2 !== undefined && <Col span={6}><Statistic title="LR χ²" value={m.lr_chi2.toFixed(4)} /></Col>}
        {m.lr_pvalue !== undefined && <Col span={6}><Statistic title="LR p 值" value={m.lr_pvalue.toFixed(4)} /></Col>}
      </Row>
    </Card>
  );
}
