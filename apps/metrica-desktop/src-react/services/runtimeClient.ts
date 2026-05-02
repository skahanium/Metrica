import type { DataOp, FitModelRequest, TaskResponse, DatasetSummary, TransformRequest, TransformResult, TransformTaskResponse } from '../types/protocol';

const DEFAULT_BASE = 'http://127.0.0.1:47821';

function createTaskId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `task-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export interface FitModelParams {
  datasetPath: string;
  formula: string;
  modelType?: 'ols' | 'iv' | 'gls' | 'panel';
  vcovType?: string;
  weightsColumn?: string;
  clusterColumn?: string;
  panelId?: string;
  panelTime?: string;
  panelMethod?: string;
  instruments?: string;
  endogColumns?: string;
  workingDir?: string;
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
    workingDir = 'apps/metrica-desktop',
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
    if (instruments.trim()) modelSpec.instruments = instruments.split(',').map((v: string) => v.trim()).filter(Boolean);
    if (endogColumns.trim()) modelSpec.endog_columns = endogColumns.split(',').map((v: string) => v.trim()).filter(Boolean);
  } else if (modelType === 'gls') {
    modelSpec.vcov = { type: vcovType };
  } else {
    modelSpec.vcov = { type: vcovType };
    if (weightsColumn.trim()) modelSpec.weights = weightsColumn.trim();
    if (clusterColumn.trim()) modelSpec.cluster_column = clusterColumn.trim();
  }

  return {
    task_id: createTaskId(),
    action: 'fit_model',
    project_context: { project_id: 'alpha-demo', working_dir: workingDir },
    dataset_ref: { source: 'file', path: datasetPath, format: 'csv' },
    model_spec: modelSpec,
    options: { drop_missing: true, return_augment: true },
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
  workingDir: string = 'apps/metrica-desktop',
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<DatasetSummary> {
  const body = JSON.stringify({
    task_id: createTaskId(),
    action: 'inspect_dataset',
    project_context: { project_id: 'alpha-demo', working_dir: workingDir },
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
  return json.result_payload as DatasetSummary;
}

export interface TransformDatasetParams {
  datasetPath: string;
  operations: DataOp[];
  workingDir?: string;
  previewRows?: number;
  persistOutput?: boolean;
}

export function buildTransformRequest(params: TransformDatasetParams): TransformRequest {
  const {
    datasetPath,
    operations,
    workingDir = 'apps/metrica-desktop',
    previewRows = 10,
    persistOutput = true,
  } = params;

  return {
    task_id: createTaskId(),
    action: 'transform',
    project_context: { project_id: 'alpha-demo', working_dir: workingDir },
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
  const request = buildTransformRequest(params);
  const res = await fetchImpl(`${baseUrl}/transform`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  const json = await res.json() as TransformTaskResponse;
  if (!json.result_payload) {
    const message = json.messages?.map((m) => m.text).join('; ') || 'Transform returned no payload';
    throw new Error(message);
  }
  return json.result_payload;
}
