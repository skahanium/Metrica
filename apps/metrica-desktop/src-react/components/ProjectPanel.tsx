import { Button, Card, Empty, List, Space, Tag, Typography, message } from 'antd';
import { FolderOpenOutlined, PlusOutlined, CheckOutlined } from '@ant-design/icons';
import { useProjectStore } from '../stores/projectStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useModelStore, type ModelHistoryItem } from '../stores/modelStore';
import { useAppStore } from '../stores/appStore';
import { loadProject, listRuns } from '../services/runtimeClient';
import type { RunRecord } from '../types/protocol';

const { Text } = Typography;

export function ProjectPanel() {
  const { projectPath, manifest, runHistory, recentProjects, setProjectPath, setManifest, setRunHistory, rememberProject, setDirty } = useProjectStore();
  const { setSourceAndActivePath } = useDatasetStore();
  const { applyModelSpec, setLastResult, addToHistory, modelHistory, toggleModelSelection, selectedModelIds } = useModelStore();
  const { setLoading } = useAppStore();

  const handleOpenRecent = async (path: string) => {
    const workingDir = path.endsWith('/.metrica/project.json')
      ? path.slice(0, path.length - '/.metrica/project.json'.length)
      : path.slice(0, path.lastIndexOf('/.metrica/project.json'));
    setLoading(true);
    try {
      const result = await loadProject(workingDir || '.');
      const runs = await listRuns(workingDir || '.');
      setProjectPath(result.project_path);
      setManifest(result.manifest);
      setRunHistory(runs);
      setSourceAndActivePath(result.manifest.source_dataset, result.manifest.active_dataset);
      if (result.manifest.saved_model_specs[0]) {
        applyModelSpec(result.manifest.saved_model_specs[0]);
      }
      const latestFit = runs.find(
        (run): run is import('../types/protocol').FitModelRunRecord =>
          run.action === 'fit_model' && !!run.result_summary,
      );
      if (latestFit?.result_summary) {
        setLastResult(latestFit.result_summary);
      }
      rememberProject(result.project_path);
      setDirty(false);
      message.success('项目已打开');
    } catch (e) {
      message.error(e instanceof Error ? e.message : '打开项目失败');
    } finally {
      setLoading(false);
    }
  };

  const handleRestoreResult = (item: RunRecord) => {
    if (item.status !== 'success' || !item.result_summary) {
      message.warning('该运行记录没有成功的结果');
      return;
    }
    if (item.action !== 'fit_model') {
      message.warning('仅支持恢复拟合模型的运行结果');
      return;
    }

    setLastResult(item.result_summary);
    if (item.model_spec) {
      applyModelSpec(item.model_spec);
    }
    message.success('已恢复模型结果');
  };

  const handleAddToHistory = (item: RunRecord) => {
    if (item.status !== 'success' || !item.result_summary) {
      message.warning('该运行记录没有成功的结果');
      return;
    }
    if (item.action !== 'fit_model') {
      message.warning('仅支持将拟合模型添加到运行历史');
      return;
    }

    const historyItem: ModelHistoryItem = {
      id: item.run_id,
      label: `${item.model_spec?.model_type ?? 'model'} ${item.run_id.slice(0, 8)}`,
      runId: item.run_id,
      modelType: item.model_spec?.model_type ?? 'unknown',
      formula: item.model_spec?.formula ?? '',
      datasetPath: item.dataset_ref.path,
      result: item.result_summary,
      createdAt: item.finished_at,
    };

    addToHistory(historyItem);
    message.success('已添加到模型历史');
  };

  const isInHistory = (runId: string) => modelHistory.some((h) => h.id === runId);
  const isSelected = (runId: string) => selectedModelIds.includes(runId);

  return (
    <Space direction="vertical" style={{ width: '100%' }} size={16}>
      <Card size="small" title="当前项目">
        {!manifest ? (
          <Empty description="尚未加载项目" />
        ) : (
          <Space direction="vertical" style={{ width: '100%' }}>
            <Text>项目路径：{projectPath || '未保存'}</Text>
            <Text>项目 ID：{manifest.project_id}</Text>
            <Text>原始数据：{manifest.source_dataset || '—'}</Text>
            <Text>当前数据：{manifest.active_dataset || '—'}</Text>
            <Text>最后运行：{manifest.last_run_id || '—'}</Text>
            {manifest.data_lineage && (manifest.data_lineage.operations?.length ?? 0) > 0 && (
              <Space direction="vertical" style={{ width: '100%', marginTop: 8 }}>
                <Text strong>数据谱系：源 → {manifest.data_lineage.operations?.length ?? 0} 步变换 → 当前</Text>
                {manifest.data_lineage.row_count_before != null && manifest.data_lineage.row_count_after != null && (
                  <Text type="secondary">
                    行数变化：{manifest.data_lineage.row_count_before} → {manifest.data_lineage.row_count_after}
                  </Text>
                )}
                <List
                  size="small"
                  dataSource={manifest.data_lineage.operations ?? []}
                  renderItem={(op: Record<string, unknown>, i: number) => (
                    <List.Item>
                      <Tag>{i + 1}</Tag>
                      <Text code>{String(op.op)}</Text>
                      <Text type="secondary" style={{ fontSize: 12, marginLeft: 8 }}>
                        {JSON.stringify(op.args)}
                      </Text>
                    </List.Item>
                  )}
                />
              </Space>
            )}
          </Space>
        )}
      </Card>

      <Card size="small" title="运行历史">
        {!runHistory.length ? (
          <Empty description="暂无运行记录" />
        ) : (
          <List
            size="small"
            dataSource={runHistory}
            renderItem={(item) => (
              <List.Item
                actions={[
                  item.status === 'success' && item.result_summary && (
                    <Button
                      key="restore"
                      size="small"
                      onClick={() => handleRestoreResult(item)}
                    >
                      恢复
                    </Button>
                  ),
                  item.status === 'success' && item.result_summary && (
                    <Button
                      key="compare"
                      size="small"
                      icon={isInHistory(item.run_id) ? <CheckOutlined /> : <PlusOutlined />}
                      type={isSelected(item.run_id) ? 'primary' : 'default'}
                      onClick={() => {
                        if (!isInHistory(item.run_id)) {
                          handleAddToHistory(item);
                        } else {
                          toggleModelSelection(item.run_id);
                        }
                      }}
                    >
                      {isInHistory(item.run_id) ? (isSelected(item.run_id) ? '已选' : '选择对比') : '加入对比'}
                    </Button>
                  ),
                ].filter(Boolean)}
              >
                <List.Item.Meta
                  title={<><Tag color={item.status === 'success' ? 'green' : 'red'}>{item.status}</Tag>{item.action}</>}
                  description={`${item.dataset_ref.path} | ${item.finished_at}`}
                />
              </List.Item>
            )}
          />
        )}
      </Card>

      <Card size="small" title="最近项目">
        {!recentProjects.length ? (
          <Empty description="暂无最近项目" />
        ) : (
          <List
            size="small"
            dataSource={recentProjects}
            renderItem={(item) => (
              <List.Item actions={[
                <Button key="open" type="link" icon={<FolderOpenOutlined />} onClick={() => handleOpenRecent(item)}>打开</Button>,
                <Button key="copy" size="small" onClick={() => navigator.clipboard?.writeText(item)}>复制路径</Button>,
              ]}>
                <Text style={{ wordBreak: 'break-all' }}>{item}</Text>
              </List.Item>
            )}
          />
        )}
      </Card>
    </Space>
  );
}
