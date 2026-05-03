// ============================================================
// 共享类型定义 — 协议层单一数据源
// Julia / Rust / TypeScript 三层通过此文件约定字段名
// ============================================================

// ---- 基础消息类型 ----

export interface Warning {
  title: string;
  detail: string;
}

export interface Message {
  level: 'info' | 'warning' | 'error';
  code: string;
  text: string;
  hint?: string;
}

// ---- 诊断类型（OLS） ----

export interface VifEntry {
  name: string;
  vif: number;
}

export interface DiagnosticResult {
  statistic: number | null;
  pvalue: number | null;
  dof?: number | null;
  method?: string;
  note?: string;
  available?: boolean;
}

export interface ResetDiagnostic extends DiagnosticResult {
  df_num?: number;
  df_den?: number;
}

export interface JarqueBeraDiagnostic extends DiagnosticResult {
  skewness?: number;
  kurtosis?: number;
}

export interface OLSDiagnostics {
  vif?: VifEntry[];
  breusch_pagan?: DiagnosticResult;
  white_test?: DiagnosticResult;
  durbin_watson?: DiagnosticResult;
  breusch_godfrey?: DiagnosticResult;
  reset_test?: ResetDiagnostic;
  jarque_bera?: JarqueBeraDiagnostic;
}

// ---- 诊断类型（Panel） ----

export interface PanelDiagnostics {
  hausman?: DiagnosticResult;
  fixed_effect_f?: DiagnosticResult;
  breusch_pagan_lm?: DiagnosticResult;
}

// ---- 模型结果 ----

export interface GlanceResult {
  model: string;
  nobs: number;
  dof: number;
  metrics: Record<string, number>;
}

export interface TidyRow {
  term: string;
  estimate: number;
  std_error: number;
  statistic: number;
  p_value: number;
  ci_lower?: number;
  ci_upper?: number;
}

export interface AugmentRow {
  fitted: number;
  residual: number;
  std_residual?: number;
  leverage?: number;
  cooks_d?: number;
}

export interface ModelResult {
  glance: GlanceResult;
  tidy: TidyRow[];
  diagnostics: OLSDiagnostics | PanelDiagnostics;
  augment_preview?: AugmentRow[];
  warnings: Warning[];
  messages?: Message[];
  summary_text?: string;
  vcov_label?: string;
}

// ---- 数据摘要 ----

export interface ColumnSummary {
  name: string;
  type?: string;
  missing?: number;
  inferred_type?: string;
  missing_count?: number;
}

export interface DatasetSummary {
  nrows: number;
  ncols: number;
  columns: ColumnSummary[];
  preview: Record<string, unknown>[];
}

// ---- 运行时请求/响应 ----

export interface ModelSpec {
  model_type: 'ols' | 'iv' | 'gls' | 'panel';
  formula: string;
  vcov?: { type: string };
  weights?: string;
  cluster_column?: string;
  panel_id?: string;
  panel_time?: string;
  panel_method?: 'fe' | 're' | 'fd' | 'between' | 'hdfde' | 'cre' | 'panel_iv';
  instruments?: string[];
  endog_columns?: string[];
  omega_spec?: string;
}

export interface FitModelRequest {
  task_id: string;
  action: 'fit_model';
  project_context: { project_id: string; working_dir: string };
  dataset_ref: { source: string; path: string; format: string };
  model_spec: ModelSpec;
  options: { drop_missing: boolean; return_augment: boolean };
}

export interface TaskResponse {
  task_id: string;
  status: 'success' | 'error';
  messages: Message[];
  artifacts?: string[];
  run_record?: RunRecord;
  result_payload?: ModelResult;
}

export interface DataLineage {
  source_dataset: string;
  active_dataset: string;
  operations: Record<string, unknown>[];
  row_count_before?: number;
  row_count_after?: number;
  notes: string[];
}

export interface ProjectManifest {
  project_id: string;
  version: number;
  created_at: string;
  updated_at: string;
  source_dataset: string;
  active_dataset: string;
  saved_model_specs: ModelSpec[];
  last_run_id?: string | null;
  ui_state: Record<string, unknown>;
  data_lineage?: DataLineage | null;
}

// RunRecord 使用 discriminated union：action 字段收窄 result_summary 和 model_spec 类型。
// 消费方通过 `run.action === 'fit_model'` 即可获取正确的类型收窄，无需 `as never`。

interface RunRecordBase {
  run_id: string;
  started_at: string;
  finished_at: string;
  status: 'success' | 'error' | string;
  dataset_ref: { source: string; path: string; format: string };
  warnings: Array<Record<string, unknown>>;
  messages: Message[];
  artifacts: string[];
}

export interface FitModelRunRecord extends RunRecordBase {
  action: 'fit_model';
  result_summary?: ModelResult | null;
  model_spec?: ModelSpec | null;
  operations?: null;
}

export interface InspectRunRecord extends RunRecordBase {
  action: 'inspect_dataset';
  result_summary?: DatasetSummary | null;
  model_spec?: null;
  operations?: null;
}

export interface TransformRunRecord extends RunRecordBase {
  action: 'transform';
  result_summary?: TransformResult | null;
  model_spec?: null;
  operations?: DataOp[] | null;
}

export type RunRecord = FitModelRunRecord | InspectRunRecord | TransformRunRecord;

/** Type guard: 收窄 RunRecord 为 fit_model 变体。 */
export function isFitModelRun(run: RunRecord): run is FitModelRunRecord {
  return run.action === 'fit_model';
}

// ---- 数据操作类型（Track B 用） ----

export type DataOpKind =
  | 'filter' | 'generate' | 'replace' | 'rename' | 'drop' | 'keep'
  | 'sort' | 'merge' | 'reshape_long' | 'reshape_wide' | 'collapse';

export interface DataOp {
  op: DataOpKind;
  args: Record<string, unknown>;
}

export interface TransformRequest {
  task_id: string;
  action: 'transform';
  project_context: { project_id: string; working_dir: string };
  dataset_ref: { source: string; path: string; format: string };
  operations: DataOp[];
  options: { preview_rows: number; persist_output: boolean };
}

export interface TransformResult {
  operation: string;
  status: 'ok' | 'error';
  result?: {
    nrows: number;
    ncols: number;
    notes: string;
    dataset_path?: string;
  };
  preview?: { columns: string[]; rows: Record<string, unknown>[] };
  warnings: Warning[];
  error?: { op_index: number; message: string };
  operations?: TransformResult[];
}

export interface TransformTaskResponse {
  task_id: string;
  status: 'success' | 'error';
  messages: Message[];
  artifacts?: string[];
  run_record?: RunRecord;
  result_payload?: TransformResult;
}

export interface SaveProjectRequest {
  task_id: string;
  action: 'save_project';
  project_context: { project_id: string; working_dir: string };
  manifest: ProjectManifest;
}

export interface LoadProjectRequest {
  task_id: string;
  action: 'load_project';
  project_context: { project_id: string; working_dir: string };
}

export interface ListRunsRequest {
  task_id: string;
  action: 'list_runs';
  project_context: { project_id: string; working_dir: string };
}

export interface RerunTaskRequest {
  task_id: string;
  action: 'rerun_task';
  project_context: { project_id: string; working_dir: string };
  run_id: string;
}
