import React from 'react';
import { Descriptions, Typography } from 'antd';
import type { GlanceResult, QuantileDiagnostics } from '../types/protocol';

const { Text } = Typography;

export interface QuantileSummaryPanelProps {
  glance: GlanceResult;
  diagnostics?: QuantileDiagnostics;
}

/**
 * 分位数回归结构化摘要：τ、伪 R²、推断口径与设计矩阵秩（只读消费 Runtime 载荷）。
 */
export const QuantileSummaryPanel: React.FC<QuantileSummaryPanelProps> = ({ glance, diagnostics }) => {
  const tau = diagnostics?.tau ?? glance.metrics?.tau;
  const pr2 = glance.metrics?.pseudo_r2;

  return (
    <div style={{ marginTop: 16 }}>
      <Text strong style={{ display: 'block', marginBottom: 8 }}>
        分位数回归摘要
      </Text>
      <Descriptions size="small" column={1} bordered>
        <Descriptions.Item label="分位点 τ">
          {tau === undefined || tau === null || Number.isNaN(tau) ? '—' : String(tau)}
        </Descriptions.Item>
        <Descriptions.Item label="伪 R²（McFadden）">
          {pr2 === undefined || pr2 === null || Number.isNaN(pr2) ? '—' : pr2.toFixed(4)}
        </Descriptions.Item>
        <Descriptions.Item label="推断口径">
          {diagnostics?.inference_kind ?? '—'}
        </Descriptions.Item>
        <Descriptions.Item label="rank(X)">
          {diagnostics?.rank_X === undefined || diagnostics?.rank_X === null ? '—' : String(diagnostics.rank_X)}
        </Descriptions.Item>
        <Descriptions.Item label="条件数 cond(X)">
          {diagnostics?.cond_X === undefined || diagnostics?.cond_X === null || Number.isNaN(diagnostics.cond_X)
            ? '—'
            : diagnostics.cond_X.toFixed(2)}
        </Descriptions.Item>
        <Descriptions.Item label="求解器">
          {diagnostics?.solver ?? '—'}
        </Descriptions.Item>
      </Descriptions>
    </div>
  );
};
