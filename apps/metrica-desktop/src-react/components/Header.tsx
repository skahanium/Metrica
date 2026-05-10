import { Dropdown, Space, Typography, Button } from 'antd';
import {
  ProjectOutlined,
  DatabaseOutlined,
  ExportOutlined,
  FolderOpenOutlined,
  SaveOutlined,
  FileAddOutlined,
  ImportOutlined,
  TableOutlined,
  HistoryOutlined,
  SwapOutlined,
  FileTextOutlined,
  DownloadOutlined,
} from '@ant-design/icons';
import { useAppStore } from '../stores/appStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useProjectStore } from '../stores/projectStore';
import { saveProject, loadProject, listRuns, inferWorkingDir, inspectDataset } from '../services/runtimeClient';
import { pickCsvFile } from '../services/nativeHost';
import type { MenuProps } from 'antd';

const { Title } = Typography;

export function Header() {
  const { setError, setLoading, setDataFullscreen, setDataHistoryVisible } = useAppStore();
  const { sourcePath, activePath, summary, setSourceAndActivePath, setSummary, clearBrowseContext } = useDatasetStore();
  const {
    projectPath, manifest, runHistory, setProjectPath, setManifest, setRunHistory,
    rememberProject, resetProject, setDirty, recentProjects,
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
        saved_model_specs: [],
        last_run_id: runHistory[0]?.run_id ?? null,
        ui_state: { is_derived: sourcePath !== activePath, ncols: summary?.columns?.length ?? 0 },
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

  const handleOpenProject = async (path?: string) => {
    const hint = path || projectPath || (activePath ? `${activePath.slice(0, activePath.lastIndexOf('/')) || '.'}/.metrica/project.json` : '');
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
      clearBrowseContext();
      setDataFullscreen(false);
      rememberProject(result.project_path);
      setDirty(false);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : '打开项目失败');
    } finally {
      setLoading(false);
    }
  };

  const handleImportCsv = async () => {
    setError(null);
    setLoading(true);
    try {
      const result = await pickCsvFile();
      if (result.cancelled || !result.path) return;
      setSourceAndActivePath(result.path, result.path);
      setSummary(null);
      clearBrowseContext();
      setDataFullscreen(false);
      setDirty(true);
      // 加载数据摘要
      const workingDir = inferWorkingDir(result.path);
      const summary = await inspectDataset(result.path, workingDir);
      setSummary(summary);
    } catch (e) {
      setError(e instanceof Error ? e.message : '导入 CSV 失败');
    } finally {
      setLoading(false);
    }
  };

  // 项目菜单
  const projectMenuItems: MenuProps['items'] = [
    { key: 'new', icon: <FileAddOutlined />, label: '新建项目', onClick: resetProject },
    { key: 'open', icon: <FolderOpenOutlined />, label: '打开项目', onClick: () => handleOpenProject() },
    { key: 'save', icon: <SaveOutlined />, label: '保存项目', onClick: handleSaveProject },
    { key: 'saveas', icon: <SaveOutlined />, label: '另存为...', disabled: true },
    { type: 'divider' },
    ...(recentProjects.length > 0 ? [
      { key: 'recent-label', label: '最近项目', type: 'group' as const, children: recentProjects.slice(0, 5).map((p) => ({
        key: `recent-${p}`,
        label: p.split('/').pop() || p,
        onClick: () => handleOpenProject(p),
      })) },
    ] : []),
    { type: 'divider' },
    { key: 'close', label: '关闭项目', onClick: resetProject },
  ];

  // 数据菜单
  const dataMenuItems: MenuProps['items'] = [
    { key: 'import', icon: <ImportOutlined />, label: '导入 CSV', onClick: handleImportCsv },
    { key: 'viewall', icon: <TableOutlined />, label: '查看全部数据', onClick: () => setDataFullscreen(true), disabled: !summary },
    { type: 'divider' },
    { key: 'transform', icon: <SwapOutlined />, label: '数据变换', disabled: !summary },
    { key: 'history', icon: <HistoryOutlined />, label: '数据历史', onClick: () => setDataHistoryVisible(true), disabled: !summary },
  ];

  // 导出菜单
  const exportMenuItems: MenuProps['items'] = [
    { key: 'script', icon: <FileTextOutlined />, label: '导出命令脚本', disabled: true },
    { key: 'result', icon: <DownloadOutlined />, label: '导出当前结果', disabled: true },
    { key: 'selected', icon: <DownloadOutlined />, label: '导出选中结果', disabled: true },
    { type: 'divider' },
    { key: 'report', icon: <FileTextOutlined />, label: '导出项目报告', disabled: true },
    { key: 'csv', icon: <DownloadOutlined />, label: '导出活动数据 CSV', disabled: !summary },
  ];

  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 24px', height: 64, background: '#fff', borderBottom: '1px solid #f0f0f0',
    }}>
      <Title level={3} style={{ margin: 0, letterSpacing: 4, fontWeight: 700, color: '#8c8c8c' }}>
        METRICA
      </Title>
      <Space size="large">
        <Dropdown menu={{ items: projectMenuItems }} trigger={['click']}>
          <Button type="text" icon={<ProjectOutlined />}>项目</Button>
        </Dropdown>
        <Dropdown menu={{ items: dataMenuItems }} trigger={['click']}>
          <Button type="text" icon={<DatabaseOutlined />}>数据</Button>
        </Dropdown>
        <Dropdown menu={{ items: exportMenuItems }} trigger={['click']}>
          <Button type="text" icon={<ExportOutlined />}>导出</Button>
        </Dropdown>
      </Space>
    </div>
  );
}
