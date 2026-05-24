import { beforeEach, describe, expect, it, vi } from 'vitest';
import { parse } from '../services/commandParser';
import {
  handleLoad,
  handleRuns,
  handleRerun,
  handleExport,
  handleCompare,
  handleSave,
} from '../services/commandExecutor';
import { useProjectStore } from '../stores/projectStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useMessageStore } from '../stores/messageStore';
import { useModelStore } from '../stores/modelStore';
import { useAppStore } from '../stores/appStore';
import * as exportStore from '../stores/exportStore';
import type { FitModelRunRecord, ModelResult, ProjectManifest } from '../types/protocol';

const rtMocks = vi.hoisted(() => ({
  loadProject: vi.fn(),
  listRuns: vi.fn(),
  rerunTask: vi.fn(),
  exportReport: vi.fn(),
  saveProject: vi.fn(),
  inspectDataset: vi.fn(),
  fitModel: vi.fn(),
}));

vi.mock('../services/runtimeClient', async (importOriginal) => {
  const mod = await importOriginal<typeof import('../services/runtimeClient')>();
  return {
    ...mod,
    loadProject: (...args: unknown[]) => rtMocks.loadProject(...args) as ReturnType<typeof mod.loadProject>,
    listRuns: (...args: unknown[]) => rtMocks.listRuns(...args) as ReturnType<typeof mod.listRuns>,
    rerunTask: (...args: unknown[]) => rtMocks.rerunTask(...args) as ReturnType<typeof mod.rerunTask>,
    exportReport: (...args: unknown[]) => rtMocks.exportReport(...args) as ReturnType<typeof mod.exportReport>,
    saveProject: (...args: unknown[]) => rtMocks.saveProject(...args) as ReturnType<typeof mod.saveProject>,
    inspectDataset: (...args: unknown[]) => rtMocks.inspectDataset(...args) as ReturnType<typeof mod.inspectDataset>,
    fitModel: (...args: unknown[]) => rtMocks.fitModel(...args) as ReturnType<typeof mod.fitModel>,
  };
});

const hostMocks = vi.hoisted(() => ({
  pickProjectOpenPath: vi.fn(),
  pickProjectSavePath: vi.fn(),
  pickExportSavePath: vi.fn(),
}));

vi.mock('../services/nativeHost', () => ({
  pickCsvFile: vi.fn(),
  pickProjectOpenPath: (...args: unknown[]) => hostMocks.pickProjectOpenPath(...args),
  pickProjectSavePath: (...args: unknown[]) => hostMocks.pickProjectSavePath(...args),
  pickExportSavePath: (...args: unknown[]) => hostMocks.pickExportSavePath(...args),
}));

const noopFeedback = () => {};

function baseManifest(over: Partial<ProjectManifest> = {}): ProjectManifest {
  const now = '2024-01-01T00:00:00.000Z';
  return {
    project_id: 'alpha-demo',
    version: 1,
    created_at: now,
    updated_at: now,
    source_dataset: '/data/demo.csv',
    active_dataset: '/data/demo.csv',
    saved_model_specs: [],
    last_run_id: null,
    ui_state: {},
    ...over,
  };
}

function logitResultSummary(): ModelResult {
  return {
    glance: {
      model: 'logit',
      nobs: 120,
      dof: 117,
      metrics: { aic: 130, bic: 140, loglikelihood: -55 },
    },
    tidy: [],
    diagnostics: {} as ModelResult['diagnostics'],
    warnings: [],
    loglikelihood: -55,
  };
}

function makeFitRun(id: string, path = '/data/demo.csv'): FitModelRunRecord {
  return {
    action: 'fit_model',
    run_id: id,
    started_at: '2024-01-01T00:00:00Z',
    finished_at: '2024-01-01T00:01:00Z',
    status: 'success',
    dataset_ref: { source: 'file', path, format: 'csv' },
    warnings: [],
    messages: [],
    artifacts: [],
    model_spec: {
      model_type: 'logit',
      formula: 'y_bin ~ x1 + x2',
      params: {},
    } as FitModelRunRecord['model_spec'],
    result_summary: logitResultSummary(),
  };
}

describe('commandExecutor 项目与导出 handler', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    rtMocks.loadProject.mockReset();
    rtMocks.listRuns.mockReset();
    rtMocks.rerunTask.mockReset();
    rtMocks.exportReport.mockReset();
    rtMocks.saveProject.mockReset();
    rtMocks.inspectDataset.mockReset();
    rtMocks.fitModel.mockReset();
    hostMocks.pickProjectOpenPath.mockReset();
    hostMocks.pickProjectSavePath.mockReset();
    hostMocks.pickExportSavePath.mockReset();

    useAppStore.setState({
      error: null,
      isLoading: false,
      juliaHealthy: true,
      healthChecked: true,
      restartCount: 0,
      healthPollingId: null,
      dataFullscreen: false,
    });
    useProjectStore.setState({
      projectPath: '',
      projectWorkingDir: '',
      manifest: null,
      recentProjects: [],
      runHistory: [],
      isDirty: false,
      projectId: 'alpha-demo',
      lastRecoveredAt: null,
    });
    useDatasetStore.setState({
      sourcePath: '',
      activePath: '',
      summary: null,
      browseColumns: null,
      browseReadonly: false,
    });
    useMessageStore.setState({ messages: [], trash: [], selectedIds: new Set(), selectionMode: 'none' });
    useModelStore.setState({ lastResult: null, modelHistory: [] });
  });

  it('load：调用 loadProject/listRuns/inspectDataset，不调用 fitModel', async () => {
    const manifest = baseManifest();
    rtMocks.loadProject.mockResolvedValue({ project_path: '/tmp/proj.metrica', manifest });
    rtMocks.listRuns.mockResolvedValue([]);
    rtMocks.inspectDataset.mockResolvedValue({
      nrows: 10,
      ncols: 3,
      columns: [],
      preview: [],
    });

    const parsed = parse('load "/tmp/proj.metrica"');
    await handleLoad(parsed, 'load "/tmp/proj.metrica"', noopFeedback);

    expect(rtMocks.loadProject).toHaveBeenCalled();
    expect(rtMocks.listRuns).toHaveBeenCalled();
    expect(rtMocks.inspectDataset).toHaveBeenCalled();
    expect(rtMocks.fitModel).not.toHaveBeenCalled();
  });

  it('runs：调用 listRuns 并追加 kind=runs 的结构化 data 消息', async () => {
    useProjectStore.setState({ projectWorkingDir: '/tmp/wd' });
    useDatasetStore.setState({
      activePath: '/data/demo.csv',
      summary: { nrows: 5, ncols: 2, columns: [], preview: [] },
    });
    const runs = [makeFitRun('run-a')];
    rtMocks.listRuns.mockResolvedValue(runs);

    const parsed = parse('runs');
    await handleRuns(parsed, 'runs', noopFeedback);

    expect(rtMocks.listRuns).toHaveBeenCalledWith('/tmp/wd', 'alpha-demo');
    const msgs = useMessageStore.getState().messages;
    const last = msgs[msgs.length - 1];
    expect(last.kind).toBe('data');
    expect(last.data_result?.kind).toBe('runs');
    expect((last.data_result as { runs?: unknown[] })?.runs).toHaveLength(1);
  });

  it('rerun：成功后追加 result 消息并 appendRunRecord', async () => {
    useProjectStore.setState({ projectWorkingDir: '/tmp/wd' });
    const rr = makeFitRun('run-new');
    rtMocks.rerunTask.mockResolvedValue({
      task_id: 't1',
      status: 'success',
      messages: [],
      result_payload: logitResultSummary(),
      run_record: rr,
    });

    const parsed = parse('rerun run-new');
    await handleRerun(parsed, 'rerun run-new', noopFeedback);

    expect(rtMocks.rerunTask).toHaveBeenCalledWith('run-new', '/tmp/wd', 'alpha-demo');
    expect(useProjectStore.getState().runHistory.some((r) => r.run_id === 'run-new')).toBe(true);
    expect(useMessageStore.getState().messages.some((m) => m.kind === 'result')).toBe(true);
  });

  it('save：请求中的 data_lineage.operations 不丢失', async () => {
    useDatasetStore.setState({
      sourcePath: '/src.csv',
      activePath: '/act.csv',
    });
    const manifest = baseManifest({
      data_lineage: {
        source_dataset: '/src.csv',
        active_dataset: '/act.csv',
        operations: [{ op: 'filter', args: { expr: 'x1 > 0' } }],
        notes: ['教学备注'],
      },
    });
    useProjectStore.setState({ manifest });

    rtMocks.saveProject.mockImplementation(async (m: ProjectManifest) => ({
      project_path: '/tmp/saved.metrica',
      manifest: m,
    }));

    const parsed = parse('save "/tmp/saved.metrica"');
    await handleSave(parsed, 'save "/tmp/saved.metrica"', noopFeedback);

    expect(rtMocks.saveProject).toHaveBeenCalled();
    const sent = rtMocks.saveProject.mock.calls[0][0] as ProjectManifest;
    expect(sent.data_lineage?.operations).toHaveLength(1);
    expect(sent.data_lineage?.operations?.[0]).toMatchObject({ op: 'filter', args: { expr: 'x1 > 0' } });
  });

  it('export markdown：带 using 时调用 exportReport 并触发 downloadText', async () => {
    const dlSpy = vi.spyOn(exportStore, 'downloadText').mockImplementation(() => {});
    useProjectStore.setState({
      projectWorkingDir: '/wd',
      runHistory: [makeFitRun('run-a')],
    });
    useDatasetStore.setState({ activePath: '/data/demo.csv' });
    rtMocks.exportReport.mockResolvedValue({
      content: '# 报告',
      format: 'markdown',
      run_id: 'run-a',
    });

    const parsed = parse('export markdown run-a, using("/tmp/out.md")');
    await handleExport(parsed, 'export markdown run-a, using("/tmp/out.md")', noopFeedback);

    expect(rtMocks.exportReport).toHaveBeenCalledWith(
      expect.objectContaining({ runId: 'run-a', format: 'markdown', workingDir: '/wd' }),
    );
    expect(dlSpy).toHaveBeenCalled();
    const msgs = useMessageStore.getState().messages;
    const dataMsg = msgs.find((m) => m.kind === 'data' && m.data_result?.kind === 'export_preview');
    expect(dataMsg?.data_result).toMatchObject({
      kind: 'export_preview',
      run_id: 'run-a',
      format: 'markdown',
      target_path: '/tmp/out.md',
    });
    dlSpy.mockRestore();
  });

  it('export markdown：run 不存在时不调用 exportReport', async () => {
    useProjectStore.setState({ projectWorkingDir: '/wd', runHistory: [] });
    useDatasetStore.setState({ activePath: '/data/demo.csv' });

    const parsed = parse('export markdown missing-id, using("/tmp/out.md")');
    await handleExport(parsed, 'export markdown missing-id, using("/tmp/out.md")', noopFeedback);

    expect(rtMocks.exportReport).not.toHaveBeenCalled();
  });

  it('compare：两个同路径 logit run 生成 model_comparison 消息', async () => {
    useDatasetStore.setState({
      summary: { nrows: 50, ncols: 4, columns: [], preview: [] },
    });
    useProjectStore.setState({
      runHistory: [makeFitRun('r1'), makeFitRun('r2')],
    });

    const parsed = parse('compare r1 r2');
    await handleCompare(parsed, 'compare r1 r2', noopFeedback);

    const msg = useMessageStore.getState().messages.find((m) => m.data_result?.kind === 'model_comparison');
    expect(msg?.data_result?.kind).toBe('model_comparison');
    expect((msg?.data_result as { rows?: unknown[] })?.rows?.length).toBe(2);
  });

  it('compare clear：移除 model_comparison 类 data 消息', async () => {
    useMessageStore.getState().addMessage({
      kind: 'data',
      command: 'compare r1 r2',
      data_result: {
        kind: 'model_comparison',
        dataset_summary: { row_count: 1, column_count: 1 },
        family: 'discrete',
        rows: [],
      },
    });
    const parsed = parse('compare clear');
    await handleCompare(parsed, 'compare clear', noopFeedback);
    expect(useMessageStore.getState().messages.some((m) => m.data_result?.kind === 'model_comparison')).toBe(
      false,
    );
  });
});
