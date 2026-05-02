import { useState } from 'react';
import { Input, Button, Space, Typography } from 'antd';
import { FolderOpenOutlined, SearchOutlined } from '@ant-design/icons';
import { useDatasetStore } from '../stores/datasetStore';
import { useModelStore } from '../stores/modelStore';
import { useTransformStore } from '../stores/transformStore';
import { inspectDataset } from '../services/runtimeClient';

const { Text } = Typography;

export function DataSourcePanel() {
  const { sourcePath, activePath, isDerived, setFilePath, setSummary } = useDatasetStore();
  const setLastResult = useModelStore((s) => s.setLastResult);
  const { clearHistory, clearOperations } = useTransformStore();
  const [loading, setLoading] = useState(false);

  const handleInspect = async () => {
    if (!sourcePath) return;
    setLoading(true);
    try {
      const summary = await inspectDataset(sourcePath);
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
        value={sourcePath}
        onChange={(e) => {
          setFilePath(e.target.value);
          setSummary(null);
          setLastResult(null);
          clearHistory();
          clearOperations();
        }}
      />
      <Space>
        <Button icon={<FolderOpenOutlined />} size="small">选择文件</Button>
        <Button icon={<SearchOutlined />} size="small" loading={loading} onClick={handleInspect}>
          检查数据
        </Button>
      </Space>
      {sourcePath && <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>原始数据：{sourcePath}</Text>}
      {isDerived && <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>建模数据：{activePath}</Text>}
    </Space>
  );
}
