import { getGrammar } from './commandGrammar';
import type { ModelSpec } from '../types/protocol';

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

  const verb = tokens[0].toLowerCase();
  const grammar = getGrammar(verb);
  if (!grammar) {
    return { verb, positionals: [], options: [], error: `未知命令: ${verb}` };
  }

  const rest = tokens.slice(1);
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
  'regress', 'ivregress', 'gls', 'xtreg', 'xtivreg', 'logit', 'probit', 'poisson',
  'ologit', 'mlogit', 'nbreg', 'did', 'eventstudy', 'ipw', 'psm', 'aipw',
  'arima', 'var', 'dfuller', 'coint', 'svy',
]);

// ---- 动词 -> model_type 映射 ----

function verbToModelType(verb: string): string {
  const map: Record<string, string> = {
    regress: 'ols',
    ivregress: 'iv',
    gls: 'gls',
    xtreg: 'panel',
    xtivreg: 'panel',
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

  if (optMap.has('robust')) spec.vcov = { type: 'hc1' };

  if (optMap.has('cluster')) spec.cluster_column = optMap.get('cluster');

  if (optMap.has('weights')) spec.weights = optMap.get('weights');

  // ---- 面板选项 ----

  if (optMap.has('id')) spec.panel_id = optMap.get('id');
  if (optMap.has('time')) spec.panel_time = optMap.get('time');
  if (optMap.has('method')) spec.panel_method = optMap.get('method') as ModelSpec['panel_method'];

  // ---- IV 选项 ----

  if (optMap.has('endogenous')) {
    spec.endog_columns = optMap.get('endogenous')!.split(/\s+/).filter(Boolean);
  }
  if (optMap.has('instruments')) {
    spec.instruments = optMap.get('instruments')!.split(/\s+/).filter(Boolean);
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
  }

  // ---- 时间序列选项 ----

  if (modelType === 'arima' || modelType === 'var' || modelType === 'unitroot' || modelType === 'cointegration') {
    const ar = optMap.has('ar') ? parseInt(optMap.get('ar')!) : 1;
    const i = optMap.has('i') ? parseInt(optMap.get('i')!) : 0;
    const ma = optMap.has('ma') ? parseInt(optMap.get('ma')!) : 0;
    if (modelType === 'arima' && (optMap.has('ar') || optMap.has('i') || optMap.has('ma'))) {
      spec.order = [ar, i, ma];
    }
    if (optMap.has('lags')) spec.lags = parseInt(optMap.get('lags')!);
    if (optMap.has('deterministic')) {
      spec.deterministic = optMap.get('deterministic') as 'constant' | 'trend' | 'none';
    }
    // 第一个 positional 可能是变量名（时间序列模型无因变量）
    if (positionals.length >= 1 && spec.formula) {
      spec.variable = positionals[0];
    }
  }

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

  if (optMap.has('robust')) spec.vcov = { type: 'hc1' };
  if (optMap.has('cluster')) spec.cluster_column = optMap.get('cluster');
  // svy 的 weights 选项映射为 weights_column
  if (optMap.has('weights')) spec.weights_column = optMap.get('weights');
  if (optMap.has('strata')) spec.strata_column = optMap.get('strata');
  if (optMap.has('psu')) spec.psu_column = optMap.get('psu');
  if (optMap.has('fpc')) spec.fpc_column = optMap.get('fpc');

  return spec;
}
