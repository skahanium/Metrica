import { Typography } from 'antd';
import { DataSourcePanel } from './DataSourcePanel';

const { Title, Text } = Typography;

export function Sidebar() {
  return (
    <div style={{ padding: 16, width: 280, background: '#fafafa', borderRight: '1px solid #f0f0f0', height: '100%' }}>
      <Title level={5}>数据源</Title>
      <DataSourcePanel />
      <div style={{ marginTop: 24 }}>
        <Title level={5}>变量</Title>
        <Text type="secondary">检查数据后将显示变量列表。</Text>
      </div>
    </div>
  );
}
