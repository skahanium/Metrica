import React from 'react';
import { Descriptions, Typography } from 'antd';
import type { GmmDiagnostics } from '../types/protocol';

const { Text } = Typography;

export interface GmmDiagnosticsPanelProps {
  diagnostics: GmmDiagnostics;
}

/**
 * 线性 GMM 结构化诊断（Hansen / Sargan J、矩条件与权重说明），只读展示 Runtime 载荷。
 */
export const GmmDiagnosticsPanel: React.FC<GmmDiagnosticsPanelProps> = ({ diagnostics }) => {
  const fmt = (v: number | null | undefined) =>
    v === null || v === undefined || Number.isNaN(v) ? '—' : String(v);

  return (
    <div style={{ marginTop: 16 }}>
      <Text strong style={{ display: 'block', marginBottom: 8 }}>
        GMM 诊断（过识别检验）
      </Text>
      <Descriptions size="small" column={1} bordered>
        <Descriptions.Item label="Hansen J">
          {fmt(diagnostics.j_statistic)}
        </Descriptions.Item>
        <Descriptions.Item label="自由度 (L−k)">
          {fmt(diagnostics.j_df as number | undefined)}
        </Descriptions.Item>
        <Descriptions.Item label="J 检验 p 值">
          {diagnostics.j_pvalue === null || diagnostics.j_pvalue === undefined
            ? '—'
            : fmt(diagnostics.j_pvalue)}
        </Descriptions.Item>
        <Descriptions.Item label="矩条件数 L">
          {fmt(diagnostics.n_moments)}
        </Descriptions.Item>
        <Descriptions.Item label="参数个数 k">
          {fmt(diagnostics.n_params)}
        </Descriptions.Item>
        <Descriptions.Item label="权重步长">
          {diagnostics.gmm_weight ?? '—'}
        </Descriptions.Item>
        <Descriptions.Item label="权重矩阵">
          <Text type="secondary" style={{ whiteSpace: 'pre-wrap' }}>
            {diagnostics.weight_matrix_description ?? '—'}
          </Text>
        </Descriptions.Item>
        {diagnostics.exactly_identified !== undefined && (
          <Descriptions.Item label="恰识别">
            {diagnostics.exactly_identified ? '是（J 检验不适用）' : '否'}
          </Descriptions.Item>
        )}
        {diagnostics.iterations !== undefined && (
          <Descriptions.Item label="迭代次数">
            {String(diagnostics.iterations)}
          </Descriptions.Item>
        )}
      </Descriptions>
    </div>
  );
};
