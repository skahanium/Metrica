import { getGrammar } from './commandGrammar';
import type { ModelSpec, DiagnosticSpec } from '../types/protocol';

// ---- 解析类型 ----

export interface ParsedOption {
  name: string;
  value?: string;
}

export interface ParsedCommand {
  verb: string;
  positionals: string[];
  options: ParsedOption[];
  error?: string;
}

// ---- 词法分析 ----

/**
 * 将 CLI 输入字符串切分为 token 列表。
 * 保留双引号和单引号包裹的完整子串。
 */
export function tokenize(input: string): string[] {
  const tokens: string[] = [];
  let current = '';
  let inQuote = false;
  let quoteChar = '';
  let parenDepth = 0;
  for (const ch of input) {
    if (!inQuote && (ch === '"' || ch === "'")) {
      inQuote = true;
      quoteChar = ch;
      current += ch;
    } else if (inQuote && ch === quoteChar) {
      inQuote = false;
      current += ch;
    } else if (!inQuote && ch === '(') {
      parenDepth++;
      current += ch;
    } else if (!inQuote && ch === ')') {
      parenDepth = Math.max(0, parenDepth - 1);
      current += ch;
    } else if (!inQuote && ch === ' ') {
      if (parenDepth > 0) {
        // 保留括号内部的空格（如 instruments(z1 z2)）
        current += ch;
      } else {
        if (current) {
          tokens.push(current);
          current = '';
        }
      }
    } else if (!inQuote && ch === ',') {
      if (parenDepth > 0) {
        // 保留括号内部的逗号
        current += ch;
      } else {
        if (current) {
          tokens.push(current);
          current = '';
        }
        tokens.push(',');
      }
    } else {
      current += ch;
    }
  }
  if (current) tokens.push(current);
  return tokens;
}

// ---- 语法分析 ----

/**
 * 将 token 列表解析为结构化命令：动词、位置参数、选项。
 * 语法：<verb> [positionals...] [, option1 option2(value) ...]
 */
export function parse(input: string): ParsedCommand {
  const tokens = tokenize(input.trim());
  if (tokens.length === 0) {
    return { verb: '', positionals: [], options: [], error: '空命令' };
  }

  const rawVerb = tokens[0].toLowerCase();
  // 命令别名（load 为独立项目命令，不得映射到 project）
  const aliasMap: Record<string, string> = {
    import: 'use',
  };
  const verb = aliasMap[rawVerb] || rawVerb;
  const effectiveTokens = tokens.map((t, i) => (i === 0 ? verb : t));

  const grammar = getGrammar(verb);
  if (!grammar) {
    return { verb: rawVerb, positionals: [], options: [], error: `未知命令: ${rawVerb}` };
  }

  const rest = effectiveTokens.slice(1);
  const commaIdx = rest.indexOf(',');

  // 逗号之前为位置参数
  const positionals = commaIdx === -1 ? rest : rest.slice(0, commaIdx);

  // 逗号之后为选项
  const options: ParsedOption[] = [];
  if (commaIdx !== -1) {
    const optTokens = rest.slice(commaIdx + 1);
    for (const token of optTokens) {
      const match = token.match(/^(\w+)\((.+)\)$/);
      if (match) {
        options.push({ name: match[1], value: match[2] });
      } else {
        options.push({ name: token });
      }
    }
  }

  return { verb, positionals, options };
}

// ---- 已知模型动词集合 ----

const MODEL_VERBS = new Set([
  'regress', 'ivregress', 'gmm', 'qreg', 'nls', 'threg', 'gls', 'xtreg', 'xtivreg', 'xtabond', 'logit', 'probit', 'poisson',
  'ologit', 'mlogit', 'nbreg', 'did', 'eventstudy', 'ipw', 'psm', 'aipw',
  'arima', 'var', 'dfuller', 'coint', 'svy', 'sur', 'reg3',
]);

// ---- 动词 -> model_type 映射 ----

function verbToModelType(verb: string): string {
  const map: Record<string, string> = {
    regress: 'ols',
    ivregress: 'iv',
    gmm: 'gmm_linear',
    qreg: 'quantile',
    nls: 'nls',
    threg: 'threshold',
    gls: 'gls',
    xtreg: 'panel',
    xtivreg: 'panel_iv',
    xtabond: 'dynamic_panel_gmm',
    logit: 'logit',
    probit: 'probit',
    poisson: 'poisson',
    ologit: 'ordered_logit',
    mlogit: 'multinomial_logit',
    nbreg: 'negbin',
    did: 'did',
    eventstudy: 'event_study',
    ipw: 'ipw',
    psm: 'psm',
    aipw: 'aipw',
    arima: 'arima',
    var: 'var',
    dfuller: 'unitroot',
    coint: 'cointegration',
  };
  return map[verb] || verb;
}

/** 将 CLI 括号块 `(y x1 x2)` 转为单方程公式 `y ~ x1 + x2` */
type ParenBlocksResult = { ok: true; equations: string[] } | { ok: false; error: string };

function parseParenEquationBlocks(positionals: string[]): ParenBlocksResult {
  if (positionals.length === 0) {
    return { ok: false, error: '请至少提供一个 (因变量 自变量1 …) 方程块。' };
  }
  const equations: string[] = [];
  for (const block of positionals) {
    const m = block.match(/^\((.+)\)$/);
    if (!m) {
      return { ok: false, error: `方程块须为圆括号包裹，例如 (y1 x1 x2)，收到：${block}` };
    }
    const parts = m[1].trim().split(/\s+/).filter(Boolean);
    if (parts.length < 2) {
      return { ok: false, error: '每个方程块至少需要因变量与 1 个自变量。' };
    }
    const rhs = parts.slice(1).join(' + ');
    equations.push(`${parts[0]} ~ ${rhs}`);
  }
  return { ok: true, equations };
}

/** 将 `a b|c c` 解析为按方程分组的列名数组，与协议 `system_*` 二维数组对齐 */
function splitPipeEquationColumns(raw: string | undefined): string[][] {
  if (raw === undefined || String(raw).trim() === '') return [];
  return String(raw)
    .split('|')
    .map((seg) => seg.trim().split(/\s+/).filter(Boolean));
}

/** 解析 `grid(min max n)` 并展开为等距严格递增数组（与 Runtime 上限 n≤500 对齐）。 */
function parseExpandedThresholdGrid(raw: string): { error: string } | { grid: number[] } {
  const parts = String(raw).trim().split(/\s+/).filter(Boolean);
  if (parts.length !== 3) {
    return { error: 'grid(min max n) 需要恰好三个数值。' };
  }
  const lo = parseFloat(parts[0]);
  const hi = parseFloat(parts[1]);
  const n = parseInt(parts[2], 10);
  if (![lo, hi].every(Number.isFinite) || !Number.isFinite(n)) {
    return { error: 'grid 的 min、max 与点数 n 须全为有限数。' };
  }
  if (n < 2 || n > 500) {
    return { error: 'grid 点数 n 须在 2–500 之间（与 Runtime DoS 上限一致）。' };
  }
  if (hi <= lo) {
    return { error: 'grid 要求 max > min。' };
  }
  if (n === 2) {
    return { grid: [lo, hi] };
  }
  const step = (hi - lo) / (n - 1);
  const grid: number[] = [];
  for (let i = 0; i < n; i += 1) {
    grid.push(lo + step * i);
  }
  return { grid };
}

// ---- 语义分析：ParsedCommand -> ModelSpec ----

/**
 * 将解析后的命令翻译为后端 API 使用的 ModelSpec 对象。
 * 返回带 error 属性的对象表示翻译失败。
 */
export function parseToModelSpec(parsed: ParsedCommand): ModelSpec | { error: string } {
  const { verb, positionals, options, error } = parsed;
  if (error) return { error };

  if (!MODEL_VERBS.has(verb)) {
    return { error: `命令 "${verb}" 暂不支持，请使用模型命令（如 regress）。` };
  }

  const optMap = new Map(options.map(o => [o.name, o.value]));

  if (verb === 'sur') {
    const br = parseParenEquationBlocks(positionals);
    if (!br.ok) return { error: br.error };
    const spec: ModelSpec = {
      model_type: 'sur',
      formula: '',
      equations: br.equations,
    };
    if (optMap.has('maxiter')) {
      const n = parseInt(String(optMap.get('maxiter')).trim(), 10);
      if (!Number.isNaN(n)) spec.sur_max_iter = n;
    }
    if (optMap.has('tol')) {
      const t = parseFloat(String(optMap.get('tol')).trim());
      if (!Number.isNaN(t)) spec.sur_tol = t;
    }
    return spec;
  }

  if (verb === 'reg3') {
    const br = parseParenEquationBlocks(positionals);
    if (!br.ok) return { error: br.error };
    const endogRaw = optMap.get('endogenous');
    const instRaw = optMap.get('instruments');
    if (!endogRaw || !instRaw) {
      return { error: 'reg3 需要 endogenous(...) 与 instruments(...)（多方程时用 | 分隔方程段）。' };
    }
    const system_endogenous = splitPipeEquationColumns(endogRaw);
    const system_instruments = splitPipeEquationColumns(instRaw);
    const g = br.equations.length;
    if (system_endogenous.length !== g || system_instruments.length !== g) {
      return {
        error: `endogenous / instruments 用 | 分隔的方程段数须为 ${g}，与方程块数一致（当前 endogenous 段 ${system_endogenous.length}，instruments 段 ${system_instruments.length}）。`,
      };
    }
    const methodRaw = (optMap.get('method') || 'twostep').trim().toLowerCase();
    const model_type: ModelSpec['model_type'] = methodRaw === '3sls' ? 'system_3sls' : 'system_2sls';
    return {
      model_type,
      formula: '',
      equations: br.equations,
      system_endogenous,
      system_instruments,
    };
  }

  // svy 前缀命令：提取子模型类型和选项
  if (verb === 'svy') {
    return parseSvyToModelSpec(positionals, optMap);
  }

  const modelType = verbToModelType(verb);

  // 组装 formula：depvar ~ indepvar1 + indepvar2 + ...
  let formula = '';
  if (positionals.length >= 2) {
    const rhs = positionals.slice(1).join(' + ');
    formula = optMap.has('noconstant')
      ? `${positionals[0]} ~ 0 + ${rhs}`
      : `${positionals[0]} ~ ${rhs}`;
  } else if (positionals.length === 1) {
    formula = positionals[0];
  }

  const spec: ModelSpec = {
    model_type: modelType as ModelSpec['model_type'],
    formula,
  };

  // ---- 通用选项 ----

  if (optMap.has('robust')) spec.vcov = { type: 'HC1' };

  if (optMap.has('cluster')) spec.cluster_column = optMap.get('cluster');

  if (optMap.has('weights')) spec.weights = optMap.get('weights');

  // ---- 面板选项 ----

  if (optMap.has('id')) spec.panel_id = optMap.get('id');
  if (optMap.has('time')) spec.panel_time = optMap.get('time');
  if (optMap.has('method') && modelType !== 'panel_iv' && modelType !== 'dynamic_panel_gmm'
    && modelType !== 'sur' && modelType !== 'system_2sls' && modelType !== 'system_3sls' && modelType !== 'quantile'
    && modelType !== 'nls' && modelType !== 'threshold') {
    spec.panel_method = optMap.get('method') as ModelSpec['panel_method'];
  }

  // ---- IV 选项 ----

  if (optMap.has('endogenous')) {
    spec.endog_columns = optMap.get('endogenous')!.split(/\s+/).filter(Boolean);
  }
  if (optMap.has('instruments')) {
    spec.instruments = optMap.get('instruments')!.split(/\s+/).filter(Boolean);
  }

  if (modelType === 'gmm_linear' && optMap.has('weight')) {
    spec.gmm_weight = optMap.get('weight');
  }

  if (modelType === 'dynamic_panel_gmm') {
    if (!spec.panel_id || !spec.panel_time) {
      return { error: 'xtabond 需要 id(...) 与 time(...) 指定面板索引列。' };
    }
    if (optMap.has('lags')) {
      const parts = optMap.get('lags')!.trim().split(/\s+/).filter(Boolean).map((s) => parseInt(s, 10));
      if (parts.length !== 2 || parts.some((n) => Number.isNaN(n))) {
        return { error: 'lags(min max) 需要两个整数，例如 lags(2 4)。' };
      }
      spec.instrument_lags = [parts[0], parts[1]];
    } else {
      spec.instrument_lags = [2, 4];
    }
    if (optMap.has('weight')) spec.gmm_weight = optMap.get('weight');
    if (optMap.has('style')) spec.dpgmm_style = optMap.get('style');
    if (optMap.has('collapse')) spec.collapse_instruments = optMap.get('collapse') === 'true';
  }

  if (modelType === 'quantile') {
    let tau = 0.5;
    if (optMap.has('quantile')) {
      const raw = String(optMap.get('quantile')).trim();
      const t = parseFloat(raw);
      if (Number.isNaN(t)) {
        return { error: 'quantile(...) 须为数值，例如 quantile(0.5)。' };
      }
      tau = t;
    }
    if (!(tau > 1e-8 && tau < 1 - 1e-8)) {
      return { error: '分位点 τ 须严格位于开区间 (0,1)，且满足实现要求 1e-8 < τ < 1-1e-8。' };
    }
    spec.quantile_tau = tau;
    spec.vcov = undefined;
    spec.cluster_column = undefined;
    spec.weights = undefined;
  }

  if (modelType === 'nls') {
    spec.vcov = undefined;
    spec.cluster_column = undefined;
    spec.weights = undefined;
    let fam = 'exp_growth';
    if (optMap.has('family')) {
      fam = String(optMap.get('family')).trim().toLowerCase();
      if (fam !== 'exp_growth') {
        return { error: '首期 nls 仅支持 family(exp_growth)。' };
      }
    }
    spec.nls_family = fam;
    if (!optMap.has('start')) {
      return { error: 'nls 须提供 start(β1 β2 β3) 三个有限初值。' };
    }
    const sp = String(optMap.get('start')).trim().split(/\s+/).filter(Boolean);
    if (sp.length !== 3) {
      return { error: 'start 须恰好包含三个浮点数。' };
    }
    const starts = sp.map((s) => parseFloat(s));
    if (starts.some((x) => !Number.isFinite(x))) {
      return { error: 'start 初值须全为有限实数。' };
    }
    spec.nls_start = starts;
    if (optMap.has('maxiter')) {
      const m = parseInt(String(optMap.get('maxiter')), 10);
      if (!Number.isFinite(m) || m < 1) {
        return { error: 'maxiter(...) 须为正整数。' };
      }
      spec.nls_max_iter = m;
    }
    if (optMap.has('tol')) {
      const t = parseFloat(String(optMap.get('tol')));
      if (!Number.isFinite(t) || t <= 0) {
        return { error: 'tol(...) 须为有限正数。' };
      }
      spec.nls_tol = t;
    }
  }

  if (modelType === 'threshold') {
    spec.vcov = undefined;
    spec.cluster_column = undefined;
    spec.weights = undefined;
    if (!optMap.has('qvar') || !String(optMap.get('qvar')).trim()) {
      return { error: 'threg 需要 qvar(切换变量列名)，且该列须出现在公式右侧。' };
    }
    spec.threshold_variable = String(optMap.get('qvar')).trim();
    if (!optMap.has('grid')) {
      return { error: 'threg 需要 grid(min max n)，例如 grid(-1 1 21)。' };
    }
    const gr = parseExpandedThresholdGrid(String(optMap.get('grid')));
    if ('error' in gr) {
      return { error: gr.error };
    }
    spec.threshold_grid = gr.grid;
    if (optMap.has('trim')) {
      const tr = parseFloat(String(optMap.get('trim')));
      if (!Number.isFinite(tr) || tr < 0 || tr >= 0.45) {
        return { error: 'trim 须在 [0, 0.45) 区间内。' };
      }
      spec.threshold_trim_frac = tr;
    }
  }

  // ---- 因果推断选项 ----
  // did / event_study 使用 treated_column；ipw / psm / aipw 使用 treatment_column

  if (modelType === 'did' || modelType === 'event_study') {
    if (optMap.has('treat')) spec.treated_column = optMap.get('treat');
    if (optMap.has('post')) spec.post_column = optMap.get('post');
    if (optMap.has('eventtime')) spec.event_time_column = optMap.get('eventtime');
  } else if (modelType === 'ipw' || modelType === 'psm' || modelType === 'aipw') {
    if (optMap.has('treat')) spec.treatment_column = optMap.get('treat');
    if (optMap.has('outcome')) spec.outcome_column = optMap.get('outcome');
    if (optMap.has('propensity')) spec.propensity_formula = optMap.get('propensity');
    if (optMap.has('outcome_model')) spec.outcome_formula = optMap.get('outcome_model');
  }

  // ---- 时间序列选项 ----

  if (modelType === 'arima' || modelType === 'var' || modelType === 'unitroot' || modelType === 'cointegration') {
    if (optMap.has('time')) spec.time_column = optMap.get('time');
    const ar = optMap.has('ar') ? parseInt(optMap.get('ar')!) : 1;
    const i = optMap.has('i') ? parseInt(optMap.get('i')!) : 0;
    const ma = optMap.has('ma') ? parseInt(optMap.get('ma')!) : 0;
    if (modelType === 'arima' && (optMap.has('ar') || optMap.has('i') || optMap.has('ma'))) {
      spec.order = [ar, i, ma];
    }
    if (optMap.has('lags')) spec.lags = parseInt(optMap.get('lags')!);
    if (modelType === 'cointegration' && optMap.has('method')) {
      spec.ts_method = optMap.get('method') as 'mle' | 'css' | 'engle_granger' | 'johansen';
    }
    if (optMap.has('deterministic')) {
      spec.deterministic = optMap.get('deterministic') as 'constant' | 'trend' | 'none';
    }
    if (modelType === 'var' || modelType === 'cointegration') {
      spec.variables = positionals;
    } else if (positionals.length >= 1 && spec.formula) {
      spec.variable = positionals[0];
    }
  }

  return spec;
}

// ---- 诊断命令解析 ----

/** 已知诊断动词集合（包含别名） */
const DIAGNOSTIC_VERBS = new Set(['diagnostic', 'ovtest', 'hettest', 'vif', 'dwstat', 'bgodfrey', 'hausman']);

/** 别名动词到规范检验名的映射 */
const VERB_TO_DIAGNOSTIC_TEST: Record<string, DiagnosticSpec['test']> = {
  ovtest: 'reset',
  hettest: 'bp',
  vif: 'vif',
  dwstat: 'dw',
  bgodfrey: 'bg',
};

export function isDiagnosticVerb(verb: string): boolean {
  return DIAGNOSTIC_VERBS.has(verb);
}

/**
 * 将解析后的命令翻译为 DiagnosticSpec 对象。
 * 支持统一 `diagnostic <test>` 和个别别名动词。
 */
export function parseToDiagnosticSpec(parsed: ParsedCommand): DiagnosticSpec | { error: string } {
  const { verb, positionals, options, error } = parsed;
  if (error) return { error };

  const optMap = new Map(options.map(o => [o.name, o.value]));

  // 统一 diagnostic 动词：第一个位置参数为检验名
  if (verb === 'diagnostic') {
    const testName = (positionals[0] || '').toLowerCase();
    const validTests = new Set(['bp', 'bg', 'reset', 'jb', 'dw', 'white', 'vif']);
    if (!testName || !validTests.has(testName)) {
      return { error: `未知的诊断检验: "${testName}"。支持: bp, bg, reset, jb, dw, white, vif` };
    }
    const spec: DiagnosticSpec = { test: testName as DiagnosticSpec['test'] };
    if (optMap.has('lags')) spec.lags = parseInt(optMap.get('lags')!);
    return spec;
  }

  // 别名动词
  const test = VERB_TO_DIAGNOSTIC_TEST[verb];
  if (!test) {
    return { error: `命令 "${verb}" 不是已知的诊断命令。` };
  }
  const spec: DiagnosticSpec = { test };
  if (optMap.has('lags')) spec.lags = parseInt(optMap.get('lags')!);
  return spec;
}

/**
 * 处理 svy 前缀命令：svy <submodel> depvar indepvars..., strata(...) psu(...) weights(...)
 */
function parseSvyToModelSpec(
  positionals: string[],
  optMap: Map<string, string | undefined>,
): ModelSpec | { error: string } {
  if (positionals.length < 1) {
    return { error: 'svy 命令需要指定底层模型（ols / logit / probit / poisson）' };
  }

  const submodel = positionals[0].toLowerCase();
  const submodelMap: Record<string, string> = {
    ols: 'survey_ols',
    logit: 'survey_logit',
    probit: 'survey_probit',
    poisson: 'survey_poisson',
  };

  if (!submodelMap[submodel]) {
    return { error: `svy 不支持的底层模型: ${submodel}（支持 ols / logit / probit / poisson）` };
  }

  const rest = positionals.slice(1);
  let formula = '';
  if (rest.length >= 2) {
    formula = `${rest[0]} ~ ${rest.slice(1).join(' + ')}`;
  } else if (rest.length === 1) {
    formula = rest[0];
  }

  const spec: ModelSpec = {
    model_type: submodelMap[submodel] as ModelSpec['model_type'],
    formula,
  };

  if (optMap.has('robust')) spec.vcov = { type: 'HC1' };
  if (optMap.has('cluster')) spec.cluster_column = optMap.get('cluster');
  // svy 的 weights 选项映射为 weights_column
  if (optMap.has('weights')) spec.weights_column = optMap.get('weights');
  if (optMap.has('strata')) spec.strata_column = optMap.get('strata');
  if (optMap.has('psu')) spec.psu_column = optMap.get('psu');
  if (optMap.has('fpc')) spec.fpc_column = optMap.get('fpc');

  return spec;
}
