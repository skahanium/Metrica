import { useState } from 'react';
import { Input, Button, Space, Typography } from 'antd';
import { SearchOutlined } from '@ant-design/icons';
import { useDatasetStore } from '../stores/datasetStore';
import { useModelStore } from '../stores/modelStore';
import { useProjectStore } from '../stores/projectStore';
import { useTransformStore } from '../stores/transformStore';
import { useAppStore } from '../stores/appStore';
import { inspectDataset, inferWorkingDir } from '../services/runtimeClient';

const { Text } = Typography;

export function DataSourcePanel() {
  const { sourcePath, activePath, setFilePath, setSummary } = useDatasetStore();
  const isDerived = sourcePath !== activePath;
  const setLastResult = useModelStore((s) => s.setLastResult);
  const { appendRunRecord, setDirty } = useProjectStore();
  const { clearHistory, clearOperations } = useTransformStore();
  const setError = useAppStore((s) => s.setError);
  const [loading, setLoading] = useState(false);

  const handleInspect = async () => {
    if (!sourcePath) return;
    setLoading(true);
    try {
      const workingDir = inferWorkingDir(sourcePath);
      const summary = await inspectDataset(sourcePath, workingDir);
      setSummary(summary);
      appendRunRecord({
        run_id: `inspect-${Date.now()}`,
        action: 'inspect_dataset',
        started_at: new Date().toISOString(),
        finished_at: new Date().toISOString(),
        status: 'success',
        dataset_ref: { source: 'file', path: sourcePath, format: 'csv' },
        warnings: [],
        messages: [],
        artifacts: [],
        result_summary: summary as never,
      });
      setDirty(true);
    } catch (e) {
      const msg = e instanceof Error ? e.message : '数据加载失败';
      setError(msg);
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
          setDirty(true);
        }}
        onPressEnter={handleInspect}
        style={{ width: '100%' }}
      />
      <Button icon={<SearchOutlined />} size="small" loading={loading} onClick={handleInspect} block>
        检查数据
      </Button>
      {sourcePath && <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>原始数据：{sourcePath}</Text>}
      {isDerived && <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>建模数据：{activePath}</Text>}
    </Space>
  );
}
