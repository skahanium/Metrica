import { getGrammar, COMMAND_LIST, type CommandGrammar } from './commandGrammar';
import type { ColumnSummary } from '../types/protocol';

// --- Types ---

export interface CompletionItem {
  text: string;
  label: string;
  description: string;
  kind: 'verb' | 'variable' | 'option' | 'value';
  priority: number;
}

export interface AutocompleteContext {
  kind: 'verb' | 'depvar' | 'indepvar' | 'option' | 'option_value';
  optionName?: string;
  grammar?: CommandGrammar;
}

// --- Context Detection ---

export function getContext(input: string, cursorPos: number): AutocompleteContext {
  const beforeCursor = input.slice(0, cursorPos);
  const tokens = beforeCursor.trim().split(/\s+/);
  const hasComma = beforeCursor.includes(',');

  // Empty or first token -> verb
  if (beforeCursor.trim() === '' || (tokens.length === 1 && !hasComma && !beforeCursor.endsWith(' '))) {
    return { kind: 'verb' };
  }

  const verb = tokens[0]?.toLowerCase() || '';
  const grammar = getGrammar(verb);

  // After comma -> option zone
  if (hasComma) {
    const afterComma = beforeCursor.slice(beforeCursor.indexOf(',') + 1);
    // Check if inside parentheses: option_name(
    const parenMatch = afterComma.match(/(\w+)\(([^)]*)$/);
    if (parenMatch) {
      return { kind: 'option_value', optionName: parenMatch[1], grammar };
    }
    // Just after comma, typing option name
    return { kind: 'option', grammar };
  }

  // Before comma -> positional argument zone
  if (!grammar) return { kind: 'verb' };

  // Check grammar: if first syntax node is depvar and we're after verb (tokens.length === 1)
  // with space after verb, we're at depvar position
  const afterVerb = beforeCursor.slice(verb.length).trim();
  const posTokens = afterVerb.split(/\s+/).filter(Boolean);

  if (grammar.syntax.length > 0 && grammar.syntax[0].kind === 'depvar' && posTokens.length === 0) {
    // At the depvar position (after verb + space, before any positional)
    return { kind: 'depvar', grammar };
  }

  return { kind: 'indepvar', grammar };
}

// --- Partial Extraction ---

export function getPartial(input: string, cursorPos: number): string {
  const beforeCursor = input.slice(0, cursorPos);
  // Get the last word being typed
  const lastSpace = beforeCursor.lastIndexOf(' ');
  const lastComma = beforeCursor.lastIndexOf(',');
  const lastParen = beforeCursor.lastIndexOf('(');
  const start = Math.max(lastSpace, lastComma, lastParen);
  return beforeCursor.slice(start + 1).trim();
}

// --- Completion Generator ---

export function getCompletions(
  context: AutocompleteContext,
  variables: ColumnSummary[],
  partial: string,
): CompletionItem[] {
  const lowerPartial = partial.toLowerCase();

  switch (context.kind) {
    case 'verb':
      return COMMAND_LIST
        .map(v => {
          const g = getGrammar(v);
          return {
            text: v,
            label: v,
            description: g?.description || '',
            kind: 'verb' as const,
            priority: 0,
          };
        })
        .filter(c => c.text.startsWith(lowerPartial))
        .sort((a, b) => a.text.length - b.text.length);

    case 'depvar':
      return variables
        .filter(v => v.name.toLowerCase().startsWith(lowerPartial))
        .map(v => ({
          text: v.name,
          label: `${v.name}  ${v.inferred_type || v.type || ''}`,
          description: (v.inferred_type === 'continuous' || v.type === 'Float64')
            ? '常用作因变量' : '',
          kind: 'variable' as const,
          priority: (v.inferred_type === 'continuous' || v.type === 'Float64') ? 10 : 5,
        }))
        .sort((a, b) => b.priority - a.priority || a.text.localeCompare(b.text));

    case 'indepvar':
      return variables
        .filter(v => v.name.toLowerCase().startsWith(lowerPartial))
        .map(v => ({
          text: v.name,
          label: `${v.name}  ${v.inferred_type || v.type || ''}`,
          description: v.missing_count ? `缺失: ${v.missing_count}` : '',
          kind: 'variable' as const,
          priority: 5,
        }))
        .sort((a, b) => a.text.localeCompare(b.text));

    case 'option': {
      if (!context.grammar) return [];
      const optNode = context.grammar.syntax.find(n => n.kind === 'option');
      if (!optNode?.children) return [];
      return Object.entries(optNode.children)
        .filter(([name]) => name.toLowerCase().startsWith(lowerPartial))
        .map(([name, node]) => ({
          text: name,
          label: name,
          description: node.label,
          kind: 'option' as const,
          priority: node.required ? 10 : 5,
        }))
        .sort((a, b) => b.priority - a.priority);
    }

    case 'option_value': {
      const optName = context.optionName;

      // Enumerated values (like method values) — requires grammar
      if (context.grammar) {
        const optNode = context.grammar.syntax.find(n => n.kind === 'option');
        const child = optNode?.children?.[optName || ''];
        if (child?.values) {
          return child.values
            .filter(v => v.toLowerCase().startsWith(lowerPartial))
            .map(v => ({
              text: v,
              label: v,
              description: child.label || '',
              kind: 'value' as const,
              priority: 5,
            }));
        }
      }

      // Variable-type option values (cluster, id, time, strata, psu, fpc, endogenous, instruments)
      const categoricalFirst = ['cluster', 'id', 'strata', 'psu', 'fpc'].includes(optName || '');
      return variables
        .filter(v => v.name.toLowerCase().startsWith(lowerPartial))
        .map(v => ({
          text: v.name,
          label: v.name,
          description: categoricalFirst && v.inferred_type !== 'continuous'
            ? '分类变量优先' : '',
          kind: 'variable' as const,
          priority: categoricalFirst && v.inferred_type !== 'continuous' ? 10 : 5,
        }))
        .sort((a, b) => b.priority - a.priority || a.text.localeCompare(b.text));
    }

    default:
      return [];
  }
}

// --- Error Correction ---

function levenshtein(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  if (m === 0) return n;
  if (n === 0) return m;

  // Use single-row DP for efficiency
  let prev = Array.from({ length: n + 1 }, (_, i) => i);
  for (let i = 1; i <= m; i++) {
    const curr = [i];
    for (let j = 1; j <= n; j++) {
      curr[j] = a[i - 1] === b[j - 1]
        ? prev[j - 1]
        : 1 + Math.min(prev[j], curr[j - 1], prev[j - 1]);
    }
    prev = curr;
  }
  return prev[n];
}

export function getCorrections(
  partial: string,
  variables: ColumnSummary[],
  maxDistance: number = 3,
): CompletionItem[] {
  const lowerPartial = partial.toLowerCase();
  return variables
    .map(v => ({
      variable: v,
      distance: levenshtein(lowerPartial, v.name.toLowerCase()),
    }))
    .filter(({ distance, variable }) =>
      distance > 0 && distance <= maxDistance && variable.name.length >= 2
    )
    .sort((a, b) => a.distance - b.distance)
    .slice(0, 3)
    .map(({ variable, distance }) => ({
      text: variable.name,
      label: variable.name,
      description: `编辑距离: ${distance}`,
      kind: 'variable' as const,
      priority: 10 - distance,
    }));
}

// --- Ghost Text ---

export function getGhostText(
  context: AutocompleteContext,
  variables: ColumnSummary[],
  input: string,
  cursorPos: number,
): string | null {
  const partial = getPartial(input, cursorPos);
  if (partial.length === 0) return null;

  const completions = getCompletions(context, variables, partial);
  if (completions.length === 0) return null;

  const top = completions[0];
  if (top.text === partial || top.text.toLowerCase() === partial.toLowerCase()) return null;

  // Return the remainder of the top completion after the partial
  const remainder = top.text.slice(partial.length);
  return remainder || null;
}
