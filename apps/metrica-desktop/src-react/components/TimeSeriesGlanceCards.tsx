import React from 'react';
import { Card, Statistic, Row, Col } from 'antd';

interface TimeSeriesGlanceCardsProps {
  modelType: string;
  nobs: number;
  aic?: number;
  bic?: number;
  loglik?: number;
  sigma2?: number;
  nCointegrating?: number;
  adfPvalue?: number;
  ppPvalue?: number;
  kpssPvalue?: number;
}

export const TimeSeriesGlanceCards: React.FC<TimeSeriesGlanceCardsProps> = ({
  modelType,
  nobs,
  aic,
  bic,
  loglik,
  sigma2,
  nCointegrating,
  adfPvalue,
  ppPvalue,
  kpssPvalue
}) => {
  return (
    <Card title={`${modelType} 模型摘要`} size="small">
      <Row gutter={[16, 16]}>
        <Col span={6}>
          <Statistic title="样本量" value={nobs} />
        </Col>

        {aic !== undefined && (
          <Col span={6}>
            <Statistic title="AIC" value={aic.toFixed(2)} />
          </Col>
        )}

        {bic !== undefined && (
          <Col span={6}>
            <Statistic title="BIC" value={bic.toFixed(2)} />
          </Col>
        )}

        {loglik !== undefined && (
          <Col span={6}>
            <Statistic title="对数似然" value={loglik.toFixed(2)} />
          </Col>
        )}

        {sigma2 !== undefined && (
          <Col span={6}>
            <Statistic title="σ²" value={sigma2.toFixed(4)} />
          </Col>
        )}

        {nCointegrating !== undefined && (
          <Col span={6}>
            <Statistic
              title="协整关系数"
              value={nCointegrating}
              valueStyle={{ color: nCointegrating > 0 ? '#3f8600' : '#cf1322' }}
            />
          </Col>
        )}

        {adfPvalue !== undefined && (
          <Col span={6}>
            <Statistic
              title="ADF p值"
              value={adfPvalue.toFixed(4)}
              valueStyle={{ color: adfPvalue < 0.05 ? '#3f8600' : '#cf1322' }}
            />
          </Col>
        )}

        {ppPvalue !== undefined && (
          <Col span={6}>
            <Statistic
              title="PP p值"
              value={ppPvalue.toFixed(4)}
              valueStyle={{ color: ppPvalue < 0.05 ? '#3f8600' : '#cf1322' }}
            />
          </Col>
        )}

        {kpssPvalue !== undefined && (
          <Col span={6}>
            <Statistic
              title="KPSS p值"
              value={kpssPvalue.toFixed(4)}
              valueStyle={{ color: kpssPvalue > 0.05 ? '#3f8600' : '#cf1322' }}
            />
          </Col>
        )}
      </Row>
    </Card>
  );
};

export default TimeSeriesGlanceCards;
