import React from 'react';
import { Card, Typography, Tag, Space } from 'antd';
import type { ColumnSummary } from '../types/protocol';

const { Text } = Typography;

interface VariableCardProps {
  column: ColumnSummary;
  onClick: (name: string) => void;
}

export const VariableCard: React.FC<VariableCardProps> = ({ column, onClick }) => {
  const isContinuous = column.inferred_type === 'continuous' || column.type === 'Float64';

  return (
    <Card
      size="small"
      hoverable
      onClick={() => onClick(column.name)}
      style={{ marginBottom: 6, borderRadius: 6, cursor: 'pointer' }}
      styles={{ body: { padding: '8px 12px' } }}
    >
      <Space direction="vertical" size={2} style={{ width: '100%' }}>
        <Text strong style={{ fontSize: 13 }}>{column.name}</Text>
        <Space size={4}>
          <Tag color={isContinuous ? 'blue' : 'green'} style={{ fontSize: 10, lineHeight: '16px' }}>
            {column.inferred_type || column.type || '?'}
          </Tag>
          {(column.missing_count ?? column.missing) ? (
            <Tag color="gold" style={{ fontSize: 10, lineHeight: '16px' }}>
              缺失 {column.missing_count ?? column.missing}
            </Tag>
          ) : null}
        </Space>
      </Space>
    </Card>
  );
};
