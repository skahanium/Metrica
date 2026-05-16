import React from 'react';
import { Descriptions, Typography } from 'antd';
import type { NlsDiagnostics } from '../types/protocol';

const { Text } = Typography;

export interface NlsDiagnosticsPanelProps {
  diagnostics?: NlsDiagnostics;
}

/**
 * NLS 结构化诊断：收敛、迭代、目标值与初值（只读消费 Runtime 载荷）。
 */
export const NlsDiagnosticsPanel: React.FC<NlsDiagnosticsPanelProps> = ({ diagnostics }) => {
  if (!diagnostics) return null;
  return (
    <div style={{ marginTop: 16 }}>
      <Text strong style={{ display: 'block', marginBottom: 8 }}>
        非线性最小二乘诊断
      </Text>
      <Descriptions size="small" column={1} bordered>
        <Descriptions.Item label="族">
          {diagnostics.nls_family ?? '—'}
        </Descriptions.Item>
        <Descriptions.Item label="收敛">
          {diagnostics.converged === undefined ? '—' : diagnostics.converged ? '是' : '否'}
        </Descriptions.Item>
        <Descriptions.Item label="迭代次数">
          {diagnostics.iterations === undefined ? '—' : String(diagnostics.iterations)}
        </Descriptions.Item>
        <Descriptions.Item label="优化器">
          {diagnostics.optimizer ?? '—'}
        </Descriptions.Item>
        <Descriptions.Item label="目标值（RSS）">
          {diagnostics.objective_final === undefined || diagnostics.objective_final === null
            ? '—'
            : String(diagnostics.objective_final)}
        </Descriptions.Item>
        <Descriptions.Item label="初值 start_used">
          {Array.isArray(diagnostics.start_used) && diagnostics.start_used.length > 0
            ? diagnostics.start_used.join(', ')
            : '—'}
        </Descriptions.Item>
        <Descriptions.Item label="failure_code">
          {diagnostics.failure_code === undefined || diagnostics.failure_code === null
            ? '—'
            : String(diagnostics.failure_code)}
        </Descriptions.Item>
      </Descriptions>
    </div>
  );
};
