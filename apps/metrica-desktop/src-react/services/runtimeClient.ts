import type {
  DataOp, FitModelRequest, TaskResponse, DatasetSummary, TransformRequest, TransformResult,
  TransformTaskResponse, SaveProjectRequest, ProjectManifest, LoadProjectRequest, ListRunsRequest,
  RerunTaskRequest, RunRecord,
} from '../types/protocol';

const DEFAULT_BASE = 'http://127.0.0.1:47821';

function createTaskId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `task-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export function inferWorkingDir(path: string): string {
  if (!path.trim()) return 'apps/metrica-desktop';
  if (!path.includes('/')) return 'apps/metrica-desktop';
  return path.slice(0, path.lastIndexOf('/')) || '.';
}

export interface FitModelParams {
  datasetPath: string;
  formula: string;
  modelType?: import('../types/protocol').ModelSpec['model_type'];
  vcovType?: string;
  weightsColumn?: string;
  clusterColumn?: string;
  panelId?: string;
  panelTime?: string;
  panelMethod?: string;
  instruments?: string;
  endogColumns?: string;
  treatmentColumn?: string;
  postColumn?: string;
  eventTimeColumn?: string;
  outcomeColumn?: string;
  timeColumn?: string;
  tsVariable?: string;
  tsVariables?: string;
  orderP?: number;
  orderD?: number;
  orderQ?: number;
  seasonalP?: number;
  seasonalD?: number;
  seasonalQ?: number;
  seasonalS?: number;
  tsLags?: number;
  tsDeterministic?: string;
  strataColumn?: string;
  psuColumn?: string;
  fpcColumn?: string;
  workingDir?: string;
  projectId?: string;
}

export function buildFitModelRequest(params: FitModelParams): FitModelRequest {
  const {
    datasetPath,
    formula,
    modelType = 'ols',
    vcovType = 'classical',
    weightsColumn = '',
    clusterColumn = '',
    panelId = '',
    panelTime = '',
    panelMethod = 'fe',
    instruments = '',
    endogColumns = '',
    treatmentColumn = '',
    postColumn = '',
    eventTimeColumn = '',
    outcomeColumn = '',
    timeColumn = '',
    tsVariable = '',
    tsVariables = '',
    orderP = 1, orderD = 0, orderQ = 0,
    seasonalP = 0, seasonalD = 0, seasonalQ = 0, seasonalS = 0,
    tsLags = 2,
    tsDeterministic = 'constant',
    strataColumn = '',
    psuColumn = '',
    fpcColumn = '',
    workingDir = inferWorkingDir(datasetPath),
    projectId = 'alpha-demo',
  } = params;

  const modelSpec: FitModelRequest['model_spec'] = {
    model_type: modelType,
    formula,
  };

  if (modelType === 'panel') {
    modelSpec.panel_id = panelId;
    modelSpec.panel_time = panelTime;
    modelSpec.panel_method = panelMethod as 'fe' | 're' | 'fd' | 'between';
  } else if (modelType === 'iv') {
    modelSpec.vcov = { type: vcovType };
    if (clusterColumn.trim()) modelSpec.cluster_column = clusterColumn.trim();
    if (instruments.trim()) modelSpec.instruments = instruments.split(/[,\s]+/).filter(Boolean);
    if (endogColumns.trim()) modelSpec.endog_columns = endogColumns.split(/[,\s]+/).filter(Boolean);
  } else if (modelType === 'gls') {
    modelSpec.vcov = { type: vcovType };
  } else if (modelType === 'did' || modelType === 'event_study') {
    modelSpec.panel_id = panelId;
    modelSpec.panel_time = panelTime;
    if (treatmentColumn?.trim()) modelSpec.treated_column = treatmentColumn.trim();
    if (postColumn?.trim()) modelSpec.post_column = postColumn.trim();
    if (eventTimeColumn?.trim()) modelSpec.event_time_column = eventTimeColumn.trim();
  } else if (modelType === 'ipw' || modelType === 'psm' || modelType === 'aipw') {
    if (treatmentColumn?.trim()) modelSpec.treatment_column = treatmentColumn.trim();
    if (outcomeColumn?.trim()) modelSpec.outcome_column = outcomeColumn.trim();
  } else if (modelType === 'arima' || modelType === 'var' || modelType === 'unitroot' || modelType === 'cointegration') {
    if (timeColumn.trim()) modelSpec.time_column = timeColumn.trim();
    if (tsVariable.trim()) modelSpec.variable = tsVariable.trim();
    if (tsVariables.trim()) modelSpec.variables = tsVariables.split(',').map((v: string) => v.trim()).filter(Boolean);
    modelSpec.order = [orderP, orderD, orderQ];
    if (seasonalP > 0 || seasonalQ > 0) {
      modelSpec.seasonal_order = [seasonalP, seasonalD, seasonalQ, seasonalS];
    }
    if (tsLags > 0) modelSpec.lags = tsLags;
    if (tsDeterministic !== 'constant') modelSpec.deterministic = tsDeterministic as 'constant' | 'trend' | 'none';
  } else if (modelType === 'logit' || modelType === 'probit' || modelType === 'poisson' || modelType === 'ordered_logit' || modelType === 'multinomial_logit' || modelType === 'negbin') {
    modelSpec.vcov = { type: vcovType };
  } else if (modelType === 'survey_ols' || modelType === 'survey_logit' || modelType === 'survey_probit' || modelType === 'survey_poisson') {
    modelSpec.vcov = { type: vcovType };
    if (weightsColumn.trim()) modelSpec.weights_column = weightsColumn.trim();
    if (strataColumn.trim()) modelSpec.strata_column = strataColumn.trim();
    if (psuColumn.trim()) modelSpec.psu_column = psuColumn.trim();
    if (fpcColumn.trim()) modelSpec.fpc_column = fpcColumn.trim();
  } else {
    modelSpec.vcov = { type: vcovType };
    if (weightsColumn.trim()) modelSpec.weights = weightsColumn.trim();
    if (clusterColumn.trim()) modelSpec.cluster_column = clusterColumn.trim();
  }

  return {
    task_id: createTaskId(),
    action: 'fit_model',
    project_context: { project_id: projectId, working_dir: workingDir },
    dataset_ref: { source: 'file', path: datasetPath, format: 'csv' },
    model_spec: modelSpec,
    options: { drop_missing: true, return_augment: false },
  };
}

export async function fitModel(
  params: FitModelParams,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<TaskResponse> {
  const body = JSON.stringify(buildFitModelRequest(params));
  const res = await fetchImpl(`${baseUrl}/fit_model`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  return res.json();
}

export async function inspectDataset(
  datasetPath: string,
  workingDir: string = inferWorkingDir(datasetPath),
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
  projectId: string = 'alpha-demo',
): Promise<DatasetSummary> {
  const body = JSON.stringify({
    task_id: createTaskId(),
    action: 'inspect_dataset',
    project_context: { project_id: projectId, working_dir: workingDir },
    dataset_ref: { source: 'file', path: datasetPath, format: 'csv' },
    model_spec: { model_type: 'ols', formula: 'y ~ x1' },
    options: { drop_missing: false, return_augment: false },
  });
  const res = await fetchImpl(`${baseUrl}/inspect_dataset`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  const json = await res.json();
  const raw = json.result_payload as Record<string, unknown>;
  // 规范化：处理 Julia / Rust 两种后端格式的差异
  return {
    nrows: (raw.nrows ?? (raw.dataset_summary as Record<string, number>)?.row_count ?? 0) as number,
    ncols: (raw.ncols ?? (raw.dataset_summary as Record<string, number>)?.column_count ?? 0) as number,
    columns: (raw.columns ?? []) as DatasetSummary['columns'],
    preview: (raw.preview ?? raw.preview_rows ?? []) as DatasetSummary['preview'],
  };
}

export interface TransformDatasetParams {
  datasetPath: string;
  operations: DataOp[];
  workingDir?: string;
  previewRows?: number;
  persistOutput?: boolean;
  projectId?: string;
}

export function buildTransformRequest(params: TransformDatasetParams): TransformRequest {
  const {
    datasetPath,
    operations,
    workingDir = inferWorkingDir(datasetPath),
    previewRows = 10,
    persistOutput = true,
    projectId = 'alpha-demo',
  } = params;

  return {
    task_id: createTaskId(),
    action: 'transform',
    project_context: { project_id: projectId, working_dir: workingDir },
    dataset_ref: { source: 'file', path: datasetPath, format: 'csv' },
    operations,
    options: { preview_rows: previewRows, persist_output: persistOutput },
  };
}

export async function transformDataset(
  params: TransformDatasetParams,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<TransformResult> {
  const json = await transformTask(params, baseUrl, fetchImpl);
  if (!json.result_payload) {
    const message = json.messages?.map((m) => m.text).join('; ') || 'Transform returned no payload';
    throw new Error(message);
  }
  return json.result_payload;
}

export async function transformTask(
  params: TransformDatasetParams,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<TransformTaskResponse> {
  const request = buildTransformRequest(params);
  const res = await fetchImpl(`${baseUrl}/transform`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  return res.json();
}

export function buildSaveProjectRequest(
  manifest: ProjectManifest,
  workingDir: string,
): SaveProjectRequest {
  return {
    task_id: createTaskId(),
    action: 'save_project',
    project_context: { project_id: manifest.project_id, working_dir: workingDir },
    manifest,
  };
}

export async function saveProject(
  manifest: ProjectManifest,
  workingDir: string,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<{ project_path: string; manifest: ProjectManifest }> {
  const request = buildSaveProjectRequest(manifest, workingDir);
  const res = await fetchImpl(`${baseUrl}/save_project`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  const json = await res.json() as TaskResponse & { result_payload?: { project_path: string; manifest: ProjectManifest } };
  if (!json.result_payload) throw new Error('Save project returned no payload');
  return json.result_payload;
}

export function buildLoadProjectRequest(workingDir: string, projectId = 'alpha-demo'): LoadProjectRequest {
  return {
    task_id: createTaskId(),
    action: 'load_project',
    project_context: { project_id: projectId, working_dir: workingDir },
  };
}

export async function loadProject(
  workingDir: string,
  projectId = 'alpha-demo',
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<{ project_path: string; manifest: ProjectManifest }> {
  const res = await fetchImpl(`${baseUrl}/load_project`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(buildLoadProjectRequest(workingDir, projectId)),
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  const json = await res.json() as TaskResponse & { result_payload?: { project_path: string; manifest: ProjectManifest } };
  if (!json.result_payload) throw new Error('Load project returned no payload');
  return json.result_payload;
}

export function buildListRunsRequest(workingDir: string, projectId = 'alpha-demo'): ListRunsRequest {
  return {
    task_id: createTaskId(),
    action: 'list_runs',
    project_context: { project_id: projectId, working_dir: workingDir },
  };
}

export async function listRuns(
  workingDir: string,
  projectId = 'alpha-demo',
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<RunRecord[]> {
  const res = await fetchImpl(`${baseUrl}/list_runs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(buildListRunsRequest(workingDir, projectId)),
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  const json = await res.json() as TaskResponse & { result_payload?: { runs: RunRecord[] } };
  return json.result_payload?.runs ?? [];
}

export function buildRerunTaskRequest(runId: string, workingDir: string, projectId = 'alpha-demo'): RerunTaskRequest {
  return {
    task_id: createTaskId(),
    action: 'rerun_task',
    project_context: { project_id: projectId, working_dir: workingDir },
    run_id: runId,
  };
}

export async function rerunTask(
  runId: string,
  workingDir: string,
  projectId = 'alpha-demo',
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<TaskResponse | TransformTaskResponse> {
  const res = await fetchImpl(`${baseUrl}/rerun_task`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(buildRerunTaskRequest(runId, workingDir, projectId)),
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  return res.json();
}

export interface HealthStatus {
  service: string;
  status: 'ready' | 'degraded';
  julia_healthy: boolean;
  restart_count: number;
  supported_actions: string[];
}

export async function checkHealth(
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<HealthStatus> {
  const res = await fetchImpl(`${baseUrl}/health`);
  if (!res.ok) throw new Error(`Health check error: ${res.status}`);
  return res.json();
}

export interface ExportReportParams {
  runId: string;
  format: 'markdown' | 'csv_tidy' | 'csv_glance' | 'csv_diagnostics';
  workingDir?: string;
  projectId?: string;
}

export function buildExportReportRequest(
  params: ExportReportParams,
): { task_id: string; action: string; project_context: { project_id: string; working_dir: string }; run_id: string; format: string } {
  const { runId, format, workingDir = '.', projectId = 'alpha-demo' } = params;
  return {
    task_id: createTaskId(),
    action: 'export_report',
    project_context: { project_id: projectId, working_dir: workingDir },
    run_id: runId,
    format,
  };
}

export async function exportReport(
  params: ExportReportParams,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<{ content: string; format: string; run_id: string }> {
  const request = buildExportReportRequest(params);
  const res = await fetchImpl(`${baseUrl}/export_report`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  const json = await res.json() as TaskResponse & { result_payload?: { content: string; format: string; run_id: string } };
  if (!json.result_payload) throw new Error('Export returned no payload');
  return json.result_payload;
}
