// ============================================================
// 共享类型定义 — 协议层单一数据源
// Julia 端字段名为 name/stderror/pvalue，前端统一规范化为 term/std_error/p_value
// normalizeTidyRow() 在 runtimeClient 或数据处理入口处执行转换
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

// ---- 诊断类型（Discrete / GLM） ----

export interface DiscreteDiagnostics {
  converged?: boolean;
  iterations?: number;
  pseudo_r2?: number;
  loglikelihood?: number;
  aic?: number;
  bic?: number;
  deviance?: number;
}

export interface OddsRatioEntry {
  term: string;
  odds_ratio: number;
  ci_lower: number;
  ci_upper: number;
}

export interface IRREntry {
  term: string;
  irr: number;
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
  estimate: number | null;
  std_error: number | null;
  statistic: number | null;
  p_value: number | null;
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
  diagnostics: OLSDiagnostics | PanelDiagnostics | DiscreteDiagnostics;
  odds_ratios?: OddsRatioEntry[];
  incidence_rate_ratios?: IRREntry[];
  augment_preview?: AugmentRow[];
  warnings: Warning[];
  messages?: Message[];
  summary_text?: string;
  vcov_label?: string;
  loglikelihood?: number;
  iterations?: number;
  converged?: boolean;
  // S4b Causal 字段
  treat_effect?: number;
  treat_effect_se?: number;
  treat_effect_pvalue?: number;
  n_treated?: number;
  n_control?: number;
  period_coefficients?: number[];
  period_stderrors?: number[];
  period_labels?: string[];
  pre_trend_pvalue?: number;
  parallel_trends_supported?: boolean;
  ate?: number;
  att?: number;
  atu?: number;
  att_se?: number;
  ate_se?: number;
  n_matched?: number;
  // S4c: TimeSeries 字段
  adf_statistic?: number;
  adf_pvalue?: number;
  pp_statistic?: number;
  pp_pvalue?: number;
  kpss_statistic?: number;
  kpss_pvalue?: number;
  unitroot_results?: UnitRootTestResult[];
  forecast?: ForecastResult;
  impulse_response?: number[][][];
  variance_decomposition?: number[][][];
  granger_causality?: GrangerCausalityResult;
  cointegrating_vector?: number[];
  n_cointegrating_relations?: number;
  eigenvalues?: number[];
  trace_stats?: number[];
  max_eigen_stats?: number[];
  acf_values?: number[];
  pacf_values?: number[];
  // S4d: Survey 字段
  design_effects?: DEFFEntry[];
  strata_summary?: StrataEntry[];
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

// ---- 变量元数据 ----

export interface VariableMetadata {
  current_name: string;
  original_name: string;
  label: string;
  dtype?: string;
  format?: string;
  missing_count?: number;
  unique_count?: number;
  source_state_id?: string;
}

// ---- 数据历史节点 ----

export interface DataHistoryNode {
  state_id: string;
  source_state_id: string | null;
  op_type: string;
  op_args: Record<string, unknown>;
  active_data_path: string;
  row_count_before: number;
  row_count_after: number;
  col_count_before: number;
  col_count_after: number;
  notes: string[];
  warnings: string[];
  created_at: string;
}

// ---- 数据查看命令 ----

export type DataCommandKind = 'describe' | 'browse' | 'summarize' | 'tabulate';

export interface DataCommandSummary {
  row_count: number;
  column_count: number;
}

export interface DescribeVariable {
  name: string;
  dtype: string;
  missing_count: number;
  unique_count: number;
  label: string;
  inferred_type?: string;
  non_missing_count?: number;
}

export interface SummarizeVariable {
  name: string;
  dtype: string;
  obs: number;
  mean: number | null;
  std_dev: number | null;
  min: number | null;
  max: number | null;
  p25: number | null;
  p50: number | null;
  p75: number | null;
  inferred_type?: string;
}

export interface TabulateRow {
  value: string;
  count: number;
  pct: number;
  cum_pct: number;
}

export interface DescribeResult {
  kind: 'describe';
  dataset_summary: DataCommandSummary;
  variables: DescribeVariable[];
}

export interface SummarizeResult {
  kind: 'summarize';
  dataset_summary: DataCommandSummary;
  variables: SummarizeVariable[];
}

export interface TabulateResult {
  kind: 'tabulate';
  dataset_summary: DataCommandSummary;
  variable: string;
  total: number;
  missing_count: number;
  truncated: boolean;
  rows: TabulateRow[];
}

export interface BrowseResult {
  kind: 'browse';
  readonly: boolean;
  dataset_summary: DataCommandSummary;
  columns: DescribeVariable[];
}

export type DataCommandResult = DescribeResult | SummarizeResult | TabulateResult | BrowseResult;
export type DataResult = DescribeResult | SummarizeResult | TabulateResult;

export interface DataCommand {
  kind: DataCommandKind;
  variables?: string[];
  limit?: number;
}

export interface MessageItem {
  id: string;
  kind: 'command' | 'result' | 'transform' | 'data';
  command?: string;
  result?: ModelResult;
  transform_result?: TransformResult;
  data_result?: DataResult;
  created_at: string;
  is_deleted: boolean;
  deleted_at?: string;
}

export type SelectionMode = 'none' | 'single' | 'multi' | 'all';

// ---- 保存范式 ----

export type SaveParadigm = 'commands_only' | 'commands_and_results';

// ---- 运行时请求/响应 ----

export interface ModelSpec {
  model_type: 'ols' | 'iv' | 'gls' | 'panel' | 'logit' | 'probit' | 'poisson' | 'ordered_logit' | 'multinomial_logit' | 'negbin' | 'did' | 'event_study' | 'ipw' | 'psm' | 'aipw' | 'arima' | 'var' | 'unitroot' | 'cointegration' | 'survey_ols' | 'survey_logit' | 'survey_probit' | 'survey_poisson';
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
  treatment_column?: string;
  treated_column?: string;
  post_column?: string;
  event_time_column?: string;
  outcome_column?: string;
  // S4c: TimeSeries 字段
  time_column?: string;
  variable?: string;
  variables?: string[];
  order?: [number, number, number];
  seasonal_order?: [number, number, number, number];
  ts_method?: 'mle' | 'css' | 'engle_granger' | 'johansen';
  lags?: number;
  deterministic?: 'constant' | 'trend' | 'none';
  // S4d: Survey 字段
  weights_column?: string;
  strata_column?: string;
  psu_column?: string;
  fpc_column?: string;
}

export interface FitModelRequest {
  task_id: string;
  action: 'fit_model' | 'inspect_dataset';
  project_context: { project_id: string; working_dir: string };
  dataset_ref: { source: string; path: string; format: string };
  model_spec: ModelSpec;
  options: { drop_missing: boolean; return_augment: boolean; preview_rows?: number };
}

export interface DataCommandRequest {
  task_id: string;
  action: 'query_dataset';
  project_context: { project_id: string; working_dir: string };
  dataset_ref: { source: string; path: string; format: string };
  command: DataCommand;
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
  | 'sort' | 'merge' | 'reshape_long' | 'reshape_wide' | 'collapse'
  | 'impute_missing';

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

// ---- S4c: 时间序列类型 ----

export interface UnitRootTestResult {
  test_name: string;
  test_statistic: number;
  p_value: number;
  lags_used: number;
  critical_values: Record<number, number>;
  conclusion: 'reject' | 'fail_to_reject';
}

export interface ForecastResult {
  point_forecast: number[];
  lower_bound: number[];
  upper_bound: number[];
  confidence_level: number;
  forecast_origin: number;
  steps: number;
}

export interface GrangerCausalityResult {
  f_stat: number;
  p_value: number;
  conclusion: 'reject' | 'fail_to_reject';
}

// ---- S4d: 调查模型类型 ----

export interface DEFFEntry {
  term: string;
  deff: number;
  n_eff: number;
  srs_se: number;
  survey_se: number;
}

export interface StrataEntry {
  stratum: string;
  n: number;
  sum_weights: number;
  mean_weight: number;
  min_weight: number;
  max_weight: number;
}

export interface TimeSeriesModelParams {
  time_column: string;
  variable?: string;
  variables?: string[];
  order?: [number, number, number];
  seasonal_order?: [number, number, number, number];
  method?: 'mle' | 'css' | 'engle_granger' | 'johansen';
  lags?: number;
  deterministic?: 'constant' | 'trend' | 'none';
}
