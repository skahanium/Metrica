import { List, Tag, Typography } from 'antd';
import { DataSourcePanel } from './DataSourcePanel';
import { useDatasetStore } from '../stores/datasetStore';

const { Title, Text } = Typography;

export function Sidebar() {
  const summary = useDatasetStore((s) => s.summary);

  return (
    <div style={{ padding: 16, width: 280, background: '#fafafa', borderRight: '1px solid #f0f0f0', height: '100%' }}>
      <Title level={5}>数据源</Title>
      <DataSourcePanel />
      <div style={{ marginTop: 24 }}>
        <Title level={5}>变量</Title>
        {!summary?.columns?.length ? (
          <Text type="secondary">检查数据后将显示变量列表。</Text>
        ) : (
          <List
            size="small"
            dataSource={summary.columns}
            renderItem={(column) => (
              <List.Item style={{ paddingLeft: 0, paddingRight: 0 }}>
                <div style={{ minWidth: 0 }}>
                  <Text strong style={{ display: 'block', wordBreak: 'break-all' }}>{column.name}</Text>
                  <Text type="secondary" style={{ fontSize: 12 }}>{column.type ?? column.inferred_type ?? '未知类型'}</Text>
                </div>
                {(column.missing ?? column.missing_count ?? 0) > 0 && <Tag color="gold">缺失 {column.missing ?? column.missing_count}</Tag>}
              </List.Item>
            )}
          />
        )}
      </div>
    </div>
  );
}
