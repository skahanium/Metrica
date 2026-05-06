import { Button, Space, Typography } from 'antd';
import { FolderOpenOutlined, RedoOutlined, SaveOutlined } from '@ant-design/icons';
import { useAppStore } from '../stores/appStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useModelStore } from '../stores/modelStore';
import { useProjectStore } from '../stores/projectStore';
import { listRuns, loadProject, rerunTask, saveProject, inferWorkingDir } from '../services/runtimeClient';

const { Title } = Typography;

interface HeaderProps {
  teachingEnabled: boolean;
  onToggleTeaching: () => void;
}

export function Header({ teachingEnabled, onToggleTeaching }: HeaderProps) {
  const { setError, setLoading } = useAppStore();
  const { sourcePath, activePath, summary, setSourceAndActivePath } = useDatasetStore();
  const isDerived = sourcePath !== activePath;
  const { buildModelSpec, applyModelSpec, setLastResult } = useModelStore();
  const {
    projectPath, manifest, runHistory, setProjectPath, setManifest, setRunHistory,
    rememberProject, resetProject, setDirty,
  } = useProjectStore();

  const buildManifest = () => {
    const now = new Date().toISOString();
    const workingDir = activePath ? inferWorkingDir(activePath) : 'apps/metrica-desktop';
    const { projectId } = useProjectStore.getState();
    return {
      workingDir,
      manifest: {
        project_id: manifest?.project_id ?? projectId,
        version: 1,
        created_at: manifest?.created_at ?? now,
        updated_at: now,
        source_dataset: sourcePath,
        active_dataset: activePath,
        saved_model_specs: [buildModelSpec()],
        last_run_id: runHistory[0]?.run_id ?? null,
        ui_state: { is_derived: isDerived, ncols: summary?.columns?.length ?? 0 },
        data_lineage: {
          source_dataset: sourcePath,
          active_dataset: activePath,
          operations: [],
          row_count_before: summary?.nrows,
          row_count_after: summary?.nrows,
          notes: [],
        },
      },
    };
  };

  const handleSaveProject = async () => {
    if (!sourcePath || !activePath) {
      setError('请先加载数据后再保存项目');
      return;
    }
    const { workingDir, manifest } = buildManifest();
    setLoading(true);
    try {
      const result = await saveProject(manifest, workingDir);
      setProjectPath(result.project_path);
      setManifest(result.manifest);
      rememberProject(result.project_path);
      setDirty(false);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : '保存项目失败');
    } finally {
      setLoading(false);
    }
  };

  const handleOpenProject = async () => {
    const hint = projectPath || (activePath ? `${activePath.slice(0, activePath.lastIndexOf('/')) || '.'}/.metrica/project.json` : '');
    const input = globalThis.prompt?.('请输入项目文件路径（默认使用当前项目路径）', hint) ?? hint;
    if (!input) return;
    const workingDir = input.endsWith('/.metrica/project.json') ? input.slice(0, input.length - '/.metrica/project.json'.length) : input.slice(0, input.lastIndexOf('/.metrica/project.json'));
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
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : '打开项目失败');
    } finally {
      setLoading(false);
    }
  };

  const handleRerun = async () => {
    if (!runHistory.length || !activePath) {
      setError('暂无可重跑的运行记录');
      return;
    }
    const workingDir = inferWorkingDir(activePath);
    setLoading(true);
    try {
      const result = await rerunTask(runHistory[0].run_id, workingDir);
      if (result.status === 'error') {
        setError(result.messages.map((m) => m.text).join('; '));
      } else if (result.result_payload && 'glance' in result.result_payload) {
        setLastResult(result.result_payload);
      }
      if (result.run_record) {
        useProjectStore.getState().appendRunRecord(result.run_record);
      }
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : '重跑失败');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 24px', height: 64, background: '#fff', borderBottom: '1px solid #f0f0f0' }}>
      <Title level={3} style={{ margin: 0, letterSpacing: 4, fontWeight: 700, color: '#8c8c8c' }}>METRICA</Title>
      <Space>
        <Button onClick={resetProject}>新建项目</Button>
        <Button icon={<FolderOpenOutlined />} onClick={handleOpenProject}>打开项目</Button>
        <Button icon={<SaveOutlined />} onClick={handleSaveProject}>保存项目</Button>
        <Button icon={<RedoOutlined />} onClick={handleRerun}>重跑上次</Button>
        <Button onClick={onToggleTeaching}>{teachingEnabled ? '教学开' : '教学关'}</Button>
      </Space>
    </div>
  );
}
