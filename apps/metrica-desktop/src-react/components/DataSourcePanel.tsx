import { useState } from 'react';
import { Button, Space, Typography } from 'antd';
import { FolderOpenOutlined } from '@ant-design/icons';
import { useDatasetStore } from '../stores/datasetStore';
import { useModelStore } from '../stores/modelStore';
import { useProjectStore } from '../stores/projectStore';
import { useTransformStore } from '../stores/transformStore';
import { useAppStore } from '../stores/appStore';
import { inspectDataset, inferWorkingDir } from '../services/runtimeClient';
import { pickCsvFile } from '../services/nativeHost';

const { Text } = Typography;

export function DataSourcePanel() {
  const { sourcePath, activePath, setSourceAndActivePath, setSummary } = useDatasetStore();
  const isDerived = sourcePath !== activePath;
  const setLastResult = useModelStore((s) => s.setLastResult);
  const { appendRunRecord, setDirty } = useProjectStore();
  const { clearHistory, clearOperations } = useTransformStore();
  const setError = useAppStore((s) => s.setError);
  const [loading, setLoading] = useState(false);

  const inspectPath = async (datasetPath: string) => {
    setLoading(true);
    try {
      const workingDir = inferWorkingDir(datasetPath);
      const summary = await inspectDataset(datasetPath, workingDir);
      setSummary(summary);
      appendRunRecord({
        run_id: `inspect-${Date.now()}`,
        action: 'inspect_dataset',
        started_at: new Date().toISOString(),
        finished_at: new Date().toISOString(),
        status: 'success',
        dataset_ref: { source: 'file', path: datasetPath, format: 'csv' },
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

  const handleChooseCsv = async () => {
    setError(null);
    setLoading(true);
    try {
      const result = await pickCsvFile();
      if (result.cancelled || !result.path) {
        return;
      }
      setSourceAndActivePath(result.path, result.path);
      setSummary(null);
      setLastResult(null);
      clearHistory();
      clearOperations();
      setDirty(true);
      await inspectPath(result.path);
    } catch (e) {
      const msg = e instanceof Error ? e.message : '选择 CSV 文件失败';
      setError(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Space direction="vertical" style={{ width: '100%' }}>
      <Button icon={<FolderOpenOutlined />} size="small" loading={loading} onClick={handleChooseCsv} block>
        选择 CSV 文件
      </Button>
      {sourcePath && <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>原始数据：{sourcePath}</Text>}
      {isDerived && <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>建模数据：{activePath}</Text>}
    </Space>
  );
}
