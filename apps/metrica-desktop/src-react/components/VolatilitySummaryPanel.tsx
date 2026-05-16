import React from 'react';
import { Descriptions, Typography } from 'antd';
import type { VolatilityDiagnostics } from '../types/protocol';

const { Text } = Typography;

export interface VolatilitySummaryPanelProps {
  diagnostics?: VolatilityDiagnostics;
}

/**
 * ARCH / GARCH 结构化诊断：只读消费 `result_payload.diagnostics`，不在 UI 内重算波动率。
 */
export const VolatilitySummaryPanel: React.FC<VolatilitySummaryPanelProps> = ({ diagnostics }) => {
  if (!diagnostics) return null;
  const prev = diagnostics.conditional_volatility_preview;
  const prevStr =
    Array.isArray(prev) && prev.length > 0 ? prev.map((x) => x.toFixed(4)).join(', ') : '—';
  return (
    <div style={{ marginTop: 16 }}>
      <Text strong style={{ display: 'block', marginBottom: 8 }}>
        波动率模型诊断
      </Text>
      <Descriptions size="small" column={1} bordered>
        <Descriptions.Item label="收敛">
          {diagnostics.converged === undefined ? '—' : diagnostics.converged ? '是' : '否'}
        </Descriptions.Item>
        <Descriptions.Item label="迭代次数">
          {diagnostics.iterations === undefined ? '—' : String(diagnostics.iterations)}
        </Descriptions.Item>
        <Descriptions.Item label="优化器">{diagnostics.optimizer ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="对数似然">
          {diagnostics.loglik === undefined || diagnostics.loglik === null
            ? '—'
            : String(diagnostics.loglik)}
        </Descriptions.Item>
        <Descriptions.Item label="持久度 (α+β)">
          {diagnostics.persistence === undefined || diagnostics.persistence === null
            ? '—'
            : String(diagnostics.persistence)}
        </Descriptions.Item>
        <Descriptions.Item label="无条件方差">
          {diagnostics.unconditional_variance === undefined || diagnostics.unconditional_variance === null
            ? '—'
            : String(diagnostics.unconditional_variance)}
        </Descriptions.Item>
        <Descriptions.Item label="条件波动序列长度">
          {diagnostics.volatility_length === undefined ? '—' : String(diagnostics.volatility_length)}
        </Descriptions.Item>
        <Descriptions.Item label="ARCH 阶 q">
          {diagnostics.arch_order === undefined ? '—' : String(diagnostics.arch_order)}
        </Descriptions.Item>
        <Descriptions.Item label="GARCH p / q">
          {diagnostics.garch_p === undefined && diagnostics.garch_q === undefined
            ? '—'
            : `${diagnostics.garch_p ?? '—'} / ${diagnostics.garch_q ?? '—'}`}
        </Descriptions.Item>
        <Descriptions.Item label="条件波动预览（前若干点）">{prevStr}</Descriptions.Item>
        <Descriptions.Item label="failure_code">
          {diagnostics.failure_code === undefined || diagnostics.failure_code === null
            ? '—'
            : String(diagnostics.failure_code)}
        </Descriptions.Item>
      </Descriptions>
    </div>
  );
};
