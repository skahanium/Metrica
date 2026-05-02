import type { FitModelRequest, TaskResponse, DatasetSummary, TransformRequest, TransformResult } from '../types/protocol';

const DEFAULT_BASE = 'http://127.0.0.1:47821';

function createTaskId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `task-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export interface FitModelParams {
  datasetPath: string;
  formula: string;
  modelType?: 'ols' | 'panel';
  vcovType?: string;
  weightsColumn?: string;
  clusterColumn?: string;
  panelId?: string;
  panelTime?: string;
  panelMethod?: string;
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

export async function transformDataset(
  request: TransformRequest,
  baseUrl: string = DEFAULT_BASE,
  fetchImpl: typeof fetch = fetch,
): Promise<TransformResult> {
  const res = await fetchImpl(`${baseUrl}/transform`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  if (!res.ok) throw new Error(`Runtime error: ${res.status}`);
  return res.json();
}
