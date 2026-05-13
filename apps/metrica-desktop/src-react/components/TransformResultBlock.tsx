import React from 'react';
import { Alert, Button, Space, Table, Tag, Typography } from 'antd';
import { CopyOutlined } from '@ant-design/icons';
import type { TransformResult } from '../types/protocol';

const { Text } = Typography;

interface TransformResultBlockProps {
  command: string;
  source: 'cli' | 'ui';
  result: TransformResult;
}

export const TransformResultBlock: React.FC<TransformResultBlockProps> = ({ command, source, result }) => {
  const rows = result.preview?.rows ?? [];
  const columns = result.preview?.columns ?? (rows[0] ? Object.keys(rows[0]) : []);
  const statusColor = result.status === 'error' ? 'red' : 'blue';

  const handleCopy = () => {
    navigator.clipboard?.writeText(command).catch(() => {});
  };

  return (
    <div style={{ marginBottom: 16, background: 'var(--m-surface)', borderRadius: 12, border: '1px solid var(--m-border)', padding: 16, boxShadow: 'var(--m-shadow-sm)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <Space>
          <Tag color={statusColor}>transform</Tag>
          <Tag color={source === 'cli' ? 'geekblue' : 'cyan'}>{source === 'cli' ? 'CLI' : '鼠标'}</Tag>
          <Text code style={{ fontSize: 13 }}>&gt; {command}</Text>
        </Space>
        <Space>
        <Button size="small" icon={<CopyOutlined />} onClick={handleCopy} />
        </Space>
      </div>

      {result.status === 'error' ? (
        <Alert
          type="error"
          showIcon
          message="数据操作失败"
          description={result.error?.message ?? 'Runtime 未返回详细错误'}
        />
      ) : (
        <Space direction="vertical" style={{ width: '100%' }} size={12}>
          <Space wrap>
            <Tag color="green">{result.result?.nrows ?? 0} 行</Tag>
            <Tag color="green">{result.result?.ncols ?? 0} 列</Tag>
            {result.result?.dataset_path && <Text type="secondary" style={{ fontSize: 12 }}>当前数据：{result.result.dataset_path}</Text>}
          </Space>
          {result.result?.notes && <Text>{result.result.notes}</Text>}
          {result.warnings?.map((warning, index) => (
            <Alert
              key={index}
              type="warning"
              showIcon
              message={String(warning.title ?? '数据操作警告')}
              description={String(warning.detail ?? '')}
            />
          ))}
          {!!rows.length && !!columns.length && (
            <Table
              size="small"
              pagination={false}
              rowKey={(_, index) => String(index)}
              dataSource={rows}
              columns={columns.map((column) => ({
                title: column,
                dataIndex: column,
                key: column,
                ellipsis: true,
              }))}
              scroll={{ x: true }}
            />
          )}
        </Space>
      )}
    </div>
  );
};
