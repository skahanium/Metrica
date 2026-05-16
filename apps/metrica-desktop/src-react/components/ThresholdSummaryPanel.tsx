import React from 'react';
import { Descriptions, Typography } from 'antd';
import type { ThresholdDiagnostics } from '../types/protocol';

const { Text } = Typography;

export interface ThresholdSummaryPanelProps {
  diagnostics?: ThresholdDiagnostics;
}

/**
 * 门限回归结构化摘要：γ̂ 与区制样本量（只读消费 Runtime 载荷）。
 */
export const ThresholdSummaryPanel: React.FC<ThresholdSummaryPanelProps> = ({ diagnostics }) => {
  if (!diagnostics) return null;
  const meta = diagnostics.search_grid_meta;
  return (
    <div style={{ marginTop: 16 }}>
      <Text strong style={{ display: 'block', marginBottom: 8 }}>
        门限回归摘要
      </Text>
      <Descriptions size="small" column={1} bordered>
        <Descriptions.Item label="门限 γ̂">
          {diagnostics.gamma_hat === undefined || diagnostics.gamma_hat === null
            ? '—'
            : String(diagnostics.gamma_hat)}
        </Descriptions.Item>
        <Descriptions.Item label="区制样本量（下 / 上）">
          {diagnostics.n_below === undefined || diagnostics.n_above === undefined
            ? '—'
            : `${diagnostics.n_below} / ${diagnostics.n_above}`}
        </Descriptions.Item>
        <Descriptions.Item label="分段 RSS">
          {diagnostics.rss_piecewise === undefined || diagnostics.rss_piecewise === null
            ? '—'
            : String(diagnostics.rss_piecewise)}
        </Descriptions.Item>
        <Descriptions.Item label="网格元数据">
          {meta
            ? `候选数 ${meta.n_candidates ?? '—'}；trim ${meta.trim_frac_applied ?? '—'}；输入长度 ${meta.grid_input_length ?? '—'}`
            : '—'}
        </Descriptions.Item>
      </Descriptions>
    </div>
  );
};
