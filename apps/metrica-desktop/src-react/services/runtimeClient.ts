import type {
  DataCommandRequest, DataCommandResult,
  DataOp, FitModelRequest, TaskResponse, DatasetSummary, TransformRequest, TransformResult,
  TransformTaskResponse, SaveProjectRequest, ProjectManifest, LoadProjectRequest, ListRunsRequest,
  RerunTaskRequest, RunRecord, DiagnosticSpec,
} from '../types/protocol';

const DEFAULT_BASE = 'http://127.0.0.1:47821';
const FULL_DATA_PREVIEW_ROWS = 1_000_000;

function isDataCommandResult(payload: unknown): payload is DataCommandResult {
  if (!payload || typeof payload !== 'object') return false;
  const kind = (payload as { kind?: unknown }).kind;
  return kind === 'describe' || kind === 'summarize' || kind === 'tabulate' || kind === 'browse';
}

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
  gmmWeight?: string;
  instrumentLags?: [number, number];
  dpgmmStyle?: string;
  collapseInstruments?: boolean;
  treatmentColumn?: string;
  postColumn?: string;
  eventTimeColumn?: string;
  outcomeColumn?: string;
  propensityFormula?: string;
  outcomeFormula?: string;
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
  tsMethod?: string;
  strataColumn?: string;
  psuColumn?: string;
  fpcColumn?: string;
  workingDir?: string;
  projectId?: string;
  /** S5.3 系统方程 */
  equations?: string[];
  systemEndogenous?: string[][];
  systemInstruments?: string[][];
  surMaxIter?: number;
  surTol?: number;
  /** 仅 `quantile` */
  quantileTau?: number;
  /** 仅 `nls` */
  nlsFamily?: string;
  nlsStart?: number[];
  nlsMaxIter?: number;
  nlsTol?: number;
  /** 仅 `threshold` */
  thresholdVariable?: string;
  thresholdGrid?: number[];
  thresholdTrimFrac?: number;
  archOrder?: number;
  garchP?: number;
  garchQ?: number;
  garchMaxIter?: number;
  garchTol?: number;
  /** 空间模型：边表 CSV 与主数据 ID 对齐字段 */
  spatialWeightsPath?: string;
  spatialIdColumn?: string;
  spatialRowStandardize?: boolean;
  spatialCoordColumns?: string[];
  spatialDistance?: string;
  gwrKernel?: string;
  gwrBandwidth?: number;
  gwrBandwidthSelection?: string;
  gwrAdaptive?: boolean;
  gtwrTimeColumn?: string;
  gtwrTimeScale?: number | string;
  /** 仅 `duration_cox` */
  durationTimeColumn?: string;
  durationEventColumn?: string;
}

function splitList(raw: string): string[] {
  return raw.split(/[,\s]+/).filter(Boolean);
}

function buildFamilyParams(p: FitModelParams): Record<string, unknown> {
  const modelType = p.modelType ?? 'ols';
  const params: Record<string, unknown> = {};
  const {
    panelId = '',
    panelTime = '',
    panelMethod = 'fe',
    instruments = '',
    endogColumns = '',
    gmmWeight = '',
    instrumentLags,
    dpgmmStyle = '',
    collapseInstruments,
    treatmentColumn = '',
    postColumn = '',
    eventTimeColumn = '',
    outcomeColumn = '',
    propensityFormula = '',
    outcomeFormula = '',
    timeColumn = '',
    tsVariable = '',
    tsVariables = '',
    orderP = 1,
    orderD = 0,
    orderQ = 0,
    seasonalP = 0,
    seasonalD = 0,
    seasonalQ = 0,
    seasonalS = 0,
    tsLags = 2,
    tsDeterministic = 'constant',
    tsMethod = '',
    strataColumn = '',
    psuColumn = '',
    fpcColumn = '',
    equations,
    systemEndogenous,
    systemInstruments,
    surMaxIter,
    surTol,
    quantileTau,
    nlsFamily,
    nlsStart,
    nlsMaxIter,
    nlsTol,
    thresholdVariable,
    thresholdGrid,
    thresholdTrimFrac,
    archOrder,
    garchP,
    garchQ,
    garchMaxIter,
    garchTol,
    spatialWeightsPath,
    spatialIdColumn,
    spatialRowStandardize,
    spatialCoordColumns,
    spatialDistance,
    gwrKernel,
    gwrBandwidth,
    gwrBandwidthSelection,
    gwrAdaptive,
    gtwrTimeColumn,
    gtwrTimeScale,
    durationTimeColumn,
    durationEventColumn,
  } = p;

  if (modelType === 'panel' || modelType === 'panel_iv') {
    if (panelId.trim()) params.panel_id = panelId.trim();
    if (panelTime.trim()) params.panel_time = panelTime.trim();
    if (modelType === 'panel' && panelMethod.trim()) {
      params.panel_method = panelMethod.trim();
    }
    if (modelType === 'panel_iv') {
      if (instruments.trim()) params.instruments = splitList(instruments);
      if (endogColumns.trim()) params.endog_columns = splitList(endogColumns);
    }
  } else if (modelType === 'iv') {
    if (instruments.trim()) params.instruments = splitList(instruments);
    if (endogColumns.trim()) params.endog_columns = splitList(endogColumns);
  } else if (modelType === 'gmm_linear') {
    if (instruments.trim()) params.instruments = splitList(instruments);
    if (endogColumns.trim()) params.endog_columns = splitList(endogColumns);
    if (gmmWeight.trim()) params.gmm_weight = gmmWeight.trim();
  } else if (modelType === 'dynamic_panel_gmm') {
    if (panelId.trim()) params.panel_id = panelId.trim();
    if (panelTime.trim()) params.panel_time = panelTime.trim();
    params.instrument_lags = instrumentLags ?? [2, 4];
    if (gmmWeight.trim()) params.gmm_weight = gmmWeight.trim();
    if (dpgmmStyle.trim()) params.dpgmm_style = dpgmmStyle.trim();
    if (typeof collapseInstruments === 'boolean') params.collapse_instruments = collapseInstruments;
  } else if (modelType === 'did' || modelType === 'event_study') {
    if (panelId.trim()) params.panel_id = panelId.trim();
    if (panelTime.trim()) params.panel_time = panelTime.trim();
    if (treatmentColumn?.trim()) params.treated_column = treatmentColumn.trim();
    if (postColumn?.trim()) params.post_column = postColumn.trim();
    if (eventTimeColumn?.trim()) params.event_time_column = eventTimeColumn.trim();
  } else if (modelType === 'ipw' || modelType === 'psm' || modelType === 'aipw') {
    if (treatmentColumn?.trim()) params.treatment_column = treatmentColumn.trim();
    if (outcomeColumn?.trim()) params.outcome_column = outcomeColumn.trim();
    if (propensityFormula?.trim()) params.propensity_formula = propensityFormula.trim();
    if (outcomeFormula?.trim()) params.outcome_formula = outcomeFormula.trim();
  } else if (
    modelType === 'arima' ||
    modelType === 'var' ||
    modelType === 'unitroot' ||
    modelType === 'cointegration' ||
    modelType === 'arch' ||
    modelType === 'garch' ||
    modelType === 'gjr_garch' ||
    modelType === 'egarch'
  ) {
    if (timeColumn.trim()) params.time_column = timeColumn.trim();
    if (tsVariable.trim()) params.variable = tsVariable.trim();
    if (tsVariables.trim()) {
      params.variables = tsVariables.split(',').map((v) => v.trim()).filter(Boolean);
    }
    if (modelType === 'arima') {
      params.order = [orderP, orderD, orderQ];
      if (seasonalP > 0 || seasonalQ > 0) {
        params.seasonal_order = [seasonalP, seasonalD, seasonalQ, seasonalS];
      }
    }
    if (modelType !== 'arch' && modelType !== 'garch' && tsLags > 0) params.lags = tsLags;
    if (modelType !== 'arch' && modelType !== 'garch' && tsDeterministic !== 'constant') {
      params.deterministic = tsDeterministic;
    }
    if (modelType !== 'arch' && modelType !== 'garch' && tsMethod.trim()) {
      params.ts_method = tsMethod.trim();
    }
    if (modelType === 'arch' && typeof archOrder === 'number' && Number.isFinite(archOrder)) {
      params.arch_order = archOrder;
    }
    if (modelType === 'garch') {
      if (typeof garchP === 'number' && Number.isFinite(garchP)) params.garch_p = garchP;
      if (typeof garchQ === 'number' && Number.isFinite(garchQ)) params.garch_q = garchQ;
    }
    if (
      (modelType === 'arch' || modelType === 'garch') &&
      typeof garchMaxIter === 'number' &&
      Number.isFinite(garchMaxIter)
    ) {
      params.garch_max_iter = garchMaxIter;
    }
    if (
      (modelType === 'arch' || modelType === 'garch') &&
      typeof garchTol === 'number' &&
      Number.isFinite(garchTol)
    ) {
      params.garch_tol = garchTol;
    }
  } else if (
    modelType === 'survey_ols' ||
    modelType === 'survey_logit' ||
    modelType === 'survey_probit' ||
    modelType === 'survey_poisson'
  ) {
    if (p.weightsColumn?.trim()) params.weights_column = p.weightsColumn.trim();
    if (strataColumn.trim()) params.strata_column = strataColumn.trim();
    if (psuColumn.trim()) params.psu_column = psuColumn.trim();
    if (fpcColumn.trim()) params.fpc_column = fpcColumn.trim();
  } else if (modelType === 'sur' || modelType === 'system_2sls' || modelType === 'system_3sls') {
    if (equations && equations.length > 0) params.equations = equations;
    if (modelType !== 'sur') {
      if (systemEndogenous && systemEndogenous.length > 0) {
        params.system_endogenous = systemEndogenous;
      }
      if (systemInstruments && systemInstruments.length > 0) {
        params.system_instruments = systemInstruments;
      }
    }
    if (modelType === 'sur') {
      if (typeof surMaxIter === 'number' && Number.isFinite(surMaxIter)) params.sur_max_iter = surMaxIter;
      if (typeof surTol === 'number' && Number.isFinite(surTol)) params.sur_tol = surTol;
    }
  } else if (modelType === 'quantile') {
    params.quantile_tau =
      typeof quantileTau === 'number' && Number.isFinite(quantileTau) ? quantileTau : 0.5;
  } else if (modelType === 'nls') {
    if (nlsFamily?.trim()) params.nls_family = nlsFamily.trim();
    if (nlsStart && nlsStart.length === 3) params.nls_start = nlsStart;
    if (typeof nlsMaxIter === 'number' && Number.isFinite(nlsMaxIter)) params.nls_max_iter = nlsMaxIter;
    if (typeof nlsTol === 'number' && Number.isFinite(nlsTol)) params.nls_tol = nlsTol;
  } else if (modelType === 'threshold') {
    if (thresholdVariable?.trim()) params.threshold_variable = thresholdVariable.trim();
    if (thresholdGrid && thresholdGrid.length >= 2) params.threshold_grid = thresholdGrid;
    if (typeof thresholdTrimFrac === 'number' && Number.isFinite(thresholdTrimFrac)) {
      params.threshold_trim_frac = thresholdTrimFrac;
    }
  } else if (
    modelType === 'spatial_lag' ||
    modelType === 'spatial_error' ||
    modelType === 'spatial_slx' ||
    modelType === 'spatial_sdm' ||
    modelType === 'spatial_sdem' ||
    modelType === 'spatial_sac' ||
    modelType === 'spatial_probit'
  ) {
    const sw = spatialWeightsPath?.trim();
    if (sw) params.spatial_weights_path = sw;
    const sid = spatialIdColumn?.trim();
    if (sid) params.spatial_id_column = sid;
    if (typeof spatialRowStandardize === 'boolean') {
      params.spatial_row_standardize = spatialRowStandardize;
    }
  } else if (modelType === 'spatial_gwr' || modelType === 'spatial_gtwr') {
    if (spatialCoordColumns) params.spatial_coord_columns = spatialCoordColumns;
    if (spatialDistance) params.spatial_distance = spatialDistance;
    if (gwrKernel) params.gwr_kernel = gwrKernel;
    if (gwrBandwidth !== undefined) params.gwr_bandwidth = gwrBandwidth;
    if (gwrBandwidthSelection) params.gwr_bandwidth_selection = gwrBandwidthSelection;
    if (typeof gwrAdaptive === 'boolean') params.gwr_adaptive = gwrAdaptive;
    if (modelType === 'spatial_gtwr') {
      if (gtwrTimeColumn) params.gtwr_time_column = gtwrTimeColumn;
      if (gtwrTimeScale !== undefined) params.gtwr_time_scale = gtwrTimeScale;
    }
  } else if (
    modelType === 'duration_cox' ||
    modelType === 'aft_weibull' ||
    modelType === 'aft_exponential' ||
    modelType === 'aft_lognormal' ||
    modelType === 'aft_loglogistic'
  ) {
    const tcol = durationTimeColumn?.trim();
    const ecol = durationEventColumn?.trim();
    if (tcol) params.duration_time_column = tcol;
    if (ecol) params.duration_event_column = ecol;
  }

  return params;
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
    gmmWeight = '',
    instrumentLags,
    dpgmmStyle = '',
    collapseInstruments,
    treatmentColumn = '',
    postColumn = '',
    eventTimeColumn = '',
    outcomeColumn = '',
    propensityFormula = '',
    outcomeFormula = '',
    timeColumn = '',
    tsVariable = '',
    tsVariables = '',
    orderP = 1, orderD = 0, orderQ = 0,
    seasonalP = 0, seasonalD = 0, seasonalQ = 0, seasonalS = 0,
    tsLags = 2,
    tsDeterministic = 'constant',
    tsMethod = '',
    strataColumn = '',
    psuColumn = '',
    fpcColumn = '',
    workingDir = inferWorkingDir(datasetPath),
    projectId = 'alpha-demo',
    equations,
    systemEndogenous,
    systemInstruments,
    surMaxIter,
    surTol,
    quantileTau,
    nlsFamily,
    nlsStart,
    nlsMaxIter,
    nlsTol,
    thresholdVariable,
    thresholdGrid,
    thresholdTrimFrac,
    archOrder,
    garchP,
    garchQ,
    garchMaxIter,
    garchTol,
    spatialWeightsPath,
    spatialIdColumn,
    spatialRowStandardize,
    spatialCoordColumns,
    spatialDistance,
    gwrKernel,
    gwrBandwidth,
    gwrBandwidthSelection,
    gwrAdaptive,
    gtwrTimeColumn,
    gtwrTimeScale,
    durationTimeColumn,
    durationEventColumn,
  } = params;

  const needsVcov =
    modelType === 'iv' ||
    modelType === 'panel_iv' ||
    modelType === 'gls' ||
    modelType === 'spatial_lag' ||
    modelType === 'spatial_sdm' ||
    [
      'logit',
      'probit',
      'poisson',
      'ordered_logit',
      'multinomial_logit',
      'negbin',
      'survey_ols',
      'survey_logit',
      'survey_probit',
      'survey_poisson',
    ].includes(modelType) ||
    ![
      'panel',
      'panel_iv',
      'dynamic_panel_gmm',
      'did',
      'event_study',
      'ipw',
      'psm',
      'aipw',
      'arima',
      'var',
      'unitroot',
      'cointegration',
      'arch',
      'garch',
      'gjr_garch',
      'egarch',
      'sur',
      'system_2sls',
      'system_3sls',
      'quantile',
      'nls',
      'threshold',
      'spatial_lag',
      'spatial_error',
      'spatial_slx',
      'spatial_sdm',
      'spatial_sdem',
      'spatial_sac',
      'spatial_probit',
      'spatial_gwr',
      'spatial_gtwr',
      'duration_cox',
      'aft_weibull',
      'aft_exponential',
      'aft_lognormal',
      'aft_loglogistic',
    ].includes(modelType);

  const modelSpec: FitModelRequest['model_spec'] = {
    model_type: modelType,
    formula,
    params: buildFamilyParams(params),
  };

  if (needsVcov) modelSpec.vcov = { type: vcovType };
  if (weightsColumn.trim()) modelSpec.weights = weightsColumn.trim();
  if (clusterColumn.trim()) modelSpec.cluster_column = clusterColumn.trim();

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
    options: { drop_missing: false, return_augment: false, preview_rows: FULL_DATA_PREVIEW_ROWS },
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

export interface RunDataCommandParams {
  datasetPath: string;
  command: import('../types/protocol').DataCommand;
  workingDir?: string;
  projectId?: string;
}

export function buildDataCommandRequest(params: RunDataCommandParams): DataCommandRequest {
  const {
    datasetPath,
    command,
    workingDir = inferWorkingDir(datasetPath),
    projectId = 'alpha-demo',
  } = params;

  return {
    task_id: createTaskId(),
    action: 'query_dataset',
    project_context: { project_id: projectId, working_dir: workingDir },
    dataset_ref: { source: 'file', path: datasetPath, format: 'csv' },
    command,
  };
}

export async function runDataCommand(
  params: RunDataCommandParams,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<DataCommandResult> {
  const body = JSON.stringify(buildDataCommandRequest(params));
  const res = await fetchImpl(`${baseUrl}/query_dataset`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  const json = await res.json();
  const messages = Array.isArray(json.messages) ? json.messages : [];
  if (json.status !== 'success') {
    const text = messages.map((message: { text?: string }) => message.text).filter(Boolean).join('; ');
    throw new Error(text || '数据命令执行失败');
  }
  if (!isDataCommandResult(json.result_payload)) {
    throw new Error('运行时返回了旧版模型结果；describe、browse、summarize、tabulate 必须走独立数据命令通道。请重启桌面端与 runtime 后重试。');
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

// ---- diagnostic ----

export interface RunDiagnosticParams {
  datasetPath: string;
  formula: string;
  modelType?: string;
  diagnostic: DiagnosticSpec;
  workingDir?: string;
  projectId?: string;
}

export function buildDiagnosticRequest(params: RunDiagnosticParams) {
  const {
    datasetPath, formula, modelType = 'ols', diagnostic,
    workingDir = inferWorkingDir(datasetPath), projectId = 'alpha-demo',
  } = params;

  return {
    task_id: createTaskId(),
    action: 'run_diagnostic',
    project_context: { project_id: projectId, working_dir: workingDir },
    dataset_ref: { source: 'file', path: datasetPath, format: 'csv' },
    model_spec: { model_type: modelType, formula },
    diagnostic,
  };
}

export interface DiagnosticResponse {
  test: string;
  statistic: number | null;
  pvalue: number | null;
  dof?: number | null;
  df_num?: number | null;
  df_den?: number | null;
  skewness?: number | null;
  kurtosis?: number | null;
  vif?: Array<{ name: string; vif: number }> | null;
  interpretation?: string;
}

export async function runDiagnostic(
  params: RunDiagnosticParams,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<DiagnosticResponse> {
  const body = JSON.stringify(buildDiagnosticRequest(params));
  const res = await fetchImpl(`${baseUrl}/run_diagnostic`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  const json = await res.json() as TaskResponse & { result_payload?: DiagnosticResponse };
  if (!json.result_payload) {
    const text = json.messages?.map(m => m.text).filter(Boolean).join('; ') || '诊断命令执行失败';
    throw new Error(text);
  }
  return json.result_payload;
}
