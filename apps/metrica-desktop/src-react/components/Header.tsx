import { Button, Space, Typography } from 'antd';
import { PlayCircleOutlined } from '@ant-design/icons';
import { useAppStore } from '../stores/appStore';

const { Title, Text } = Typography;

export function Header() {
  const isLoading = useAppStore((s) => s.isLoading);

  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 24px', height: 64, background: '#fff', borderBottom: '1px solid #f0f0f0' }}>
      <Space align="baseline">
        <Text type="secondary" style={{ fontSize: 12, letterSpacing: 2, textTransform: 'uppercase' }}>Metrica</Text>
        <Title level={4} style={{ margin: 0 }}>计量分析工作台</Title>
      </Space>
      <Button type="primary" icon={<PlayCircleOutlined />} loading={isLoading} htmlType="submit" form="model-form">
        运行模型
      </Button>
    </div>
  );
}
