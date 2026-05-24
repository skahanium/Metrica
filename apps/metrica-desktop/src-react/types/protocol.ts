// ============================================================
// 共享类型定义 — 协议层单一数据源
// Julia 端字段名为 name/stderror/pvalue，前端统一规范化为 term/std_error/p_value
// normalizeTidyRow() 在 runtimeClient 或数据处理入口处执行转换
// ============================================================

// ---- CLI 反馈类型 ----

export interface CliFeedback {
  level: 'error' | 'warning' | 'success';
  message: string;
}

// ---- 基础消息类型 ----

export interface Warning {
  title: string;
  detail: string;
  code?: string;
  hint?: string;
  severity?: string;
}

export interface Message {
  level: 'info' | 'warning' | 'error';
  code: string;
  text: string;
  hint?: string;
}

// ---- 诊断类型（OLS） ----

export interface DiagnosticSpec {
  test: 'bp' | 'bg' | 'reset' | 'jb' | 'dw' | 'white' | 'vif';
  lags?: number;
}

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

/** S5.3：系统方程在 `result_payload.diagnostics` 中的扩展键 */
export interface SystemEquationsDiagnostics {
  system_method?: string;
  sigma_residual?: { dim?: number; matrix?: number[][] };
  equation_correlation?: { dim?: number; matrix?: number[][] };
  iterations?: number;
}

/** 行标准化结构化报告（空间模型 diagnostics 子对象） */
export interface RowStandardizedReport {
  requested?: boolean;
  applied?: boolean;
  row_sums_min?: number;
  row_sums_max?: number;
}

/** S5.7 空间模型 diagnostics（与 Julia `MetricaSpatial` 序列化键对齐） */
export interface SpatialDiagnostics {
  n_obs?: number;
  n_nonzero_links?: number;
  symmetry_hint?: string;
  id_join_unique?: boolean;
  id_join_missing_count?: number;
  spatial_weights_basename?: string;
  row_standardized_report?: RowStandardizedReport;
  moran_i?: number | null;
  moran_ei?: number | null;
  moran_var?: number | null;
  moran_z?: number | null;
  moran_pvalue?: number | null;
  rho?: number;
  lambda?: number;
  direct_effects?: Record<string, number> | null;
  indirect_effects?: Record<string, number> | null;
  total_effects?: Record<string, number> | null;
  effects_method?: string | null;
}

export interface ModelCapabilities {
  status: 'implemented' | 'partial' | 'planned' | string;
  model_family: string;
  supported_models: string[];
  estimators: string[];
  diagnostics_available: string[];
  diagnostics_unavailable: string[];
  effects_available: string[];
  prediction_available: boolean;
  limitations: string[];
}

/** 标准化增广数据可用性声明（与 Julia `build_augment_status` 对齐） */
export interface AugmentStatus {
  available: boolean;
  columns_available: string[];
  columns_unavailable: string[];
  preview_included: boolean;
  preview_rows: number;
}

/** 效应分解结果（空间模型 direct/indirect/total effects） */
export interface EffectsResult {
  method?: string;
  direct?: Record<string, number>;
  indirect?: Record<string, number>;
  total?: Record<string, number>;
}

/** 线性 GMM（Runtime `result_payload.diagnostics`） */
export interface GmmDiagnostics {
  j_statistic?: number;
  j_df?: number;
  j_pvalue?: number | null;
  n_moments?: number;
  n_params?: number;
  overidentifying_restrictions?: number;
  gmm_weight?: string;
  weight_matrix_description?: string;
  iterations?: number;
  exactly_identified?: boolean;
  /** `dynamic_panel_gmm`：一阶差分残差序列相关检验 */
  ar1_test?: { statistic?: number; pvalue?: number; description?: string };
  ar2_test?: { statistic?: number; pvalue?: number; description?: string };
  hansen_j?: { j_statistic?: number; j_df?: number; j_pvalue?: number | null };
  n_instruments?: number;
  n_groups?: number;
  n_periods?: number;
  n_obs_diff?: number;
  instrument_lags?: number[];
  dpgmm_style?: string;
  collapse_instruments?: boolean;
  diff_hansen?: { c_statistic?: number; df?: number; pvalue?: number | null };
}

/** 分位数回归（`result_payload.diagnostics`） */
export interface QuantileDiagnostics {
  tau?: number;
  inference_kind?: string;
  rank_X?: number;
  cond_X?: number;
  solver?: string;
  pseudo_r2_definition?: string;
}

/** 受控 NLS（`result_payload.diagnostics`） */
export interface NlsDiagnostics {
  converged?: boolean;
  iterations?: number;
  optimizer?: string;
  objective_final?: number;
  gradient_norm?: number | null;
  start_used?: number[];
  failure_code?: string | null;
  nls_family?: string;
}

/** ARCH / GARCH（`result_payload.diagnostics`） */
export interface VolatilityDiagnostics {
  converged?: boolean;
  iterations?: number;
  optimizer?: string;
  loglik?: number;
  persistence?: number;
  unconditional_variance?: number;
  conditional_volatility_preview?: number[];
  volatility_length?: number;
  arch_order?: number;
  garch_p?: number;
  garch_q?: number;
  failure_code?: string | null;
}

/** 单门限回归（`result_payload.diagnostics`） */
export interface ThresholdDiagnostics {
  gamma_hat?: number;
  n_below?: number;
  n_above?: number;
  rss_piecewise?: number;
  search_grid_meta?: {
    n_candidates?: number;
    trim_frac_applied?: number;
    grid_input_length?: number;
  };
}

export interface DurationDiagnostics {
  n_obs?: number;
  n_events?: number;
  n_censored?: number;
  censoring_fraction?: number;
  risk_set_ties_method?: string;
  converged?: boolean;
  iterations?: number;
  loglikelihood?: number;
  baseline_hazard_summary?: {
    n_event_times?: number;
    preview?: Array<{ time: number; cumulative_hazard: number }>;
    ties_method?: string;
  };
  ph_diagnostics?: null | Record<string, unknown>;
}

export interface HazardRatioEntry {
  term: string;
  hr: number;
  ci_lower: number | null;
  ci_upper: number | null;
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
  /** 方程级 glance 等场景下的结构化警告 */
  warnings?: Warning[];
}

export interface TidyRow {
  /** 多方程合并 `tidy` 时标识所属方程（如 `y1 ~ x1 + x2`） */
  equation?: string;
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

// ---- 模型结果 ==================================================================

/**
 * 模型结果核心字段 —— 所有模型族共有的字段。
 */
export interface CoreResultFields {
  glance: GlanceResult;
  tidy: TidyRow[];
  diagnostics?: OLSDiagnostics | PanelDiagnostics | DiscreteDiagnostics | GmmDiagnostics | SystemEquationsDiagnostics | QuantileDiagnostics | NlsDiagnostics | ThresholdDiagnostics | VolatilityDiagnostics | SpatialDiagnostics | GWRDiagnostics | SpatialProbitDiagnostics | BayesDiagnostics | DurationDiagnostics;
  model_capabilities?: ModelCapabilities;
  augment_status?: AugmentStatus;
  effects?: EffectsResult;
  odds_ratios?: OddsRatioEntry[];
  hazard_ratios?: HazardRatioEntry[];
  incidence_rate_ratios?: IRREntry[];
  augment_preview?: AugmentRow[];
  warnings: Warning[];
  messages?: Message[];
  summary_text?: string;
  vcov_label?: string;
  loglikelihood?: number;
  equation_glances?: GlanceResult[];
}

/**
 * 因果推断模型结果字段（DID / EventStudy / IPW / PSM / AIPW）。
 * 使用 `hasCausalResult()` 类型守卫进行收窄访问。
 */
export interface CausalResultFields {
  /** DID 处理效应 */
  treat_effect?: number;
  treat_effect_se?: number;
  treat_effect_pvalue?: number;
  n_treated?: number;
  n_control?: number;
  /** EventStudy 事件研究系数 */
  period_coefficients?: number[];
  period_stderrors?: number[];
  period_labels?: string[];
  pre_trend_pvalue?: number;
  parallel_trends_supported?: boolean;
  /** IPW / AIPW 平均处理效应 */
  ate?: number;
  att?: number;
  atu?: number;
  att_se?: number;
  ate_se?: number;
  /** PSM 匹配信息 */
  n_matched?: number;
}

/**
 * 时间序列结果字段（ARIMA / VAR / UnitRoot / Cointegration）。
 * 使用 `hasTimeSeriesResult()` 类型守卫进行收窄访问。
 */
export interface TimeSeriesResultFields {
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
}

/**
 * 复杂抽样结果字段（Survey）。
 * 使用 `hasSurveyResult()` 类型守卫进行收窄访问。
 */
export interface SurveyResultFields {
  design_effects?: DEFFEntry[];
  strata_summary?: StrataEntry[];
}

/**
 * 模型结果 —— 核心字段 + 各模型族可选字段的交叉类型。
 * 所有字段在 JSON 线格式中平坦展开，TypeScript 侧通过交叉类型分组便于按模型族理解。
 *
 * 使用类型守卫函数进行收窄：
 *   if (hasCausalResult(result)) { result.treat_effect }
 */
export type ModelResult = CoreResultFields & CausalResultFields & TimeSeriesResultFields & SurveyResultFields;

// ---- 类型守卫：按模型族收窄 ModelResult ---- */

/** 检查结果是否包含因果推断字段 */
export function hasCausalResult(result: ModelResult): result is ModelResult & CausalResultFields {
  return result.treat_effect !== undefined || result.ate !== undefined;
}

/** 检查结果是否包含时间序列字段 */
export function hasTimeSeriesResult(result: ModelResult): result is ModelResult & TimeSeriesResultFields {
  return result.forecast !== undefined || result.adf_statistic !== undefined;
}

/** 检查结果是否包含复杂抽样字段 */
export function hasSurveyResult(result: ModelResult): result is ModelResult & SurveyResultFields {
  return Array.isArray(result.design_effects) || Array.isArray(result.strata_summary);
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

/** 运行记录表（CLI `runs` 专用，前端结果流） */
export interface RunsTableResult {
  kind: 'runs';
  dataset_summary: { row_count: number; column_count: number };
  runs: Array<{
    run_id: string;
    action: string;
    model_type?: string | null;
    dataset_path: string;
    status: string;
    finished_at: string;
  }>;
}

/** 导出预览摘要（CLI `export`，含 plot 元数据） */
export interface ExportPreviewResult {
  kind: 'export_preview';
  dataset_summary: { row_count: 1; column_count: 4 };
  run_id: string;
  format: string;
  target_path: string | null;
  content_preview: string;
}

/** CLI 模型对比表（仅消费结构化字段） */
export interface ModelComparisonResult {
  kind: 'model_comparison';
  dataset_summary: { row_count: number; column_count: number };
  family: 'discrete' | 'causal';
  rows: Array<Record<string, string | number | null>>;
}

export type DataResult =
  | DescribeResult
  | SummarizeResult
  | TabulateResult
  | BrowseResult
  | RunsTableResult
  | ExportPreviewResult
  | ModelComparisonResult;

export interface DataCommand {
  kind: DataCommandKind;
  variables?: string[];
  limit?: number;
}

export interface MessageItem {
  id: string;
  kind: 'command' | 'result' | 'transform' | 'data';
  command?: string;
  /** 与 Runtime `run_record.run_id` 对齐，供导出图表等能力索引 */
  run_id?: string;
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

export type ModelType =
  | 'ols' | 'iv' | 'gmm_linear' | 'quantile' | 'nls' | 'threshold' | 'gls' | 'pca'
  | 'panel' | 'panel_iv' | 'dynamic_panel_gmm' | 'sur' | 'system_2sls' | 'system_3sls'
  | 'logit' | 'probit' | 'poisson' | 'ordered_logit' | 'multinomial_logit' | 'negbin'
  | 'did' | 'event_study' | 'did_iv' | 'rd' | 'rd_iv' | 'ipw' | 'psm' | 'aipw'
  | 'arima' | 'var' | 'unitroot' | 'cointegration' | 'arch' | 'garch' | 'gjr_garch' | 'egarch'
  | 'survey_ols' | 'survey_logit' | 'survey_probit' | 'survey_poisson'
  | 'spatial_lag' | 'spatial_error' | 'spatial_slx' | 'spatial_sdm' | 'spatial_sdem' | 'spatial_sac'
  | 'spatial_gwr' | 'spatial_gtwr' | 'spatial_probit'
  | 'duration_cox' | 'aft_weibull' | 'aft_exponential' | 'aft_lognormal' | 'aft_loglogistic'
  | 'bayes_linear' | 'bayes_logistic' | 'bayes_probit' | 'bayes_hierarchical';

/** Runtime wire format: common fields + nested `params` for model-family-specific options. */
export interface ModelSpec {
  model_type: ModelType;
  formula: string;
  vcov?: { type: string };
  weights?: string;
  cluster_column?: string;
  params: Record<string, unknown>;
}

// === 模型族 params 类型（嵌套在 ModelSpec.params 中） ============================

/**
 * 每个模型族的 `params` 对象形状。`ModelSpec` 的公共字段为 formula / vcov / weights / cluster_column。
 */

/** 核心模型字段 —— 所有变体共享 */
interface ModelSpecCore {
  formula: string;
  vcov?: { type: string };
  weights?: string;
  cluster_column?: string;
}

/** 线性回归（ols / gls / pca / iv / gmm_linear） */
export interface LinearSpec extends ModelSpecCore {
  model_type: 'ols' | 'gls' | 'pca' | 'iv' | 'gmm_linear';
  instruments?: string[];
  endog_columns?: string[];
  gmm_weight?: string;
}

/** 面板（panel / panel_iv / did / event_study / dynamic_panel_gmm） */
export interface PanelSpec extends ModelSpecCore {
  model_type: 'panel' | 'panel_iv' | 'did' | 'event_study' | 'dynamic_panel_gmm';
  panel_id?: string;
  panel_time?: string;
  panel_method?: 'fe' | 're' | 'fd' | 'between' | 'hdfde' | 'cre' | 'panel_iv';
  instruments?: string[];
  endog_columns?: string[];
  gmm_weight?: string;
  dpgmm_style?: string;
  instrument_lags?: [number, number];
  collapse_instruments?: boolean;
  omega_spec?: string;
  treated_column?: string;
  post_column?: string;
  event_time_column?: string;
}

/** 离散选择（logit / probit / poisson / negbin / ordered_logit / multinomial_logit） */
export interface DiscreteSpec extends ModelSpecCore {
  model_type: 'logit' | 'probit' | 'poisson' | 'ordered_logit' | 'multinomial_logit' | 'negbin';
}

/** 因果推断（ipw / psm / aipw / did_iv / rd / rd_iv） */
export interface CausalSpec extends ModelSpecCore {
  model_type: 'ipw' | 'psm' | 'aipw' | 'did_iv' | 'rd' | 'rd_iv';
  treatment_column?: string;
  outcome_column?: string;
  propensity_formula?: string;
  outcome_formula?: string;
}

/** 系统方程（sur / system_2sls / system_3sls） */
export interface SystemSpec extends ModelSpecCore {
  model_type: 'sur' | 'system_2sls' | 'system_3sls';
  equations?: string[];
  system_endogenous?: string[][];
  system_instruments?: string[][];
  sur_max_iter?: number;
  sur_tol?: number;
}

/** 时间序列（arima / var / unitroot / cointegration / arch / garch / gjr_garch / egarch） */
export interface TimeSeriesSpec extends ModelSpecCore {
  model_type: 'arima' | 'var' | 'unitroot' | 'cointegration' | 'arch' | 'garch' | 'gjr_garch' | 'egarch';
  time_column?: string;
  variable?: string;
  variables?: string[];
  order?: [number, number, number];
  seasonal_order?: [number, number, number, number];
  ts_method?: 'mle' | 'css' | 'engle_granger' | 'johansen';
  lags?: number;
  deterministic?: 'constant' | 'trend' | 'none';
  arch_order?: number;
  garch_p?: number;
  garch_q?: number;
  garch_max_iter?: number;
  garch_tol?: number;
}

/** 复杂抽样（survey_ols / survey_logit / survey_probit / survey_poisson） */
export interface SurveySpec extends ModelSpecCore {
  model_type: 'survey_ols' | 'survey_logit' | 'survey_probit' | 'survey_poisson';
  weights_column?: string;
  strata_column?: string;
  psu_column?: string;
  fpc_column?: string;
}

/** 空间（spatial_* / gwr / gtwr） */
export interface SpatialSpec extends ModelSpecCore {
  model_type: 'spatial_lag' | 'spatial_error' | 'spatial_slx' | 'spatial_sdm' | 'spatial_sdem' | 'spatial_sac' | 'spatial_gwr' | 'spatial_gtwr' | 'spatial_probit';
  spatial_weights_path?: string;
  spatial_id_column?: string;
  spatial_row_standardize?: boolean;
  spatial_coord_columns?: string[];
  spatial_distance?: string;
  spatial_crs?: string;
  gwr_kernel?: string;
  gwr_bandwidth?: number;
  gwr_bandwidth_selection?: string;
  gwr_adaptive?: boolean;
  gtwr_time_column?: string;
  gtwr_time_scale?: number | string;
}

/** 久期（duration_cox / aft_*） */
export interface DurationSpec extends ModelSpecCore {
  model_type: 'duration_cox' | 'aft_weibull' | 'aft_exponential' | 'aft_lognormal' | 'aft_loglogistic';
  duration_time_column?: string;
  duration_event_column?: string;
}

/** 贝叶斯（bayes_linear / bayes_logistic / bayes_probit / bayes_hierarchical） */
export interface BayesSpec extends ModelSpecCore {
  model_type: 'bayes_linear' | 'bayes_logistic' | 'bayes_probit' | 'bayes_hierarchical';
  bayes_seed?: number;
  bayes_prior_scale?: number;
  bayes_iter?: number;
  bayes_warmup?: number;
  bayes_chains?: number;
  bayes_group_column?: string;
}

/** 非线性/门限（nls / threshold） */
export interface NonlinearSpec extends ModelSpecCore {
  model_type: 'nls' | 'threshold';
  nls_family?: string;
  nls_start?: number[];
  nls_max_iter?: number;
  nls_tol?: number;
  threshold_variable?: string;
  threshold_grid?: number[];
  threshold_trim_frac?: number;
}

/** 分位数回归 */
export interface QuantileSpec extends ModelSpecCore {
  model_type: 'quantile';
  quantile_tau?: number;
}

/** 模型规格判别联合 —— 所有模型族的封闭联合。 */
export type ModelSpecVariant =
  | LinearSpec | PanelSpec | DiscreteSpec | CausalSpec | SystemSpec
  | TimeSeriesSpec | SurveySpec | SpatialSpec | DurationSpec | BayesSpec
  | NonlinearSpec | QuantileSpec;

// ---- 模型类型帮助常量 ----

/** 按模型族分组的 model_type 映射（与 Rust ModelSpecKind::kind() 对齐） */
export const MODEL_TYPE_FAMILY: Record<string, string> = {
  ols: 'linear', gls: 'linear', pca: 'linear', iv: 'linear', gmm_linear: 'linear',
  panel: 'panel', panel_iv: 'panel', did: 'panel', event_study: 'panel', dynamic_panel_gmm: 'panel',
  logit: 'discrete', probit: 'discrete', poisson: 'discrete', negbin: 'discrete',
  ordered_logit: 'discrete', multinomial_logit: 'discrete',
  ipw: 'causal', psm: 'causal', aipw: 'causal', did_iv: 'causal', rd: 'causal', rd_iv: 'causal',
  sur: 'system', system_2sls: 'system', system_3sls: 'system',
  arima: 'time_series', var: 'time_series', unitroot: 'time_series', cointegration: 'time_series',
  arch: 'time_series', garch: 'time_series', gjr_garch: 'time_series', egarch: 'time_series',
  quantile: 'quantile', nls: 'nonlinear', threshold: 'nonlinear',
  duration_cox: 'duration', aft_weibull: 'duration', aft_exponential: 'duration',
  aft_lognormal: 'duration', aft_loglogistic: 'duration',
  bayes_linear: 'bayes', bayes_logistic: 'bayes', bayes_probit: 'bayes', bayes_hierarchical: 'bayes',
  spatial_lag: 'spatial', spatial_error: 'spatial', spatial_slx: 'spatial',
  spatial_sdm: 'spatial', spatial_sdem: 'spatial', spatial_sac: 'spatial',
  spatial_gwr: 'spatial', spatial_gtwr: 'spatial', spatial_probit: 'spatial',
};

/** 获取模型族名称 */
export function getModelFamily(modelType: string): string | undefined {
  return MODEL_TYPE_FAMILY[modelType];
}

/** 类型守卫：检查 model_type 是否属于指定族 */
export function isModelFamily(modelType: string, family: string): boolean {
  return MODEL_TYPE_FAMILY[modelType] === family;
}

/** Exported header guard */
export function isModelSpec(v: unknown): v is ModelSpec {
  return (
    typeof v === 'object' &&
    v !== null &&
    'model_type' in v &&
    'formula' in v &&
    'params' in v &&
    typeof (v as ModelSpec).params === 'object'
  );
}
export interface GWRLocalCoefficientRow {
  obs: number;
  [coefName: string]: number;
}

/** GWR/GTWR 诊断 */
export interface GWRDiagnostics {
  bandwidth?: number;
  bandwidth_selection?: string;
  bandwidth_score?: number;
  kernel?: string;
  adaptive?: boolean;
  effective_parameters?: number;
  aicc?: number;
  local_coefficients_preview?: GWRLocalCoefficientRow[];
  local_r2?: number[];
  time_scale?: number;
  time_column?: string;
  time_range?: number[];
}

/** 空间 Probit 诊断 */
export interface SpatialProbitDiagnostics {
  rho_accept_rate?: number;
  n_iter?: number;
  n_warmup?: number;
  n_chains?: number;
  inference_mode?: string;
  rho_posterior_mean?: number;
  rho_posterior_sd?: number;
  rho_credible_lower?: number;
  rho_credible_upper?: number;
}

/** 贝叶斯线性回归（`result_payload.diagnostics`） */
export interface BayesDiagnostics {
  inference_mode?: string;
  seed_used?: number | null;
  sigma2_known?: boolean;
  sigma2_posterior_mean?: number;
  prior_scale?: number;
  log_marginal_likelihood?: number | null;
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
