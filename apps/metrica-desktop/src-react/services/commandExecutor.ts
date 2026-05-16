/**
 * 命令执行器 — 将 executeCommand 的各 verb 分支提取为独立 handler。
 * 每个 handler 接收 parse 结果，返回 true/false/Promise<boolean>。
 */
import type { ParsedCommand } from './commandParser';
import { parseToModelSpec, parseToDiagnosticSpec, isDiagnosticVerb } from './commandParser';
import { parseToDataOp } from './commandDataOps';
import { executeDataOperations } from './dataOperationExecutor';
import { pickCsvFile, pickExportSavePath, pickProjectOpenPath, pickProjectSavePath } from './nativeHost';
import { projectRootFromManifestPath, resolveProjectWorkingDirFromUserPath } from './projectPaths';
import { buildCausalComparisonRows, buildDiscreteComparisonRows, resolveCompareRuns } from './modelComparison';
import { exportRegisteredChartDataUrl } from './chartExport';
import * as api from './runtimeClient';
import { useAppStore } from '../stores/appStore';
import { useModelStore } from '../stores/modelStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useMessageStore } from '../stores/messageStore';
import { useProjectStore } from '../stores/projectStore';
import { downloadDataUrl, downloadText, generateExportFilename, useExportStore } from '../stores/exportStore';
import type { CliFeedback, DatasetSummary, TaskResponse } from '../types/protocol';
import { isFitModelRun } from '../types/protocol';

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

function projectIdForApi(): string {
  const ps = useProjectStore.getState();
  return ps.manifest?.project_id ?? ps.projectId ?? 'alpha-demo';
}

function stripQuotes(s: string): string {
  return s.replace(/^["']|["']$/g, '');
}

function getLastSuccessfulFitRunId(): string | null {
  const runs = useProjectStore.getState().runHistory;
  for (const r of runs) {
    if (isFitModelRun(r) && r.status === 'success' && r.result_summary) return r.run_id;
  }
  return null;
}

function findRunById(runId: string) {
  return useProjectStore.getState().runHistory.find((r) => r.run_id === runId);
}

/** 加载项目 manifest + runs，并恢复数据集路径到 store */
async function loadProjectIntoStores(workingDir: string): Promise<void> {
  const ps = useProjectStore.getState();
  const result = await api.loadProject(workingDir, projectIdForApi());
  ps.setProjectPath(result.project_path);
  ps.setProjectWorkingDir(projectRootFromManifestPath(result.project_path));
  ps.setManifest(result.manifest);
  const runs = await api.listRuns(workingDir, projectIdForApi());
  ps.setRunHistory(runs);
  ps.rememberProject(result.project_path);
  const ds = useDatasetStore.getState();
  ds.setSourceAndActivePath(result.manifest.source_dataset, result.manifest.active_dataset);
  try {
    const summary = await api.inspectDataset(result.manifest.active_dataset);
    ds.setSummary(summary);
  } catch {
    // 数据集可能暂不可读，仍保留路径以便用户修复后重试。
    ds.setSummary(null);
  }
  ds.clearBrowseContext();
  useAppStore.getState().setDataFullscreen(false);
  setError(null);
}

/** Julia 进程恢复后从磁盘重载项目与数据集路径（不自动重跑模型） */
export async function recoverJuliaWorkspaceIfPossible(): Promise<void> {
  const wd = useProjectStore.getState().projectWorkingDir;
  if (!wd) return;
  const last = useProjectStore.getState().lastRecoveredAt;
  if (last && Date.now() - Date.parse(last) < 60_000) return;
  try {
    await loadProjectIntoStores(wd);
    useProjectStore.getState().markRecovered();
    useMessageStore.getState().addMessage({
      kind: 'command',
      command: '[系统] Julia 计算引擎已重启，项目上下文已从磁盘恢复；如需重算请使用 rerun。',
    });
  } catch {
    // 恢复失败时不抛错，避免干扰健康轮询。
  }
}

// ---- use command ----

export const handleUse: CmdHandler = (parsed, _input, feedback) => {
  const raw = parsed.positionals[0] || '';
  console.log('[handleUse] raw:', raw);
  const clearAll = () => {
    const ds = useDatasetStore.getState();
    ds.setSourceAndActivePath('', '');
    ds.setSummary(null);
    ds.clearBrowseContext();
    useAppStore.getState().setDataFullscreen(false);
    setError(null);
  };

  if (raw === 'clear') { clearAll(); feedback('success', '已清空当前数据集'); return true; }

  let filePath = raw.replace(/^["']|["']$/g, '');
  if (!filePath) {
    return (async () => {
      try {
        const result = await pickCsvFile();
        if (result.cancelled || !result.path) return false;
        filePath = result.path;
      } catch (e: unknown) {
        feedback('error', (e as Error).message || '文件选择失败');
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
        const fileName = filePath.split('/').pop() || filePath;
        feedback('success', `已加载 ${fileName}（${r.nrows} 行 × ${r.ncols} 列）`);
        useMessageStore.getState().addMessage({ kind: 'result', command: `use ${filePath}`, result: { glance: null as any, tidy: [], warnings: [], diagnostics: {} } });
        try {
          const describeResult = await api.runDataCommand({
            datasetPath: filePath,
            command: { kind: 'describe' },
          });
          useMessageStore.getState().addMessage({ kind: 'data', command: '', data_result: describeResult as import('../types/protocol').DataResult });
        } catch (err) { feedback('warning', '自动描述失败，可手动执行 describe 命令'); }
      } catch (e: unknown) {
        feedback('error', (e as Error).message || '数据加载失败');
        setError((e as Error).message || '数据加载失败');
      }
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
      const fileName = filePath.split('/').pop() || filePath;
      feedback('success', `已加载 ${fileName}（${r.nrows} 行 × ${r.ncols} 列）`);
      useMessageStore.getState().addMessage({ kind: 'result', command: `use ${filePath}`, result: { glance: null as any, tidy: [], warnings: [], diagnostics: {} } });
      try {
        const describeResult = await api.runDataCommand({
          datasetPath: filePath,
          command: { kind: 'describe' },
        });
        useMessageStore.getState().addMessage({ kind: 'data', command: '', data_result: describeResult as import('../types/protocol').DataResult });
      } catch (err) { feedback('warning', '自动描述失败，可手动执行 describe 命令'); }
    } catch (e: unknown) {
      feedback('error', (e as Error).message || '数据加载失败');
      setError((e as Error).message || '数据加载失败');
    }
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
    let raw = parsed.positionals[1] || '';
    raw = stripQuotes(raw);
    if (!raw) {
      feedback('warning', 'project open 需要指定项目路径，或使用 load 命令。');
      return false;
    }
    const workingDir = resolveProjectWorkingDirFromUserPath(raw);
    return (async () => {
      setLoading(true);
      try {
        await loadProjectIntoStores(workingDir);
      } catch (e: unknown) {
        setError((e as Error).message || '打开项目失败');
      } finally {
        setLoading(false);
      }
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

// ---- load / runs / rerun（CLI 主路径） ----

export const handleLoad: CmdHandler = (parsed, _input, feedback) => {
  let raw = parsed.positionals[0] || '';
  raw = stripQuotes(raw);
  return (async () => {
    if (!raw) {
      try {
        const pick = await pickProjectOpenPath();
        if (pick.cancelled || !pick.path) {
          feedback('warning', '已取消加载项目。');
          return false;
        }
        raw = pick.path;
        feedback('success', `等价命令：load "${raw}"`);
      } catch (e: unknown) {
        feedback('error', (e as Error).message || '项目路径选择失败');
        return false;
      }
    }
    const workingDir = resolveProjectWorkingDirFromUserPath(raw);
    setLoading(true);
    try {
      await loadProjectIntoStores(workingDir);
      feedback('success', '项目已加载，运行记录与数据集路径已恢复。');
    } catch (e: unknown) {
      setError((e as Error).message || '加载项目失败');
    } finally {
      setLoading(false);
    }
    return true;
  })();
};

export const handleRuns: CmdHandler = (_parsed, input, feedback) => {
  const ps = useProjectStore.getState();
  const wd = ps.projectWorkingDir || api.inferWorkingDir(getActivePath());
  if (!wd) {
    feedback('warning', '请先加载数据集或打开项目后再执行 runs。');
    return false;
  }
  return (async () => {
    setLoading(true);
    try {
      const runs = await api.listRuns(wd, projectIdForApi());
      useProjectStore.getState().setRunHistory(runs);
      const ds = useDatasetStore.getState().summary;
      const rows = runs.map((r) => ({
        run_id: r.run_id,
        action: r.action,
        model_type: isFitModelRun(r) ? r.model_spec?.model_type ?? null : null,
        dataset_path: r.dataset_ref.path,
        status: r.status,
        finished_at: r.finished_at,
      }));
      useMessageStore.getState().addMessage({
        kind: 'data',
        command: input,
        data_result: {
          kind: 'runs',
          dataset_summary: { row_count: ds?.nrows ?? 0, column_count: ds?.ncols ?? 0 },
          runs: rows,
        },
      });
      feedback('success', `已列出 ${runs.length} 条运行记录。`);
      setError(null);
    } catch (e: unknown) {
      feedback('error', (e as Error).message || 'list_runs 失败');
    } finally {
      setLoading(false);
    }
    return true;
  })();
};

export const handleRerun: CmdHandler = (parsed, input, feedback) => {
  const runId = stripQuotes(parsed.positionals[0] || '');
  if (!runId) {
    feedback('warning', 'rerun 需要 run_id，例如：rerun run-1');
    return false;
  }
  const ps = useProjectStore.getState();
  const wd = ps.projectWorkingDir || api.inferWorkingDir(getActivePath());
  if (!wd) {
    feedback('warning', '无法解析项目工作目录，请先 load/save 项目或加载数据集。');
    return false;
  }
  return (async () => {
    setLoading(true);
    try {
      const resp = await api.rerunTask(runId, wd, projectIdForApi()) as TaskResponse;
      if (resp.status !== 'success') {
        const txt = resp.messages?.map((m) => m.text).join('; ') || 'rerun 失败';
        feedback('warning', txt);
        return false;
      }
      const payload = resp.result_payload as Record<string, unknown> | undefined;
      const rr = resp.run_record;
      if (payload && (payload as { glance?: unknown }).glance && rr && isFitModelRun(rr)) {
        const normalized = normalizePayload(payload);
        const ms = useModelStore.getState();
        if (rr.model_spec) ms.applyModelSpec(rr.model_spec);
        ms.setLastResult(normalized as unknown as import('../types/protocol').ModelResult);
        ms.addToHistory({
          id: crypto.randomUUID(),
          label: input,
          runId: rr.run_id,
          modelType: (rr.model_spec?.model_type ?? 'ols') as import('../types/protocol').ModelSpec['model_type'],
          formula: rr.model_spec?.formula ?? '',
          datasetPath: rr.dataset_ref.path,
          result: normalized as unknown as import('../types/protocol').ModelResult,
          createdAt: new Date().toISOString(),
          command: input,
        });
        useMessageStore.getState().addMessage({
          kind: 'result',
          command: input,
          run_id: rr.run_id,
          result: normalized as unknown as import('../types/protocol').ModelResult,
        });
        useProjectStore.getState().appendRunRecord(rr);
      }
      setError(null);
      feedback('success', '重跑已完成。');
    } catch (e: unknown) {
      setError((e as Error).message || 'rerun 失败');
    } finally {
      setLoading(false);
    }
    return true;
  })();
};

export const handleExport: CmdHandler = (parsed, input, feedback) => {
  const format = (parsed.positionals[0] || '').toLowerCase();
  const optMap = new Map(parsed.options.map((o) => [o.name, o.value]));
  let runId = stripQuotes(parsed.positionals[1] || '');
  const usingRaw = optMap.get('using');
  const usingPath = usingRaw ? stripQuotes(usingRaw) : '';

  if (!['markdown', 'csv_tidy', 'csv_glance', 'csv_diagnostics', 'plot'].includes(format)) {
    feedback('warning', `不支持的导出格式：${format}`);
    return false;
  }

  if (format === 'plot') {
    if (!runId) {
      feedback('warning', 'export plot 必须显式指定 run_id。');
      return false;
    }
    const imgFmt = (optMap.get('format') || '').toLowerCase();
    if (imgFmt !== 'svg' && imgFmt !== 'png') {
      feedback('warning', 'export plot 必须使用 format(svg) 或 format(png)。不支持 pdf 等其他格式。');
      return false;
    }
    const run = findRunById(runId);
    const glanceModel = run && isFitModelRun(run) ? run.result_summary?.glance?.model : undefined;
    if (glanceModel !== 'event_study') {
      feedback('warning', '当前 run 无可导出的图表（仅事件研究 run 支持 plot 导出）。');
      return false;
    }
    return (async () => {
      let targetPath = usingPath || null;
      if (!targetPath) {
        try {
          const pick = await pickExportSavePath(`metrica-plot-${runId}.${imgFmt}`);
          if (pick.cancelled || !pick.path) {
            feedback('warning', '已取消导出路径选择，未调用 Runtime。');
            return false;
          }
          targetPath = pick.path;
        } catch (e: unknown) {
          feedback('error', (e as Error).message || '导出路径选择失败');
          return false;
        }
      }
      const out = await exportRegisteredChartDataUrl(runId, imgFmt as 'svg' | 'png');
      if ('error' in out) {
        feedback('warning', out.error);
        return false;
      }
      const fname = targetPath.split('/').pop() || `metrica-plot.${imgFmt}`;
      downloadDataUrl(out.dataUrl, fname);
      useMessageStore.getState().addMessage({
        kind: 'data',
        command: input,
        data_result: {
          kind: 'export_preview',
          dataset_summary: { row_count: 1, column_count: 4 },
          run_id: runId,
          format: `plot/${imgFmt}`,
          target_path: targetPath,
          content_preview: `${out.dataUrl.slice(0, 80)}…`,
        },
      });
      feedback('success', `图表已触发下载：${fname}`);
      return true;
    })();
  }

  // ---- 文本类导出（Runtime export_report） ----
  return (async () => {
    if (!runId) {
      runId = getLastSuccessfulFitRunId() || '';
      if (!runId) {
        feedback('warning', '请指定 run_id，或先成功运行至少一次模型拟合。');
        return false;
      }
    }
    const existing = findRunById(runId);
    if (!existing) {
      feedback('warning', `运行记录不存在：${runId}。可先执行 runs 同步列表。`);
      return false;
    }
    let targetPath = usingPath || null;
    if (!targetPath) {
      try {
        const ext = format.startsWith('csv') ? 'csv' : 'md';
        const pick = await pickExportSavePath(generateExportFilename(format, 'model', runId).replace(/\.[^.]+$/, `.${ext}`));
        if (pick.cancelled || !pick.path) {
          feedback('warning', '已取消导出路径选择，未调用 Runtime。');
          return false;
        }
        targetPath = pick.path;
      } catch (e: unknown) {
        feedback('error', (e as Error).message || '导出路径选择失败');
        return false;
      }
    }
    const wd = useProjectStore.getState().projectWorkingDir || api.inferWorkingDir(getActivePath());
    useExportStore.getState().setIsExporting(true);
    try {
      const body = await api.exportReport({
        runId,
        format: format as 'markdown' | 'csv_tidy' | 'csv_glance' | 'csv_diagnostics',
        workingDir: wd,
        projectId: projectIdForApi(),
      });
      const mime = format.startsWith('csv') ? 'text/csv;charset=utf-8' : 'text/markdown;charset=utf-8';
      const fname = targetPath.split('/').pop() || generateExportFilename(format, 'model', runId);
      downloadText(body.content, fname, mime);
      useMessageStore.getState().addMessage({
        kind: 'data',
        command: input,
        data_result: {
          kind: 'export_preview',
          dataset_summary: { row_count: 1, column_count: 4 },
          run_id: body.run_id,
          format,
          target_path: targetPath,
          content_preview: body.content.slice(0, 400),
        },
      });
      useExportStore.getState().addExportHistory({
        runId: body.run_id,
        format,
        exportedAt: new Date().toISOString(),
        content: body.content.slice(0, 2000),
      });
      feedback('success', '导出内容已下载，并在结果流中显示摘要。');
      setError(null);
    } catch (e: unknown) {
      setError((e as Error).message || '导出失败');
    } finally {
      useExportStore.getState().setIsExporting(false);
    }
    return true;
  })();
};

export const handleCompare: CmdHandler = (parsed, input, feedback) => {
  const ids = parsed.positionals.map((p) => stripQuotes(p));
  if (ids.length === 1 && ids[0].toLowerCase() === 'clear') {
    useMessageStore.getState().removeDataMessagesByKind('model_comparison');
    feedback('success', '已清除模型对比结果。');
    return true;
  }
  if (ids.length < 2) {
    feedback('warning', 'compare 至少需要两个 run_id，或使用 compare clear。');
    return false;
  }
  const resolved = resolveCompareRuns(useProjectStore.getState().runHistory, ids);
  if (!resolved.ok) {
    feedback('warning', resolved.error);
    return false;
  }
  const { runs, family } = resolved;
  const rows = family === 'discrete'
    ? buildDiscreteComparisonRows(runs)
    : buildCausalComparisonRows(runs);
  const ds = useDatasetStore.getState().summary;
  useMessageStore.getState().addMessage({
    kind: 'data',
    command: input,
    data_result: {
      kind: 'model_comparison',
      dataset_summary: { row_count: ds?.nrows ?? 0, column_count: ds?.ncols ?? 0 },
      family,
      rows,
    },
  });
  feedback('success', '已生成模型对比表。');
  return true;
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

export const handleSave: CmdHandler = (parsed, _input, feedback) => {
  const activePath = getActivePath();
  if (!activePath) {
    feedback('warning', '请先加载数据后再保存项目');
    return false;
  }
  return (async () => {
    const ps = useProjectStore.getState();
    const ds = useDatasetStore.getState();
    const optMap = new Map(parsed.options.map((o) => [o.name, o.value]));
    let rawPath = parsed.positionals[0] ? stripQuotes(parsed.positionals[0]) : '';
    if (!rawPath) {
      try {
        const pick = await pickProjectSavePath();
        if (pick.cancelled || !pick.path) {
          feedback('warning', '已取消保存。');
          return false;
        }
        rawPath = pick.path;
        feedback('success', `等价命令：save "${rawPath}"`);
      } catch (e: unknown) {
        feedback('error', (e as Error).message || '保存路径选择失败');
        return false;
      }
    }
    const workingDirForSave = resolveProjectWorkingDirFromUserPath(rawPath);
    const now = new Date().toISOString();
    const prev = ps.manifest;
    const baseLineage = prev?.data_lineage ?? {
      source_dataset: ds.sourcePath,
      active_dataset: activePath,
      operations: [] as Record<string, unknown>[],
      notes: [] as string[],
    };
    const manifest = {
      project_id: prev?.project_id ?? ps.projectId,
      version: 1,
      created_at: prev?.created_at ?? now,
      updated_at: now,
      source_dataset: ds.sourcePath,
      active_dataset: activePath,
      saved_model_specs: prev?.saved_model_specs ?? [],
      last_run_id: ps.runHistory[0]?.run_id ?? null,
      ui_state: {
        ...(prev?.ui_state ?? {}),
        ...(optMap.has('paradigm') ? { save_paradigm: optMap.get('paradigm') } : {}),
      },
      data_lineage: {
        ...baseLineage,
        source_dataset: baseLineage.source_dataset || ds.sourcePath,
        active_dataset: baseLineage.active_dataset || activePath,
        operations: baseLineage.operations ?? [],
        notes: baseLineage.notes ?? [],
      },
    };
    setLoading(true);
    try {
      const result = await api.saveProject(manifest, workingDirForSave);
      ps.setProjectPath(result.project_path);
      ps.setProjectWorkingDir(projectRootFromManifestPath(result.project_path));
      ps.setManifest(result.manifest);
      ps.rememberProject(result.project_path);
      ps.setDirty(false);
      setError(null);
      feedback('success', '项目已保存（含数据谱系）。');
    } catch (e: unknown) {
      setError((e as Error).message || '保存项目失败');
    } finally {
      setLoading(false);
    }
    return true;
  })();
};

// ---- data viewing commands ----

export const handleDataView: CmdHandler = (parsed, input, feedback) => {
  const activePath = getActivePath();
  const verb = parsed.verb;
  feedback('success', `执行 ${verb}...（数据集：${activePath ? activePath.split('/').pop() : '未加载'}）`);
  return (async () => {
    setLoading(true);
    try {
      console.log('[handleDataView] calling runDataCommand...');
      const result = await api.runDataCommand({
        datasetPath: activePath,
        command: {
          kind: verb as 'describe' | 'browse' | 'summarize' | 'tabulate',
          variables: parsed.positionals.length > 0 ? parsed.positionals : undefined,
        },
      });
      console.log('[handleDataView] result:', result?.kind);
      const ds = useDatasetStore.getState();
      if (result.kind === 'browse') {
        ds.setBrowseContext(result.columns.map(c => c.name), result.readonly);
        useAppStore.getState().setDataFullscreen(true);
      } else {
        ds.clearBrowseContext();
        useMessageStore.getState().addMessage({ kind: 'data', command: input, data_result: result });
        feedback('success', `${verb} 完成`);
      }
      setError(null);
    } catch (e: unknown) { feedback('error', (e as Error).message || `${verb} 执行失败`); return false; }
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
        vcovType: (spec.vcov as { type?: string } | undefined)?.type || 'classical',
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
      const payload = (result as TaskResponse).result_payload as Record<string, unknown> | undefined;
      const rr = (result as TaskResponse).run_record;
      const runId = rr && isFitModelRun(rr) ? rr.run_id : (result as TaskResponse).task_id;
      if (payload && (payload as { glance?: unknown }).glance) {
        const normalized = normalizePayload(payload);
        const ms = useModelStore.getState();
        ms.applyModelSpec(spec);
        ms.setLastResult(normalized as unknown as import('../types/protocol').ModelResult);
        ms.addToHistory({
          id: crypto.randomUUID(),
          label: input,
          runId,
          modelType: spec.model_type,
          formula: spec.formula || '',
          datasetPath: activePath,
          result: normalized as unknown as import('../types/protocol').ModelResult,
          createdAt: new Date().toISOString(),
          command: input,
        });
        useMessageStore.getState().addMessage({
          kind: 'result',
          command: input,
          run_id: runId,
          result: normalized as unknown as import('../types/protocol').ModelResult,
        });
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

// ---- full preview (for DataFullscreen) ----

export async function loadFullPreview(datasetPath: string): Promise<DatasetSummary> {
  return api.inspectDataset(datasetPath);
}

// ---- router ----

/** 是否需要活动数据集（model / data-op / data-view / diagnostic 命令需要） */
export function requiresActiveDataset(verb: string): boolean {
  return !['use', 'project', 'trash', 'datahistory', 'save', 'load', 'runs', 'rerun', 'export', 'compare'].includes(verb)
    && !POSTEST_VERBS.has(verb);
}

export { isDiagnosticVerb };
export function isPostestVerb(verb: string) { return POSTEST_VERBS.has(verb); }
