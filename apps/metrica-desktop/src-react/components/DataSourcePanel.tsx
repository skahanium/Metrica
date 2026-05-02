import { useState } from 'react';
import { Input, Button, Space, Typography } from 'antd';
import { FolderOpenOutlined, SearchOutlined } from '@ant-design/icons';
import { useDatasetStore } from '../stores/datasetStore';
import { inspectDataset } from '../services/runtimeClient';

const { Text } = Typography;

export function DataSourcePanel() {
  const { filePath, setFilePath, setSummary } = useDatasetStore();
  const [loading, setLoading] = useState(false);

  const handleInspect = async () => {
    if (!filePath) return;
    setLoading(true);
    try {
      const summary = await inspectDataset(filePath);
      setSummary(summary);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Space direction="vertical" style={{ width: '100%' }}>
      <Input
        placeholder="CSV 文件路径"
        value={filePath}
        onChange={(e) => setFilePath(e.target.value)}
      />
      <Space>
        <Button icon={<FolderOpenOutlined />} size="small">选择文件</Button>
        <Button icon={<SearchOutlined />} size="small" loading={loading} onClick={handleInspect}>
          检查数据
        </Button>
      </Space>
      {filePath && <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>{filePath}</Text>}
    </Space>
  );
}
