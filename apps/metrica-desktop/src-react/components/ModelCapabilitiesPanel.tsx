import React from 'react';
import { Collapse, Tag, Typography, Descriptions, Space } from 'antd';
import { CheckCircleOutlined, CloseCircleOutlined, WarningOutlined, ExperimentOutlined } from '@ant-design/icons';
import type { ModelCapabilities } from '../types/protocol';

const { Text, Title } = Typography;

interface ModelCapabilitiesPanelProps {
  capabilities: ModelCapabilities;
}

const statusColor: Record<string, string> = {
  implemented: 'green',
  partial: 'orange',
  planned: 'blue',
};

const statusIcon: Record<string, React.ReactNode> = {
  implemented: <CheckCircleOutlined />,
  partial: <WarningOutlined />,
  planned: <ExperimentOutlined />,
};

const statusLabel: Record<string, string> = {
  implemented: '已实现',
  partial: '部分实现',
  planned: '规划中',
};

export const ModelCapabilitiesPanel: React.FC<ModelCapabilitiesPanelProps> = ({ capabilities }) => {
  const st = capabilities.status || 'partial';

  return (
    <Collapse
      size="small"
      style={{ marginTop: 12, background: 'var(--m-surface)', border: '1px solid var(--m-border)' }}
      items={[
        {
          key: 'caps',
          label: (
            <Space size={8}>
              <Text strong style={{ fontSize: 13 }}>模型能力声明</Text>
              <Tag color={statusColor[st] || 'default'} icon={statusIcon[st]}>
                {statusLabel[st] || st}
              </Tag>
              <Text type="secondary" style={{ fontSize: 12 }}>{String(capabilities.model_family)} 族</Text>
            </Space>
          ),
          children: (
            <div style={{ padding: '4px 0' }}>
              <Descriptions size="small" column={2} labelStyle={{ fontSize: 12, color: 'var(--m-text-secondary)' }} contentStyle={{ fontSize: 12 }}>
                <Descriptions.Item label="已实现模型">
                  {capabilities.supported_models.map((m: string) => (
                    <Tag key={m} color="green" style={{ marginBottom: 4 }}>{m}</Tag>
                  ))}
                </Descriptions.Item>
                <Descriptions.Item label="估计方法">
                  {capabilities.estimators.map((e: string) => (
                    <Tag key={e} style={{ marginBottom: 4 }}>{e}</Tag>
                  ))}
                </Descriptions.Item>
                <Descriptions.Item label="可用诊断">
                  {capabilities.diagnostics_available.length > 0
                    ? capabilities.diagnostics_available.map((d: string) => (
                        <Tag key={d} color="green" style={{ marginBottom: 4 }}>{d}</Tag>
                      ))
                    : <Text type="secondary">—</Text>}
                </Descriptions.Item>
                <Descriptions.Item label="不可用诊断">
                  {capabilities.diagnostics_unavailable.length > 0
                    ? capabilities.diagnostics_unavailable.map((d: string) => (
                        <Tag key={d} color="red" icon={<CloseCircleOutlined />} style={{ marginBottom: 4 }}>{d}</Tag>
                      ))
                    : <Text type="secondary">—</Text>}
                </Descriptions.Item>
                <Descriptions.Item label="效应分解">
                  {capabilities.effects_available.length > 0
                    ? capabilities.effects_available.map((e: string) => (
                        <Tag key={e} color="blue" style={{ marginBottom: 4 }}>{e}</Tag>
                      ))
                    : <Text type="secondary">暂不可用</Text>}
                </Descriptions.Item>
                <Descriptions.Item label="预测">
                  <Tag color={capabilities.prediction_available ? 'green' : 'default'}>
                    {capabilities.prediction_available ? '可用' : '不可用'}
                  </Tag>
                </Descriptions.Item>
              </Descriptions>
              {capabilities.limitations.length > 0 && (
                <div style={{ marginTop: 8 }}>
                  <Text type="secondary" style={{ fontSize: 12 }}>已知限制：</Text>
                  <ul style={{ margin: '4px 0 0 16px', padding: 0 }}>
                    {capabilities.limitations.map((lim: string, i: number) => (
                      <li key={i}><Text style={{ fontSize: 12 }}>{lim}</Text></li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          ),
        },
      ]}
    />
  );
};
