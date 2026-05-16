import React from 'react';
import { Table, Card, Typography, Descriptions, Tag } from 'antd';
import type { GWRDiagnostics, GWRLocalCoefficientRow } from '../types/protocol';

const { Text } = Typography;

interface GWRDiagnosticsPanelProps {
  diagnostics: GWRDiagnostics;
}

export const GWRDiagnosticsPanel: React.FC<GWRDiagnosticsPanelProps> = ({ diagnostics }) => {
  const previewRows = diagnostics.local_coefficients_preview ?? [];
  if (previewRows.length === 0) return null;

  const coefCols = Object.keys(previewRows[0])
    .filter((k) => k !== 'obs')
    .map((k) => ({
      title: k,
      dataIndex: k,
      key: k,
      render: (v: number) => (v !== undefined ? v.toFixed(4) : '—'),
    }));

  const columns = [
    { title: 'Obs', dataIndex: 'obs', key: 'obs', width: 60 },
    ...coefCols,
  ];

  return (
    <Card size="small" title="GWR 局部系数摘要" style={{ marginTop: 12 }}>
      <Descriptions size="small" column={3} style={{ marginBottom: 12 }}>
        <Descriptions.Item label="带宽">{diagnostics.bandwidth?.toFixed(4) ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="核函数">
          <Tag color="blue">{diagnostics.kernel ?? 'gaussian'}</Tag>
        </Descriptions.Item>
        <Descriptions.Item label="带宽选择">
          <Tag>{diagnostics.bandwidth_selection ?? '—'}</Tag>
        </Descriptions.Item>
        {diagnostics.adaptive !== undefined && (
          <Descriptions.Item label="自适应">{diagnostics.adaptive ? '是' : '否'}</Descriptions.Item>
        )}
        <Descriptions.Item label="有效参数">{diagnostics.effective_parameters?.toFixed(2) ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="AICc">{diagnostics.aicc?.toFixed(2) ?? '—'}</Descriptions.Item>
        {diagnostics.time_scale !== undefined && (
          <>
            <Descriptions.Item label="时间尺度">{diagnostics.time_scale.toFixed(4)}</Descriptions.Item>
            <Descriptions.Item label="时间列">{diagnostics.time_column ?? '—'}</Descriptions.Item>
          </>
        )}
      </Descriptions>

      <Text type="secondary" style={{ fontSize: 12, marginBottom: 8, display: 'block' }}>
        局部系数预览（前 {previewRows.length} 行）
      </Text>
      <Table
        size="small"
        rowKey="obs"
        dataSource={previewRows as GWRLocalCoefficientRow[]}
        columns={columns}
        pagination={false}
        scroll={{ x: 'max-content' }}
      />
    </Card>
  );
};
