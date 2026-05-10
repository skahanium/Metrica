import type { DataOp, DataOpKind } from '../types/protocol';
import type { ParsedCommand, ParsedOption } from './commandParser';

const DATA_OP_VERBS = new Set([
  'filter',
  'impute_missing',
  'generate',
  'replace',
  'rename',
  'drop',
  'keep',
  'sort',
  'merge',
  'reshape',
  'collapse',
]);

function optionMap(options: ParsedOption[]): Map<string, string | undefined> {
  return new Map(options.map((option) => [option.name.toLowerCase(), option.value]));
}

function splitList(value = ''): string[] {
  return value
    .split(/[,\s]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function stripQuotes(value: string): string {
  return value.replace(/^["']|["']$/g, '');
}

function requireText(value: string | undefined, message: string): string | { error: string } {
  const text = value?.trim() ?? '';
  return text ? text : { error: message };
}

export function isDataOperationVerb(verb: string): boolean {
  return DATA_OP_VERBS.has(verb.toLowerCase());
}

export function parseToDataOp(parsed: ParsedCommand): DataOp | { error: string } {
  if (parsed.error) return { error: parsed.error };

  const verb = parsed.verb.toLowerCase();
  const positionals = parsed.positionals;
  const opts = optionMap(parsed.options);

  if (!isDataOperationVerb(verb)) {
    return { error: `命令 "${parsed.verb}" 不是数据操作命令。` };
  }

  if (verb === 'filter') {
    const condition = requireText(positionals.join(' '), 'filter 命令需要筛选条件');
    if (typeof condition !== 'string') return condition;
    return { op: 'filter', args: { condition } };
  }

  if (verb === 'impute_missing') {
    return { op: 'impute_missing', args: {} };
  }

  if (verb === 'generate') {
    const eqIndex = positionals.indexOf('=');
    const name = eqIndex === -1 ? positionals[0] : positionals.slice(0, eqIndex).join(' ');
    const expr = eqIndex === -1 ? positionals.slice(1).join(' ') : positionals.slice(eqIndex + 1).join(' ');
    const validName = requireText(name, 'generate 命令需要新变量名');
    if (typeof validName !== 'string') return validName;
    const validExpr = requireText(expr, 'generate 命令需要表达式，例如 generate z = x1 + x2');
    if (typeof validExpr !== 'string') return validExpr;
    return { op: 'generate', args: { name: validName, expr: validExpr } };
  }

  if (verb === 'replace') {
    const col = requireText(positionals[0], 'replace 命令需要列名');
    if (typeof col !== 'string') return col;
    const value = requireText(opts.get('value'), 'replace 命令需要 value(...) 选项');
    if (typeof value !== 'string') return value;
    const condition = requireText(opts.get('if'), 'replace 命令需要 if(...) 条件');
    if (typeof condition !== 'string') return condition;
    return { op: 'replace', args: { col, value, condition } };
  }

  if (verb === 'rename') {
    const oldName = requireText(positionals[0], 'rename 命令需要旧变量名');
    if (typeof oldName !== 'string') return oldName;
    const newName = requireText(positionals[1], 'rename 命令需要新变量名');
    if (typeof newName !== 'string') return newName;
    return { op: 'rename', args: { mapping: { [oldName]: newName } } };
  }

  if (verb === 'drop' || verb === 'keep' || verb === 'sort') {
    if (!positionals.length) return { error: `${verb} 命令需要至少一个变量名` };
    return { op: verb as DataOpKind, args: { cols: positionals } };
  }

  if (verb === 'merge') {
    const withPath = requireText(positionals[0], 'merge 命令需要右表路径');
    if (typeof withPath !== 'string') return withPath;
    const on = splitList(opts.get('on'));
    if (!on.length) return { error: 'merge 命令需要 on(...) 键列' };
    return {
      op: 'merge',
      args: {
        with: stripQuotes(withPath),
        on,
        how: opts.get('how')?.trim() || 'inner',
      },
    };
  }

  if (verb === 'reshape') {
    const direction = positionals[0]?.toLowerCase();
    const idCols = splitList(opts.get('id'));
    const timeCol = opts.get('time')?.trim();
    if (direction !== 'long' && direction !== 'wide') {
      return { error: 'reshape 命令需要方向 long 或 wide' };
    }
    if (!idCols.length) return { error: 'reshape 命令需要 id(...) 选项' };
    if (!timeCol) return { error: 'reshape 命令需要 time(...) 选项' };
    const cols = positionals.slice(1);
    if (!cols.length) return { error: 'reshape 命令需要变量列表' };
    if (direction === 'long') {
      return { op: 'reshape_long', args: { id_cols: idCols, time_col: timeCol, stub_cols: cols } };
    }
    return { op: 'reshape_wide', args: { id_cols: idCols, time_col: timeCol, value_cols: cols } };
  }

  if (verb === 'collapse') {
    const valueCols = positionals;
    if (!valueCols.length) return { error: 'collapse 命令需要值变量列表' };
    const by = splitList(opts.get('by'));
    const stats = splitList(opts.get('stats'));
    if (!by.length) return { error: 'collapse 命令需要 by(...) 分组变量' };
    if (!stats.length) return { error: 'collapse 命令需要 stats(...) 统计量' };
    return { op: 'collapse', args: { by, stats, value_cols: valueCols } };
  }

  return { error: `暂不支持的数据操作命令：${parsed.verb}` };
}
