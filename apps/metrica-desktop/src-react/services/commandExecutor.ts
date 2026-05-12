/**
 * 命令执行器 — 将 executeCommand 的各 verb 分支提取为独立 handler。
 * 每个 handler 接收 parse 结果，返回 true/false/Promise<boolean>。
 */
import type { ParsedCommand } from './commandParser';
import { parseToModelSpec, parseToDiagnosticSpec, isDiagnosticVerb } from './commandParser';
import { parseToDataOp } from './commandDataOps';
import { executeDataOperations } from './dataOperationExecutor';
import { pickCsvFile } from './nativeHost';
import * as api from './runtimeClient';
import { useAppStore } from '../stores/appStore';
import { useModelStore } from '../stores/modelStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useMessageStore } from '../stores/messageStore';
import { useProjectStore } from '../stores/projectStore';
import type { CliFeedback } from '../components/CommandLine';

type FeedbackFn = (level: CliFeedback['level'], message: string) => void;
type CmdHandler = (parsed: ParsedCommand, input: string, feedback: FeedbackFn) => boolean | Promise<boolean>;

// ---- helpers ----

function setLoading(v: boolean) { useAppStore.getState().setLoading(v); }
function setError(msg: string | null) { useAppStore.getState().setError(msg); }
function getActivePath() { return useDatasetStore.getState().activePath; }

function normalizeTidyRow(raw: Record<string, unknown>): Record<string, unknown> {
  return {
    term: raw.name ?? raw.term ?? '',
    estimate: raw.estimate ?? null,
    std_error: raw.stderror ?? raw.std_error ?? null,
    statistic: raw.statistic ?? null,
    p_value: raw.pvalue ?? raw.p_value ?? null,
    ci_lower: raw.ci_lower ?? null,
    ci_upper: raw.ci_upper ?? null,
  };
}

function normalizePayload(payload: Record<string, unknown>): Record<string, unknown> {
  const tidy = payload.tidy as Record<string, unknown>[] | undefined;
  return {
    ...payload,
    tidy: tidy ? tidy.map(normalizeTidyRow) : undefined,
  };
}

// ---- use command ----

export const handleUse: CmdHandler = (parsed, _input, feedback) => {
  const raw = parsed.positionals[0] || '';
  const clearAll = () => {
    const ds = useDatasetStore.getState();
    ds.setSourceAndActivePath('', '');
    ds.setSummary(null);
    ds.clearBrowseContext();
    useAppStore.getState().setDataFullscreen(false);
    setError(null);
  };

  if (raw === 'clear') { clearAll(); return true; }

  let filePath = raw.replace(/^["']|["']$/g, '');
  if (!filePath) {
    return (async () => {
      try {
        const result = await pickCsvFile();
        if (result.cancelled || !result.path) return false;
        filePath = result.path;
      } catch (e: unknown) {
        feedback('warning', (e as Error).message || '文件选择失败');
        return false;
      }
      setLoading(true);
      try {
        const r = await api.inspectDataset(filePath);
        const ds = useDatasetStore.getState();
        ds.setSourceAndActivePath(filePath, filePath);
        ds.setSummary(r);
        ds.clearBrowseContext();
        useAppStore.getState().setDataFullscreen(false);
        setError(null);
      } catch (e: unknown) { setError((e as Error).message || '数据加载失败'); }
      finally { setLoading(false); }
      return true;
    })();
  }

  return (async () => {
    setLoading(true);
    try {
      const r = await api.inspectDataset(filePath);
      const ds = useDatasetStore.getState();
      ds.setSourceAndActivePath(filePath, filePath);
      ds.setSummary(r);
      ds.clearBrowseContext();
      useAppStore.getState().setDataFullscreen(false);
      setError(null);
    } catch (e: unknown) { setError((e as Error).message || '数据加载失败'); }
    finally { setLoading(false); }
    return true;
  })();
};

// ---- project command ----

export const handleProject: CmdHandler = (parsed, _input, feedback) => {
  const sub = parsed.positionals[0]?.toLowerCase();
  const ps = useProjectStore.getState();

  if (sub === 'new') {
    ps.resetProject();
    feedback('warning', 'project new 目前仅重置项目状态。完整保存对话框功能待后续版本。');
    return true;
  }
  if (sub === 'open') {
    const path = parsed.positionals[1] || '';
    if (!path) { feedback('warning', 'project open 需要指定项目文件路径'); return false; }
    return (async () => {
      setLoading(true);
      try {
        const result = await api.loadProject(path);
        ps.setProjectPath(result.project_path);
        ps.setManifest(result.manifest);
        const runs = await api.listRuns(path);
        ps.setRunHistory(runs);
        ps.rememberProject(result.project_path);
        const ds = useDatasetStore.getState();
        ds.setSourceAndActivePath(result.manifest.source_dataset, result.manifest.active_dataset);
        ds.clearBrowseContext();
        useAppStore.getState().setDataFullscreen(false);
        setError(null);
      } catch (e: unknown) { setError((e as Error).message || '打开项目失败'); }
      finally { setLoading(false); }
      return true;
    })();
  }
  if (sub === 'close') {
    ps.resetProject();
    const ds = useDatasetStore.getState();
    ds.setSourceAndActivePath('', '');
    ds.setSummary(null);
    ds.clearBrowseContext();
    useAppStore.getState().setDataFullscreen(false);
    setError(null);
    return true;
  }
  feedback('warning', 'project 子命令: new / open / close');
  return false;
};

// ---- trash command ----

export const handleTrash: CmdHandler = (parsed, _input, feedback) => {
  const sub = parsed.positionals[0]?.toLowerCase();
  const ms = useMessageStore.getState();
  const { addMessage } = ms;

  if (sub === 'list') {
    const trashed = ms.messages.filter(m => m.is_deleted);
    if (trashed.length === 0) { feedback('warning', '回收站为空'); return true; }
    addMessage({
      kind: 'data',
      command: 'trash list',
      data_result: {
        kind: 'tabulate',
        dataset_summary: { row_count: trashed.length, column_count: 2 },
        variable: 'trash', total: trashed.length, missing_count: 0, truncated: false,
        rows: trashed.map(m => ({ value: m.id, count: 0, pct: 0, cum_pct: 0 })),
      },
    });
    return true;
  }
  if (sub === 'restore') {
    const id = parsed.positionals[1];
    if (!id) { feedback('warning', 'trash restore 需要消息 ID'); return false; }
    ms.restoreMessages([id]);
    return true;
  }
  if (sub === 'clear') { ms.clearTrash(); return true; }
  feedback('warning', 'trash 子命令: list / restore <id> / clear');
  return false;
};

// ---- datahistory command ----

export const handleDatahistory: CmdHandler = (parsed, _input, feedback) => {
  const sub = parsed.positionals[0]?.toLowerCase();
  if (!sub || sub === 'list') { useAppStore.getState().setDataHistoryVisible(true); return true; }
  if (sub === 'restore') { feedback('warning', 'datahistory restore 请从数据历史面板操作'); return false; }
  feedback('warning', 'datahistory 子命令: list / restore <id>');
  return false;
};

// ---- save command ----

export const handleSave: CmdHandler = (_parsed, _input, feedback) => {
  const activePath = getActivePath();
  if (!activePath) { feedback('warning', '请先加载数据后再保存项目'); return false; }
  return (async () => {
    const ps = useProjectStore.getState();
    const ds = useDatasetStore.getState();
    const now = new Date().toISOString();
    const manifest = {
      project_id: ps.manifest?.project_id ?? ps.projectId ?? 'alpha-demo',
      version: 1,
      created_at: ps.manifest?.created_at ?? now,
      updated_at: now,
      source_dataset: ds.sourcePath,
      active_dataset: activePath,
      saved_model_specs: [] as any[],
      last_run_id: ps.runHistory[0]?.run_id ?? null,
      ui_state: {},
      data_lineage: null as any,
    };
    setLoading(true);
    try {
      const result = await api.saveProject(manifest, api.inferWorkingDir(activePath));
      ps.setProjectPath(result.project_path);
      ps.setManifest(result.manifest);
      ps.rememberProject(result.project_path);
      ps.setDirty(false);
      setError(null);
    } catch (e: unknown) { setError((e as Error).message || '保存项目失败'); }
    finally { setLoading(false); }
    return true;
  })();
};

// ---- data viewing commands ----

export const handleDataView: CmdHandler = (parsed, input, feedback) => {
  const activePath = getActivePath();
  const verb = parsed.verb;
  return (async () => {
    setLoading(true);
    try {
      const result = await api.runDataCommand({
        datasetPath: activePath,
        command: {
          kind: verb as 'describe' | 'browse' | 'summarize' | 'tabulate',
          variables: parsed.positionals.length > 0 ? parsed.positionals : undefined,
        },
      });
      const ds = useDatasetStore.getState();
      if (result.kind === 'browse') {
        ds.setBrowseContext(result.columns.map(c => c.name), result.readonly);
        useAppStore.getState().setDataFullscreen(true);
      } else {
        ds.clearBrowseContext();
        useMessageStore.getState().addMessage({ kind: 'data', command: input, data_result: result });
      }
      setError(null);
    } catch (e: unknown) { feedback('warning', (e as Error).message || '数据命令执行失败'); return false; }
    finally { setLoading(false); }
    return true;
  })();
};

// ---- data operation commands ----

export const handleDataOp: CmdHandler = (parsed, input, feedback) => {
  const opResult = parseToDataOp(parsed);
  if ('error' in opResult) { feedback('warning', opResult.error); return false; }
  return (async () => {
    try { await executeDataOperations({ operations: [opResult], commandLabel: input, source: 'cli' }); }
    catch { /* executeDataOperations 已写入结构化错误 */ }
    return true;
  })();
};

// ---- modeling commands ----

export const handleModel: CmdHandler = (parsed, input, feedback) => {
  const activePath = getActivePath();
  const specResult = parseToModelSpec(parsed);
  if ('error' in specResult) { feedback('warning', specResult.error); return false; }

  const spec = specResult;
  return (async () => {
    setLoading(true);
    try {
      const result = await api.fitModel({
        datasetPath: activePath,
        formula: spec.formula || '',
        modelType: spec.model_type,
        vcovType: (spec.vcov as any)?.type || 'classical',
        weightsColumn: spec.weights || spec.weights_column || '',
        clusterColumn: spec.cluster_column || '',
        panelId: spec.panel_id || '',
        panelTime: spec.panel_time || '',
        panelMethod: spec.panel_method || '',
        instruments: Array.isArray(spec.instruments) ? spec.instruments.join(',') : (spec.instruments || ''),
        endogColumns: Array.isArray(spec.endog_columns) ? spec.endog_columns.join(',') : (spec.endog_columns || ''),
        treatmentColumn: spec.treatment_column || spec.treated_column || '',
        postColumn: spec.post_column || '',
        eventTimeColumn: spec.event_time_column || '',
        outcomeColumn: spec.outcome_column || '',
        propensityFormula: spec.propensity_formula || '',
        outcomeFormula: spec.outcome_formula || '',
        timeColumn: spec.time_column || '',
        tsVariable: spec.variable || '',
        tsVariables: Array.isArray(spec.variables) ? spec.variables.join(',') : '',
        tsLags: spec.lags,
        tsDeterministic: spec.deterministic || 'constant',
        tsMethod: spec.ts_method || '',
        orderP: spec.order?.[0], orderD: spec.order?.[1], orderQ: spec.order?.[2],
        strataColumn: spec.strata_column || '', psuColumn: spec.psu_column || '', fpcColumn: spec.fpc_column || '',
      });
      const payload = (result as any).result_payload;
      if (payload && payload.glance) {
        const normalized = normalizePayload(payload);
        const ms = useModelStore.getState();
        ms.setLastResult(normalized as any);
        ms.addToHistory({
          id: crypto.randomUUID(),
          label: input, runId: (result as any).task_id || '',
          modelType: spec.model_type, formula: spec.formula || '',
          datasetPath: activePath, result: normalized as any,
          createdAt: new Date().toISOString(), command: input,
        });
        useMessageStore.getState().addMessage({ kind: 'result', command: input, result: normalized as any });
        setError(null);
      } else { setError('模型返回结果异常'); }
    } catch (e: unknown) { setError((e as Error).message || '模型拟合失败'); }
    finally { setLoading(false); }
    return true;
  })();
};

// ---- diagnostic / post-estimation ----

const POSTEST_VERBS = new Set(['predict', 'margins', 'test', 'lincom', 'estimates']);

export const handleDiagnostic: CmdHandler = (parsed, input, feedback) => {
  const specResult = parseToDiagnosticSpec(parsed);
  if ('error' in specResult) { feedback('warning', specResult.error); return false; }

  const ms = useModelStore.getState();
  const { lastResult, formula, modelType } = ms;
  if (!lastResult || !formula) {
    feedback('warning', '请先运行模型（如 regress）再执行诊断命令。');
    return false;
  }

  const activePath = getActivePath();
  if (!activePath) {
    feedback('warning', '请先加载数据集。');
    return false;
  }

  const spec = specResult;
  return (async () => {
    setLoading(true);
    try {
      const result = await api.runDiagnostic({
        datasetPath: activePath,
        formula,
        modelType,
        diagnostic: spec,
      });
      const ms2 = useMessageStore.getState();
      ms2.addMessage({
        kind: 'result',
        command: input,
        result: {
          glance: { model: `diagnostic:${spec.test}`, nobs: 0, dof: 0, metrics: {} },
          tidy: [],
          diagnostics: { [spec.test]: result },
          warnings: [],
        },
      });
      setError(null);
    } catch (e: unknown) {
      setError((e as Error).message || '诊断命令执行失败');
    } finally {
      setLoading(false);
    }
    return true;
  })();
};

export const handlePostest: CmdHandler = (parsed, _input, feedback) => {
  feedback('warning', `后估计命令 ${parsed.verb} 将在后续版本中支持。请先运行模型后重试。`);
  return false;
};

// ---- router ----

/** 是否需要活动数据集（model / data-op / data-view / diagnostic 命令需要） */
export function requiresActiveDataset(verb: string): boolean {
  return !['use', 'project', 'trash', 'datahistory', 'save'].includes(verb)
    && !POSTEST_VERBS.has(verb);
}

export { isDiagnosticVerb };
export function isPostestVerb(verb: string) { return POSTEST_VERBS.has(verb); }
