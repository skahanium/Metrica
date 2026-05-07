# Metrica 前端 CLI 重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Metrica 前端从"表单+Tab"混杂交互重构为"变量原语+常驻命令行+结果流"的纯粹交互范式。

**Architecture:** 新增命令系统（grammar/parser/autocomplete）作为核心引擎，CommandLine 组件替代 ModelForm 成为唯一建模入口，ResultFlow 替代 Tab 系统成为结果展示层。数据操作保留双通道（CLI + 可视化）。现有 runtimeClient API 和 Zustand store 体系复用而非重写。

**Tech Stack:** React 19 + TypeScript 5 + Zustand 5 + Ant Design 5 + AG Grid 33 + ECharts 5 + Vite 6

**设计文档:** `docs/superpowers/specs/2026-05-06-metrica-interaction-purity-design.md`

---

## 文件结构

```
src-react/
  services/
    commandGrammar.ts    ← NEW: 命令语法树定义 (所有命令动词的语法树)
    commandParser.ts     ← NEW: Tokenizer + Parser → ParsedCommand
    autocomplete.ts      ← NEW: 上下文补全引擎 + 幽灵文本 + 纠错
    runtimeClient.ts     ← MODIFY: 无 API 变更，仅可能调整调用方
  stores/
    commandStore.ts      ← NEW: 命令历史、补全状态、解析结果
    appStore.ts          ← MODIFY: -activeTab, +teachingEnabled, +dataFullscreen
    datasetStore.ts      ← MODIFY: +selectedColumn
    modelStore.ts        ← MODIFY: 简化，保留 lastResult/modelHistory/buildModelSpec
  components/
    CommandLine.tsx       ← NEW: 底部常驻命令输入 + 补全菜单 + 幽灵文本
    ResultFlow.tsx        ← NEW: 结果流容器 (向上滚动)
    ResultBlock.tsx       ← NEW: 单个结果块 (命令 + glance/系数/诊断/教学)
    TeachingLayer.tsx     ← NEW: 教学解释卡片
    DataFullscreen.tsx    ← NEW: 数据全屏视图
    VariableCard.tsx      ← NEW: 变量缩略卡片 (侧边栏用)
    App.tsx               ← MODIFY: 新布局 (侧边栏|结果流|命令行)
    Header.tsx            ← MODIFY: 移除 "运行模型" 按钮
    Sidebar.tsx           ← MODIFY: 变量卡片替换简单列表
    ModelForm.tsx         ← DELETE: 命令行替代
  __tests__/
    commandParser.test.ts ← NEW
    autocomplete.test.ts  ← NEW
    commandStore.test.ts  ← NEW
    CommandLine.test.tsx  ← NEW
    ResultFlow.test.tsx   ← NEW
```

---

## Phase 1: 命令系统引擎 (无 UI)

### Task 1: 命令语法树定义

**Files:**
- Create: `apps/metrica-desktop/src-react/services/commandGrammar.ts`

- [ ] **Step 1: 定义 CommandNode 类型和所有命令的语法树**

```typescript
// services/commandGrammar.ts

export type NodeKind = 'verb' | 'depvar' | 'indepvar' | 'comma' | 'option' | 'option_value';

export interface SyntaxNode {
  kind: NodeKind;
  label: string;          // 显示名，如 "因变量" / "自变量" / "选项"
  required: boolean;
  multiple: boolean;      // 可多个 (如自变量)
  children?: Record<string, SyntaxNode>; // 仅 option 节点有 children
  values?: string[];      // 仅枚举型 option_value 有 (如 method: fe|re|fd)
}

export interface CommandGrammar {
  verb: string;
  description: string;    // 中文描述
  category: string;       // 'data' | 'model' | 'diagnostic' | 'postest' | 'project' | 'export'
  syntax: SyntaxNode[];   // 语法树 (顺序敏感)
}

// 示例: regress 语法树
const REGRESS_GRAMMAR: CommandGrammar = {
  verb: 'regress',
  description: '线性回归 (OLS/WLS)',
  category: 'model',
  syntax: [
    { kind: 'depvar', label: '因变量', required: true, multiple: false },
    { kind: 'indepvar', label: '自变量', required: true, multiple: true },
    { kind: 'comma', label: ',', required: false, multiple: false },
    {
      kind: 'option', label: '选项', required: false, multiple: true,
      children: {
        robust:     { kind: 'option_value', label: 'robust', required: false, multiple: false, values: ['true'] },
        cluster:    { kind: 'option_value', label: 'cluster', required: false, multiple: false },
        noconstant: { kind: 'option_value', label: 'noconstant', required: false, multiple: false, values: ['true'] },
      },
    },
  ],
};
```

- [ ] **Step 2: 定义所有命令语法树**

实现全部命令的 `COMMAND_GRAMMARS: Record<string, CommandGrammar>`，覆盖设计文档命令表中所有命令。

- [ ] **Step 3: 写单元测试**

```typescript
// __tests__/commandGrammar.test.ts
import { describe, it, expect } from 'vitest';
import { getGrammar } from '../services/commandGrammar';

describe('commandGrammar', () => {
  it('returns regress grammar', () => {
    const g = getGrammar('regress');
    expect(g.verb).toBe('regress');
    expect(g.syntax[0].kind).toBe('depvar');
  });

  it('returns undefined for unknown verb', () => {
    expect(getGrammar('nonexistent')).toBeUndefined();
  });

  it('all model commands have depvar as first syntax node', () => {
    const modelVerbs = ['regress', 'ivregress', 'gls', 'xtreg', 'logit', 'probit',
      'poisson', 'ologit', 'mlogit', 'nbreg', 'did', 'eventstudy'];
    for (const verb of modelVerbs) {
      const g = getGrammar(verb);
      expect(g!.syntax[0].kind).toBe('depvar');
    }
  });
});
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd apps/metrica-desktop && npx vitest run __tests__/commandGrammar.test.ts
```

- [ ] **Step 5: 提交**

```bash
git add apps/metrica-desktop/src-react/services/commandGrammar.ts \
        apps/metrica-desktop/src-react/__tests__/commandGrammar.test.ts
git commit -m "feat: 添加命令语法树定义"
```

---

### Task 2: 命令解析器

**Files:**
- Create: `apps/metrica-desktop/src-react/services/commandParser.ts`

- [ ] **Step 1: 定义 ParsedCommand 类型并实现 tokenize**

```typescript
// services/commandParser.ts

export interface ParsedOption {
  name: string;
  value?: string;  // undefined for bare options like 'robust'
}

export interface ParsedCommand {
  verb: string;
  positionals: string[];    // 逗号前的所有 token
  options: ParsedOption[];  // 逗号后的键值对
  error?: string;           // 语法错误信息
}

export function tokenize(input: string): string[] {
  // 按空格分割，保留引号内字符串
  const tokens: string[] = [];
  let current = '';
  let inQuote = false;
  let quoteChar = '';
  for (const ch of input) {
    if (!inQuote && (ch === '"' || ch === "'")) {
      inQuote = true;
      quoteChar = ch;
      current += ch;
    } else if (inQuote && ch === quoteChar) {
      inQuote = false;
      current += ch;
    } else if (!inQuote && ch === ' ') {
      if (current) { tokens.push(current); current = ''; }
    } else {
      current += ch;
    }
  }
  if (current) tokens.push(current);
  return tokens;
}
```

- [ ] **Step 2: 实现 parse 函数**

```typescript
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

  const positionals = commaIdx === -1 ? rest : rest.slice(0, commaIdx);

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
```

- [ ] **Step 3: 实现 parseToModelSpec 函数 (关键)**

```typescript
import type { ModelSpec } from '../types/protocol';

export function parseToModelSpec(parsed: ParsedCommand): ModelSpec | { error: string } {
  const { verb, positionals, options, error } = parsed;
  if (error) return { error };

  const optMap = new Map(options.map(o => [o.name, o.value]));

  const base: ModelSpec = {
    model_type: verbToModelType(verb),
    formula: positionals.length >= 2
      ? `${positionals[0]} ~ ${positionals.slice(1).join(' + ')}`
      : positionals[0] || '',
  };

  // 选项映射
  if (optMap.has('robust')) base.vcov = 'hc1';
  if (optMap.has('cluster')) base.cluster_column = optMap.get('cluster');
  if (optMap.has('weights')) base.weights = optMap.get('weights');
  if (optMap.has('noconstant')) base.formula += ' - 1';

  // 面板
  if (optMap.has('id')) base.panel_id = optMap.get('id');
  if (optMap.has('time')) base.panel_time = optMap.get('time');
  if (optMap.has('method')) base.panel_method = optMap.get('method') as ModelSpec['panel_method'];

  // IV
  if (optMap.has('endogenous')) base.endog_columns = optMap.get('endogenous')!.split(/\s+/);
  if (optMap.has('instruments')) base.instruments = optMap.get('instruments')!.split(/\s+/);

  // 因果推断
  if (optMap.has('treat')) base.treatment_column = optMap.get('treat');
  if (optMap.has('post')) base.post_column = optMap.get('post');
  if (optMap.has('eventtime')) base.event_time_column = optMap.get('eventtime');
  if (optMap.has('outcome')) base.outcome_column = optMap.get('outcome');

  // 时间序列
  if (optMap.has('ar')) base.order_p = parseInt(optMap.get('ar')!);
  if (optMap.has('i')) base.order_d = parseInt(optMap.get('i')!);
  if (optMap.has('ma')) base.order_q = parseInt(optMap.get('ma')!);
  if (optMap.has('lags')) base.ts_lags = parseInt(optMap.get('lags')!);

  // 调查
  if (optMap.has('strata')) base.strata_column = optMap.get('strata');
  if (optMap.has('psu')) base.psu_column = optMap.get('psu');
  if (optMap.has('fpc')) base.fpc_column = optMap.get('fpc');

  return base;
}

function verbToModelType(verb: string): string {
  const map: Record<string, string> = {
    regress: 'ols', ivregress: 'iv', gls: 'gls',
    xtreg: 'panel', xtivreg: 'panel',
    logit: 'logit', probit: 'probit', poisson: 'poisson',
    ologit: 'ordered_logit', mlogit: 'multinomial_logit', nbreg: 'negbin',
    did: 'did', eventstudy: 'event_study', ipw: 'ipw', psm: 'psm', aipw: 'aipw',
    arima: 'arima', var: 'var', dfuller: 'unitroot', coint: 'cointegration',
  };
  return map[verb] || verb;
}
```

- [ ] **Step 4: 写单元测试**

```typescript
// __tests__/commandParser.test.ts
describe('commandParser', () => {
  describe('tokenize', () => {
    it('splits by spaces', () => {
      expect(tokenize('regress y x1 x2')).toEqual(['regress', 'y', 'x1', 'x2']);
    });
    it('preserves quoted strings', () => {
      expect(tokenize('use "path/to data.csv"')).toEqual(['use', '"path/to data.csv"']);
    });
  });

  describe('parse', () => {
    it('parses simple regress', () => {
      const r = parse('regress gdp inflation year');
      expect(r.verb).toBe('regress');
      expect(r.positionals).toEqual(['gdp', 'inflation', 'year']);
      expect(r.options).toEqual([]);
    });

    it('parses regress with options', () => {
      const r = parse('regress gdp inflation, robust');
      expect(r.positionals).toEqual(['gdp', 'inflation']);
      expect(r.options).toEqual([{ name: 'robust' }]);
    });

    it('parses key-value options', () => {
      const r = parse('regress gdp inflation, cluster(region)');
      expect(r.options).toEqual([{ name: 'cluster', value: 'region' }]);
    });

    it('returns error for unknown verb', () => {
      const r = parse('unknown_cmd x y');
      expect(r.error).toBeDefined();
    });
  });

  describe('parseToModelSpec', () => {
    it('converts regress to ols ModelSpec', () => {
      const r = parse('regress gdp inflation year, robust');
      const spec = parseToModelSpec(r);
      expect(spec).not.toHaveProperty('error');
      if (!('error' in spec)) {
        expect(spec.model_type).toBe('ols');
        expect(spec.formula).toBe('gdp ~ inflation + year');
        expect(spec.vcov).toBe('hc1');
      }
    });

    it('converts xtreg to panel ModelSpec', () => {
      const r = parse('xtreg gdp capital labor, id(country) time(year) method(fe)');
      const spec = parseToModelSpec(r);
      if (!('error' in spec)) {
        expect(spec.model_type).toBe('panel');
        expect(spec.panel_id).toBe('country');
        expect(spec.panel_time).toBe('year');
        expect(spec.panel_method).toBe('fe');
      }
    });
  });
});
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd apps/metrica-desktop && npx vitest run __tests__/commandParser.test.ts
```

- [ ] **Step 6: 提交**

```bash
git add apps/metrica-desktop/src-react/services/commandParser.ts \
        apps/metrica-desktop/src-react/__tests__/commandParser.test.ts
git commit -m "feat: 实现命令解析器 (tokenize + parse + parseToModelSpec)"
```

---

### Task 3: 自动补全引擎

**Files:**
- Create: `apps/metrica-desktop/src-react/services/autocomplete.ts`

- [ ] **Step 1: 实现光标上下文检测**

```typescript
// services/autocomplete.ts

import { getGrammar, type SyntaxNode, type CommandGrammar } from './commandGrammar';
import type { ColumnSummary } from '../types/protocol';

export interface CompletionItem {
  text: string;
  label: string;        // 显示文本
  description: string;  // 中文说明
  kind: 'verb' | 'variable' | 'option' | 'value';
  priority: number;     // 排序权重 (越高越前)
}

export interface AutocompleteContext {
  kind: 'verb' | 'depvar' | 'indepvar' | 'option' | 'option_value';
  optionName?: string;  // 当前在哪个选项的括号内
  grammar?: CommandGrammar;
}

export function getContext(input: string, cursorPos: number): AutocompleteContext {
  const beforeCursor = input.slice(0, cursorPos);
  const tokens = beforeCursor.trim().split(/\s+/);
  const hasComma = beforeCursor.includes(',');

  // 第一个 token → 命令动词
  if (tokens.length === 0 || (tokens.length === 1 && !hasComma)) {
    return { kind: 'verb' };
  }

  const verb = tokens[0].toLowerCase();
  const grammar = getGrammar(verb);

  // 逗号之后 → 选项区
  if (hasComma) {
    const afterComma = beforeCursor.slice(beforeCursor.indexOf(',') + 1);
    // 检测是否在括号内
    const parenMatch = afterComma.match(/(\w+)\(([^)]*)$/);
    if (parenMatch) {
      return { kind: 'option_value', optionName: parenMatch[1], grammar };
    }
    return { kind: 'option', grammar };
  }

  // 逗号之前 → 位置参数区
  if (!grammar) return { kind: 'verb' };

  // 语法树第一项是 depvar → 第一个位置参数是因变量
  if (grammar.syntax[0]?.kind === 'depvar' && tokens.length === 1) {
    return { kind: 'depvar', grammar };
  }
  return { kind: 'indepvar', grammar };
}
```

- [ ] **Step 2: 实现补全项生成**

```typescript
export function getCompletions(
  context: AutocompleteContext,
  variables: ColumnSummary[],
  partial: string,
  allVerbs: string[],
): CompletionItem[] {
  switch (context.kind) {
    case 'verb':
      return allVerbs
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
        .filter(c => c.text.startsWith(partial.toLowerCase()))
        .sort((a, b) => a.text.length - b.text.length);

    case 'depvar':
      return variables
        .filter(v => v.name.toLowerCase().startsWith(partial.toLowerCase()))
        .map(v => ({
          text: v.name,
          label: `${v.name}  ${v.inferred_type || v.type || '?'}`,
          description: v.inferred_type === 'continuous' || v.type === 'Float64'
            ? '常用作因变量' : '',
          kind: 'variable' as const,
          priority: (v.inferred_type === 'continuous' || v.type === 'Float64') ? 10 : 5,
        }))
        .sort((a, b) => b.priority - a.priority);

    case 'indepvar':
      return variables
        .filter(v => v.name.toLowerCase().startsWith(partial.toLowerCase()))
        .map(v => ({
          text: v.name,
          label: `${v.name}  ${v.inferred_type || v.type || '?'}`,
          description: v.missing_count ? `缺失: ${v.missing_count}` : '',
          kind: 'variable' as const,
          priority: 5,
        }))
        .sort((a, b) => a.text.localeCompare(b.text));

    case 'option':
      if (!context.grammar) return [];
      return Object.entries(context.grammar.syntax
        .find(n => n.kind === 'option')?.children || {})
        .filter(([name]) => name.toLowerCase().startsWith(partial.toLowerCase()))
        .map(([name, node]) => ({
          text: name,
          label: name,
          description: node.label,
          kind: 'option' as const,
          priority: node.required ? 10 : 5,
        }))
        .sort((a, b) => b.priority - a.priority);

    case 'option_value':
      // 在括号内：cluster(id) / method(fe) / endogenous()
      if (context.optionName === 'method') {
        return (context.grammar?.syntax
          .find(n => n.kind === 'option')?.children?.method?.values || [])
          .filter(v => v.startsWith(partial.toLowerCase()))
          .map(v => ({ text: v, label: v, description: '', kind: 'value' as const, priority: 5 }));
      }
      // cluster/endogenous/instruments/id/time → 补全变量
      return variables
        .filter(v => v.name.toLowerCase().startsWith(partial.toLowerCase()))
        .map(v => ({
          text: v.name,
          label: v.name,
          description: context.optionName === 'cluster' || context.optionName === 'id'
            ? '分类变量优先' : '',
          kind: 'variable' as const,
          priority: (v.inferred_type !== 'continuous') ? 10 : 5,
        }))
        .sort((a, b) => b.priority - a.priority);

    default:
      return [];
  }
}
```

- [ ] **Step 3: 实现纠错建议**

```typescript
export function getCorrections(
  partial: string,
  variables: ColumnSummary[],
  maxDistance: number = 3,
): CompletionItem[] {
  return variables
    .map(v => {
      const d = levenshtein(partial.toLowerCase(), v.name.toLowerCase());
      return { ...v, distance: d };
    })
    .filter(v => v.distance > 0 && v.distance <= maxDistance)
    .sort((a, b) => a.distance - b.distance)
    .map(v => ({
      text: v.name,
      label: v.name,
      description: `编辑距离: ${v.distance}`,
      kind: 'variable' as const,
      priority: 10 - v.distance,
    }));
}

function levenshtein(a: string, b: string): number {
  const m = a.length, n = b.length;
  const dp: number[][] = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }
  return dp[m][n];
}
```

- [ ] **Step 4: 实现幽灵文本生成**

```typescript
export function getGhostText(
  context: AutocompleteContext,
  variables: ColumnSummary[],
  input: string,
  cursorPos: number,
): string | null {
  const partial = input.slice(input.lastIndexOf(' ', cursorPos - 1) + 1, cursorPos).trim();
  const completions = getCompletions(context, variables, partial, []);
  if (completions.length === 0) return null;
  const top = completions[0];
  if (top.text === partial) return null; // 已完全匹配
  return top.text.slice(partial.length);
}
```

- [ ] **Step 5: 写单元测试**

```typescript
// __tests__/autocomplete.test.ts
describe('autocomplete', () => {
  const mockVars = [
    { name: 'gdp', type: 'Float64', inferred_type: 'continuous', missing_count: 0 },
    { name: 'inflation', type: 'Float64', inferred_type: 'continuous', missing_count: 2 },
    { name: 'year', type: 'Int64', inferred_type: 'discrete', missing_count: 0 },
    { name: 'region', type: 'String', inferred_type: 'categorical', missing_count: 0 },
  ];

  describe('getContext', () => {
    it('detects verb context at start', () => {
      expect(getContext('reg', 3).kind).toBe('verb');
    });
    it('detects depvar context', () => {
      expect(getContext('regress ', 8).kind).toBe('depvar');
    });
    it('detects option context after comma', () => {
      expect(getContext('regress y x, ', 13).kind).toBe('option');
    });
    it('detects option_value in parens', () => {
      expect(getContext('xtreg y x, id(', 13).kind).toBe('option_value');
    });
  });

  describe('getCompletions', () => {
    it('prioritizes continuous vars for depvar', () => {
      const ctx: AutocompleteContext = { kind: 'depvar' };
      const c = getCompletions(ctx, mockVars, '', []);
      expect(c[0].text).toBe('gdp'); // continuous, higher priority
    });

    it('filters by partial', () => {
      const ctx: AutocompleteContext = { kind: 'indepvar' };
      const c = getCompletions(ctx, mockVars, 'inf', []);
      expect(c).toHaveLength(1);
      expect(c[0].text).toBe('inflation');
    });
  });

  describe('getCorrections', () => {
    it('suggests close matches', () => {
      const c = getCorrections('inflaton', mockVars);
      expect(c).toHaveLength(1);
      expect(c[0].text).toBe('inflation');
    });
  });
});
```

- [ ] **Step 6: 运行测试确认通过**

```bash
cd apps/metrica-desktop && npx vitest run __tests__/autocomplete.test.ts
```

- [ ] **Step 7: 提交**

```bash
git add apps/metrica-desktop/src-react/services/autocomplete.ts \
        apps/metrica-desktop/src-react/__tests__/autocomplete.test.ts
git commit -m "feat: 实现基于语法树的自动补全引擎"
```

---

### Task 4: 命令状态 Store

**Files:**
- Create: `apps/metrica-desktop/src-react/stores/commandStore.ts`

- [ ] **Step 1: 实现 commandStore**

```typescript
// stores/commandStore.ts
import { create } from 'zustand';
import type { ParsedCommand } from '../services/commandParser';
import type { CompletionItem, AutocompleteContext } from '../services/autocomplete';

interface CommandState {
  // 当前输入
  input: string;
  cursorPos: number;

  // 补全状态
  context: AutocompleteContext | null;
  completions: CompletionItem[];
  selectedCompletionIdx: number;
  ghostText: string | null;
  showCompletions: boolean;

  // 纠错
  correction: string | null;

  // 历史
  history: string[];
  historyIdx: number;  // -1 = 不在历史浏览

  // 解析结果
  lastParsed: ParsedCommand | null;
  parseError: string | null;

  // 动作
  setInput: (input: string, cursorPos: number) => void;
  setCompletions: (completions: CompletionItem[], context: AutocompleteContext) => void;
  setGhostText: (text: string | null) => void;
  setCorrection: (correction: string | null) => void;
  acceptCompletion: () => string | null;
  selectNextCompletion: () => void;
  selectPrevCompletion: () => void;
  hideCompletions: () => void;
  addToHistory: (cmd: string) => void;
  navigateHistoryUp: () => string | null;
  navigateHistoryDown: () => string | null;
  setLastParsed: (parsed: ParsedCommand | null, error: string | null) => void;
}

export const useCommandStore = create<CommandState>((set, get) => ({
  input: '',
  cursorPos: 0,
  context: null,
  completions: [],
  selectedCompletionIdx: 0,
  ghostText: null,
  showCompletions: false,
  correction: null,
  history: [],
  historyIdx: -1,
  lastParsed: null,
  parseError: null,

  setInput: (input, cursorPos) => set({ input, cursorPos, correction: null }),

  setCompletions: (completions, context) => set({
    completions,
    context,
    selectedCompletionIdx: 0,
    showCompletions: completions.length > 0,
  }),

  setGhostText: (ghostText) => set({ ghostText }),

  setCorrection: (correction) => set({ correction }),

  acceptCompletion: () => {
    const { completions, selectedCompletionIdx } = get();
    if (completions.length === 0) return null;
    const item = completions[Math.min(selectedCompletionIdx, completions.length - 1)];
    set({ showCompletions: false, ghostText: null });
    return item.text;
  },

  selectNextCompletion: () => set(s => ({
    selectedCompletionIdx: Math.min(s.selectedCompletionIdx + 1, s.completions.length - 1),
  })),

  selectPrevCompletion: () => set(s => ({
    selectedCompletionIdx: Math.max(s.selectedCompletionIdx - 1, 0),
  })),

  hideCompletions: () => set({ showCompletions: false }),

  addToHistory: (cmd) => set(s => ({
    history: [cmd, ...s.history].slice(0, 100),
    historyIdx: -1,
  })),

  navigateHistoryUp: () => {
    const { history, historyIdx } = get();
    const newIdx = Math.min(historyIdx + 1, history.length - 1);
    set({ historyIdx: newIdx });
    return newIdx >= 0 ? history[newIdx] : null;
  },

  navigateHistoryDown: () => {
    const { history, historyIdx } = get();
    const newIdx = Math.max(historyIdx - 1, -1);
    set({ historyIdx: newIdx });
    return newIdx >= 0 ? get().history[newIdx] : '';
  },

  setLastParsed: (lastParsed, parseError) => set({ lastParsed, parseError }),
}));
```

- [ ] **Step 2: 写单元测试**

```typescript
// __tests__/commandStore.test.ts
describe('commandStore', () => {
  it('manages history correctly', () => {
    const { addToHistory, navigateHistoryUp, navigateHistoryDown } = useCommandStore.getState();
    addToHistory('regress y x');
    addToHistory('summarize y');
    expect(navigateHistoryUp()).toBe('summarize y');
    expect(navigateHistoryUp()).toBe('regress y x');
    expect(navigateHistoryDown()).toBe('summarize y');
  });

  it('cycles completions', () => {
    useCommandStore.setState({
      completions: [{ text: 'a', label: 'a', description: '', kind: 'verb', priority: 5 }],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });
    const { acceptCompletion } = useCommandStore.getState();
    expect(acceptCompletion()).toBe('a');
    expect(useCommandStore.getState().showCompletions).toBe(false);
  });
});
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd apps/metrica-desktop && npx vitest run __tests__/commandStore.test.ts
```

- [ ] **Step 4: 提交**

```bash
git add apps/metrica-desktop/src-react/stores/commandStore.ts \
        apps/metrica-desktop/src-react/__tests__/commandStore.test.ts
git commit -m "feat: 添加命令状态 Store"
```

---

## Phase 2: CLI 界面

### Task 5: CommandLine 组件

**Files:**
- Create: `apps/metrica-desktop/src-react/components/CommandLine.tsx`

- [ ] **Step 1: 实现 CommandLine 组件**

```tsx
// components/CommandLine.tsx
import React, { useRef, useEffect, useCallback } from 'react';
import { Input } from 'antd';
import { useCommandStore } from '../stores/commandStore';
import { getContext, getCompletions, getCorrections, getGhostText } from '../services/autocomplete';
import { parse } from '../services/commandParser';
import { useDatasetStore } from '../stores/datasetStore';
import { COMMAND_LIST } from '../services/commandGrammar';
import type { CompletionItem } from '../services/autocomplete';

interface CommandLineProps {
  onExecute: (input: string) => void;
}

export const CommandLine: React.FC<CommandLineProps> = ({ onExecute }) => {
  const inputRef = useRef<any>(null);
  const {
    input, setInput, completions, showCompletions, selectedCompletionIdx, ghostText,
    correction, hideCompletions, acceptCompletion, selectNextCompletion, selectPrevCompletion,
    addToHistory, navigateHistoryUp, navigateHistoryDown, setCompletions, setGhostText,
    setCorrection,
  } = useCommandStore();

  const variables = useDatasetStore(s => s.summary?.columns || []);

  // 实时更新补全
  const updateCompletions = useCallback((value: string, cursorPos: number) => {
    const ctx = getContext(value, cursorPos);
    const partial = value.slice(value.lastIndexOf(' ', cursorPos - 1) + 1, cursorPos).trim();
    let items = getCompletions(ctx, variables, partial, COMMAND_LIST);

    // 无结果 → 尝试纠错
    if (items.length === 0 && ctx.kind !== 'verb' && partial.length >= 3) {
      const corrections = getCorrections(partial, variables);
      if (corrections.length > 0) {
        setCorrection(corrections[0].text); // 设置纠错提示
        items = corrections;
      }
    }

    setCompletions(items, ctx);

    // 幽灵文本
    const ghost = getGhostText(ctx, variables, value, cursorPos);
    setGhostText(ghost);
  }, [variables, setCompletions, setGhostText, setCorrection]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setInput(value, e.target.selectionStart || 0);
    updateCompletions(value, e.target.selectionStart || 0);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (showCompletions) {
      if (e.key === 'ArrowDown') { e.preventDefault(); selectNextCompletion(); return; }
      if (e.key === 'ArrowUp') { e.preventDefault(); selectPrevCompletion(); return; }
      if (e.key === 'Tab') {
        e.preventDefault();
        const text = acceptCompletion();
        if (text) {
          const newInput = input + text;
          setInput(newInput, newInput.length);
          hideCompletions();
        }
        return;
      }
      if (e.key === 'Escape') { e.preventDefault(); hideCompletions(); return; }
    }

    // 幽灵文本接受
    if (e.key === 'Tab' && ghostText && !showCompletions) {
      e.preventDefault();
      const newInput = input + ghostText;
      setInput(newInput, newInput.length);
      updateCompletions(newInput, newInput.length);
      return;
    }

    // 历史浏览
    if (e.key === 'ArrowUp' && input === '' || (e.key === 'ArrowUp' && !showCompletions)) {
      if (input === '') {
        e.preventDefault();
        const hist = navigateHistoryUp();
        if (hist) setInput(hist, hist.length);
        return;
      }
    }

    // 提交
    if (e.key === 'Enter' && !showCompletions) {
      e.preventDefault();
      const trimmed = input.trim();
      if (trimmed) {
        addToHistory(trimmed);
        onExecute(trimmed);
        setInput('', 0);
      }
    }
  };

  // 自动聚焦
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  return (
    <div style={{ position: 'relative', padding: '8px 16px', borderTop: '1px solid #f0f0f0', background: '#fafafa' }}>
      {/* 补全菜单 */}
      {showCompletions && (
        <div style={{
          position: 'absolute', bottom: '100%', left: 16, right: 16,
          background: '#fff', border: '1px solid #d9d9d9', borderRadius: 6,
          maxHeight: 200, overflow: 'auto', zIndex: 1000, boxShadow: '0 2px 8px rgba(0,0,0,0.1)',
          marginBottom: 4,
        }}>
          {correction && (
            <div style={{ padding: '4px 12px', fontSize: 12, color: '#999' }}>
              未找到。你的意思是？
            </div>
          )}
          {completions.map((item, idx) => (
            <div key={item.text} style={{
              padding: '6px 12px', cursor: 'pointer',
              background: idx === selectedCompletionIdx ? '#e6f4ff' : 'transparent',
              display: 'flex', justifyContent: 'space-between',
            }}>
              <span style={{ fontWeight: 500 }}>{item.text}</span>
              <span style={{ color: '#999', fontSize: 12 }}>{item.description}</span>
            </div>
          ))}
        </div>
      )}

      {/* 命令行: 幽灵文本叠加 */}
      <div style={{ position: 'relative' }}>
        <Input
          ref={inputRef}
          prefix={<span style={{ color: '#1677ff', fontWeight: 600 }}>&gt;</span>}
          placeholder="输入命令... (regress / summarize / describe / ...)"
          value={input}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          onBlur={() => setTimeout(hideCompletions, 200)}
          variant="borderless"
          style={{ fontFamily: 'monospace', fontSize: 14 }}
        />
        {ghostText && !showCompletions && (
          <span style={{
            position: 'absolute', left: 24, top: '50%', transform: 'translateY(-50%)',
            color: '#bfbfbf', fontFamily: 'monospace', fontSize: 14, pointerEvents: 'none',
          }}>
            {input}{ghostText}
          </span>
        )}
      </div>

      <div style={{ fontSize: 11, color: '#bbb', marginTop: 2, paddingLeft: 24 }}>
        Tab 补全 | ↑↓ 浏览 | Enter 执行 | Esc 关闭菜单
      </div>
    </div>
  );
};
```

- [ ] **Step 2: 写组件测试**

```typescript
// __tests__/CommandLine.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CommandLine } from '../components/CommandLine';

describe('CommandLine', () => {
  it('renders command prompt', () => {
    render(<CommandLine onExecute={vi.fn()} />);
    expect(screen.getByPlaceholderText(/输入命令/)).toBeInTheDocument();
  });

  it('calls onExecute on Enter', async () => {
    const onExecute = vi.fn();
    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/);
    await userEvent.type(input, 'regress y x{Enter}');
    expect(onExecute).toHaveBeenCalledWith('regress y x');
  });
});
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd apps/metrica-desktop && npx vitest run __tests__/CommandLine.test.tsx
```

- [ ] **Step 4: 提交**

```bash
git add apps/metrica-desktop/src-react/components/CommandLine.tsx \
        apps/metrica-desktop/src-react/__tests__/CommandLine.test.tsx
git commit -m "feat: 实现常驻命令行组件 (补全菜单 + 幽灵文本 + 历史)"
```

---

## Phase 3: 结果流

### Task 6: TeachingLayer 组件

**Files:**
- Create: `apps/metrica-desktop/src-react/components/TeachingLayer.tsx`

- [ ] **Step 1: 实现 TeachingLayer**

```tsx
// components/TeachingLayer.tsx
import React, { useState } from 'react';
import { Collapse, Typography, Tag, Button } from 'antd';
import { CaretRightOutlined } from '@ant-design/icons';
import type { ModelResult } from '../types/protocol';

const { Text, Paragraph } = Typography;

interface TeachingLayerProps {
  result: ModelResult;
  collapsed?: boolean;
}

export const TeachingLayer: React.FC<TeachingLayerProps> = ({ result, collapsed = false }) => {
  const [isCollapsed, setIsCollapsed] = useState(collapsed);
  const notes = (result as any).teaching_notes; // Julia 后端生成

  if (!notes) return null;

  return (
    <div style={{ marginBottom: 12 }}>
      <Button
        type="link"
        size="small"
        onClick={() => setIsCollapsed(!isCollapsed)}
        style={{ padding: 0, fontSize: 12 }}
      >
        📖 {isCollapsed ? '显示教学解读' : '收起教学解读'}
      </Button>
      {!isCollapsed && (
        <div style={{
          padding: '12px 16px', background: '#f6ffed', borderRadius: 8,
          border: '1px solid #b7eb8f', marginTop: 8,
        }}>
          <Paragraph style={{ marginBottom: 4 }}>
            <Text strong>{notes.equation}</Text>
          </Paragraph>
          {notes.interpretations?.map((item: string, i: number) => (
            <Text key={i} style={{ display: 'block', fontSize: 13, marginBottom: 2 }}>
              {item}
            </Text>
          ))}
          {notes.next_steps && (
            <div style={{ marginTop: 8 }}>
              <Text type="secondary" style={{ fontSize: 12 }}>下一步建议：</Text>
              {notes.next_steps.map((step: string, i: number) => (
                <Tag key={i} color="blue" style={{ marginTop: 2 }}>{step}</Tag>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
};
```

- [ ] **Step 2: 运行现有测试确认无回归**

```bash
cd apps/metrica-desktop && npx vitest run
```

- [ ] **Step 3: 提交**

```bash
git add apps/metrica-desktop/src-react/components/TeachingLayer.tsx
git commit -m "feat: 添加教学层组件"
```

---

### Task 7: ResultBlock 组件

**Files:**
- Create: `apps/metrica-desktop/src-react/components/ResultBlock.tsx`

- [ ] **Step 1: 实现 ResultBlock**

```tsx
// components/ResultBlock.tsx
import React, { useState } from 'react';
import { Button, Space, Typography } from 'antd';
import { ReloadOutlined, CopyOutlined, ExpandOutlined } from '@ant-design/icons';
import { TeachingLayer } from './TeachingLayer';
import { GlanceTable } from './GlanceTable';
import { TidyTable } from './TidyTable';
import { DiagnosticCards } from './DiagnosticCards';
import { DiagnosticCharts } from './DiagnosticCharts';
import { DiscreteGlanceCards } from './DiscreteGlanceCards';
import { DIDResultCards } from './DIDResultCards';
import { TreatmentEffectSummary } from './TreatmentEffectSummary';
import { EventStudyPlot } from './EventStudyPlot';
import { BalanceTable } from './BalanceTable';
import { AugmentPreview } from './AugmentPreview';
import { ClassificationPreview } from './ClassificationPreview';
import type { ModelResult } from '../types/protocol';

const { Text } = Typography;

interface ResultBlockProps {
  command: string;
  result: ModelResult;
  teachingEnabled: boolean;
  onRerun: (command: string) => void;
  onCopy: (command: string) => void;
}

export const ResultBlock: React.FC<ResultBlockProps> = ({
  command, result, teachingEnabled, onRerun, onCopy,
}) => {
  const [expandedChart, setExpandedChart] = useState<string | null>(null);

  const modelType = result.glance?.model;

  return (
    <div style={{
      marginBottom: 16, background: '#fff', borderRadius: 8,
      border: '1px solid #f0f0f0', padding: 16,
    }}>
      {/* 命令头 */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <Text code style={{ fontSize: 13 }}>&gt; {command}</Text>
        <Space>
          <Button size="small" icon={<ReloadOutlined />} onClick={() => onRerun(command)} />
          <Button size="small" icon={<CopyOutlined />} onClick={() => onCopy(command)} />
        </Space>
      </div>

      {/* 教学层 */}
      {teachingEnabled && <TeachingLayer result={result} />}

      {/* Glance 卡片 */}
      {result.glance && <GlanceTable />}

      {/* 模型特定卡片 */}
      {modelType === 'logit' || modelType === 'probit' || modelType === 'poisson'
        || modelType === 'ordered_logit' || modelType === 'multinomial_logit' || modelType === 'negbin'
        ? <DiscreteGlanceCards />
        : null}
      {modelType === 'did' && <DIDResultCards />}
      {(modelType === 'ipw' || modelType === 'psm' || modelType === 'aipw') && <TreatmentEffectSummary />}

      {/* 系数表 */}
      {result.tidy && result.tidy.length > 0 && <TidyTable />}

      {/* 诊断 */}
      {result.diagnostics && (
        <>
          <DiagnosticCards />
          <DiagnosticCharts expanded={expandedChart} onExpand={setExpandedChart} />
        </>
      )}

      {/* 因果推断图 */}
      {modelType === 'event_study' && (
        <EventStudyPlot expanded={expandedChart === 'eventstudy'} onExpand={setExpandedChart} />
      )}
      {modelType === 'psm' && <BalanceTable />}

      {/* 拟合值 */}
      {result.augment_preview && result.augment_preview.length > 0 && (
        <>
          <AugmentPreview />
          {(modelType === 'logit' || modelType === 'probit') && <ClassificationPreview />}
        </>
      )}
    </div>
  );
};
```

- [ ] **Step 2: 提交**

```bash
git add apps/metrica-desktop/src-react/components/ResultBlock.tsx
git commit -m "feat: 添加结果块组件"
```

---

### Task 8: ResultFlow 组件

**Files:**
- Create: `apps/metrica-desktop/src-react/components/ResultFlow.tsx`

- [ ] **Step 1: 实现 ResultFlow**

```tsx
// components/ResultFlow.tsx
import React, { useRef, useEffect, useCallback } from 'react';
import { Empty } from 'antd';
import { useModelStore } from '../stores/modelStore';
import { useAppStore } from '../stores/appStore';
import { ResultBlock } from './ResultBlock';

interface ResultFlowProps {
  onRerun: (command: string) => void;
}

export const ResultFlow: React.FC<ResultFlowProps> = ({ onRerun }) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const modelHistory = useModelStore(s => s.modelHistory);
  const teachingEnabled = useAppStore(s => s.teachingEnabled);

  // 自动滚动到底部
  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [modelHistory.length]);

  const handleCopy = useCallback((cmd: string) => {
    navigator.clipboard.writeText(cmd);
  }, []);

  if (modelHistory.length === 0) {
    return (
      <div ref={containerRef} style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Empty description="尚无分析结果。在命令行输入 use 加载数据，然后输入 regress 等命令开始分析。" />
      </div>
    );
  }

  return (
    <div ref={containerRef} style={{
      flex: 1, overflow: 'auto', padding: 16,
    }}>
      {modelHistory.map((item) => (
        item.result && (
          <ResultBlock
            key={item.id}
            command={item.command || item.spec?.formula || ''}
            result={item.result}
            teachingEnabled={teachingEnabled}
            onRerun={onRerun}
            onCopy={handleCopy}
          />
        )
      ))}
    </div>
  );
};
```

- [ ] **Step 2: 提交**

```bash
git add apps/metrica-desktop/src-react/components/ResultFlow.tsx
git commit -m "feat: 添加结果流组件"
```

---

## Phase 4: 数据视图

### Task 9: DataFullscreen 组件

**Files:**
- Create: `apps/metrica-desktop/src-react/components/DataFullscreen.tsx`

- [ ] **Step 1: 实现 DataFullscreen**

```tsx
// components/DataFullscreen.tsx
import React, { useState, useMemo } from 'react';
import { Button, Space, Descriptions, Empty, Typography } from 'antd';
import { ArrowLeftOutlined, FilterOutlined, SwapOutlined, ExportOutlined } from '@ant-design/icons';
import { AgGridReact } from 'ag-grid-react';
import { useDatasetStore } from '../stores/datasetStore';
import { useAppStore } from '../stores/appStore';
import { ColDef } from 'ag-grid-community';

const { Text } = Typography;

export const DataFullscreen: React.FC = () => {
  const summary = useDatasetStore(s => s.summary);
  const setDataFullscreen = useAppStore(s => s.setDataFullscreen);
  const [selectedColumn, setSelectedColumn] = useState<string | null>(null);

  const columnDefs: ColDef[] = useMemo(() => {
    if (!summary) return [];
    return summary.columns.map((col, idx) => ({
      field: `col_${idx}`,
      headerName: col.name,
      sortable: true,
      filter: true,
      resizable: true,
      headerComponentParams: {
        onHeaderContextMenu: (e: MouseEvent) => {
          e.preventDefault();
          setSelectedColumn(col.name);
        },
      },
    }));
  }, [summary]);

  const rowData = useMemo(() => {
    if (!summary?.preview) return [];
    return summary.preview.map((row, i) => {
      const obj: Record<string, any> = { _idx: i + 1 };
      row.forEach((val, j) => { obj[`col_${j}`] = val; });
      return obj;
    });
  }, [summary]);

  if (!summary) {
    return <Empty description="未加载数据" />;
  }

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: 8 }}>
      {/* 工具栏 */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
        <Space>
          <Button icon={<ArrowLeftOutlined />} onClick={() => setDataFullscreen(false)}>
            返回结果
          </Button>
          <Text strong>{summary.nrows} obs × {summary.ncols} vars</Text>
        </Space>
        <Space>
          <Button icon={<FilterOutlined />}>筛选</Button>
          <Button icon={<SwapOutlined />}>变换</Button>
          <Button icon={<ExportOutlined />}>导出</Button>
        </Space>
      </div>

      {/* AG Grid 表格 */}
      <div style={{ flex: 1, overflow: 'auto' }}>
        <AgGridReact
          columnDefs={columnDefs}
          rowData={rowData}
          defaultColDef={{ flex: 1, minWidth: 100 }}
          suppressCellFocus
          onCellContextMenu={(e) => {
            if (e.colDef.field) {
              setSelectedColumn(summary.columns[parseInt(e.colDef.field.replace('col_', ''))]?.name || null);
            }
          }}
        />
      </div>

      {/* 选中列的统计卡片 */}
      {selectedColumn && (
        <ColumnStatsPanel
          columnName={selectedColumn}
          columns={summary.columns}
          onClose={() => setSelectedColumn(null)}
        />
      )}
    </div>
  );
};

// 列统计子组件
const ColumnStatsPanel: React.FC<{
  columnName: string;
  columns: any[];
  onClose: () => void;
}> = ({ columnName, columns, onClose }) => {
  const col = columns.find(c => c.name === columnName);
  if (!col) return null;

  return (
    <div style={{
      padding: 12, borderTop: '1px solid #f0f0f0', background: '#fafafa',
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
    }}>
      <Space>
        <Text strong>{col.name}</Text>
        <Text type="secondary">{col.inferred_type || col.type || '?'}</Text>
        {col.missing_count > 0 && (
          <Text type="warning">缺失: {col.missing_count} ({((col.missing_count / col.missing_count) * 100).toFixed(1)}%)</Text>
        )}
      </Space>
      <Button size="small" onClick={onClose}>关闭</Button>
    </div>
  );
};
```

- [ ] **Step 2: 提交**

```bash
git add apps/metrica-desktop/src-react/components/DataFullscreen.tsx
git commit -m "feat: 添加数据全屏视图组件"
```

---

### Task 10: VariableCard 组件 + Sidebar 改造

**Files:**
- Create: `apps/metrica-desktop/src-react/components/VariableCard.tsx`
- Modify: `apps/metrica-desktop/src-react/components/Sidebar.tsx`

- [ ] **Step 1: 实现 VariableCard**

```tsx
// components/VariableCard.tsx
import React from 'react';
import { Card, Typography, Tag, Space } from 'antd';
import type { ColumnSummary } from '../types/protocol';

const { Text } = Typography;

interface VariableCardProps {
  column: ColumnSummary;
  onClick: (name: string) => void;
}

export const VariableCard: React.FC<VariableCardProps> = ({ column, onClick }) => {
  const isContinuous = column.inferred_type === 'continuous' || column.type === 'Float64';

  return (
    <Card
      size="small"
      hoverable
      onClick={() => onClick(column.name)}
      style={{ marginBottom: 6, borderRadius: 6 }}
      bodyStyle={{ padding: '8px 12px' }}
    >
      <Space direction="vertical" size={2} style={{ width: '100%' }}>
        <Text strong style={{ fontSize: 13 }}>{column.name}</Text>
        <Space>
          <Tag color={isContinuous ? 'blue' : 'green'} style={{ fontSize: 10, lineHeight: '16px' }}>
            {column.inferred_type || column.type || '?'}
          </Tag>
          {column.missing_count ? (
            <Tag color="gold" style={{ fontSize: 10, lineHeight: '16px' }}>
              缺失 {column.missing_count}
            </Tag>
          ) : null}
        </Space>
      </Space>
    </Card>
  );
};
```

- [ ] **Step 2: 改造 Sidebar**

修改 `Sidebar.tsx`，用 `VariableCard` 替换原来的 `List.Item` 简单列表：

```tsx
// 原 Sidebar.tsx 底部变量列表部分改为：
<Input.Search placeholder="搜索变量..." allowClear style={{ marginBottom: 8 }} />
<div style={{ flex: 1, overflow: 'auto' }}>
  {(summary?.columns || []).map((col) => (
    <VariableCard
      key={col.name}
      column={col}
      onClick={(name) => {
        // 将变量名插入命令行
        const store = useCommandStore.getState();
        const newInput = store.input ? `${store.input} ${name}` : name;
        store.setInput(newInput, newInput.length);
      }}
    />
  ))}
</div>
```

- [ ] **Step 3: 提交**

```bash
git add apps/metrica-desktop/src-react/components/VariableCard.tsx \
        apps/metrica-desktop/src-react/components/Sidebar.tsx
git commit -m "feat: 变量卡片组件 + 侧边栏改造"
```

---

## Phase 5: 布局整合

### Task 11: App.tsx 布局重构

**Files:**
- Modify: `apps/metrica-desktop/src-react/components/App.tsx`
- Modify: `apps/metrica-desktop/src-react/stores/appStore.ts`
- Modify: `apps/metrica-desktop/src-react/components/Header.tsx`

- [ ] **Step 1: 更新 appStore**

```typescript
// stores/appStore.ts 变更:
// - 移除 activeTab, setActiveTab
// + 新增 teachingEnabled, setTeachingEnabled
// + 新增 dataFullscreen, setDataFullscreen

interface AppState {
  // ... 保留 isLoading, error, juliaHealthy, restartCount
  teachingEnabled: boolean;
  dataFullscreen: boolean;
  setTeachingEnabled: (v: boolean) => void;
  setDataFullscreen: (v: boolean) => void;
  // 移除: activeTab, setActiveTab
}
```

- [ ] **Step 2: 重构 App.tsx 布局**

```tsx
// components/App.tsx — 新布局
import React, { useCallback } from 'react';
import { ConfigProvider, Layout, theme } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { CommandLine } from './CommandLine';
import { ResultFlow } from './ResultFlow';
import { DataFullscreen } from './DataFullscreen';
import { useAppStore } from '../stores/appStore';
import { useModelStore } from '../stores/modelStore';
import { useDatasetStore } from '../stores/datasetStore';
import { parse, parseToModelSpec } from '../services/commandParser';
import { fitModel, inspectDataset } from '../services/runtimeClient';

const { Content, Sider } = Layout;

export function App() {
  const { isLoading, error, teachingEnabled, dataFullscreen, setLoading, setError } = useAppStore();
  const addToHistory = useModelStore(s => s.addToHistory);
  const setLastResult = useModelStore(s => s.setLastResult);
  const setSummary = useDatasetStore(s => s.setSummary);
  const activePath = useDatasetStore(s => s.activePath);

  const executeCommand = useCallback(async (input: string) => {
    const parsed = parse(input);
    if (parsed.error) {
      setError(parsed.error);
      return;
    }

    // 数据加载命令
    if (parsed.verb === 'use') {
      setLoading(true);
      try {
        const path = parsed.positionals[0]?.replace(/^"|"$/g, '');
        const result = await inspectDataset(path);
        setSummary(result);
        setError(null);
      } catch (e: any) {
        setError(e.message || '数据加载失败');
      } finally {
        setLoading(false);
      }
      return;
    }

    // 数据查看命令
    if (['describe', 'browse', 'summarize', 'tabulate'].includes(parsed.verb)) {
      // 这些是前端本地操作（基于已有 summary），或调用 describe API
      setLoading(true);
      try {
        const result = await fitModel({
          model_type: 'ols',
          formula: parsed.positionals.join(' ~ ') || '1 ~ 1',
          dataset_path: activePath,
          vcov: 'classical',
        });
        // 实际应调用专有 API，此处先走 fit_model 通量
        setLastResult(result);
        addToHistory({ id: crypto.randomUUID(), command: input, result, timestamp: Date.now() });
        setError(null);
      } catch (e: any) {
        setError(e.message || '命令执行失败');
      } finally {
        setLoading(false);
      }
      return;
    }

    // 建模命令
    const specOrError = parseToModelSpec(parsed);
    if ('error' in specOrError) {
      setError(specOrError.error);
      return;
    }

    setLoading(true);
    try {
      const result = await fitModel({
        ...specOrError,
        dataset_path: activePath,
      } as any);
      setLastResult(result);
      addToHistory({
        id: crypto.randomUUID(),
        command: input,
        spec: specOrError,
        result,
        timestamp: Date.now(),
      });
      setError(null);
    } catch (e: any) {
      setError(e.message || '模型拟合失败');
    } finally {
      setLoading(false);
    }
  }, [activePath, setLoading, setError, setLastResult, addToHistory, setSummary]);

  return (
    <ConfigProvider locale={zhCN} theme={{ algorithm: theme.defaultAlgorithm }}>
      <Layout style={{ minHeight: '100vh' }}>
        <Header teachingEnabled={teachingEnabled} onToggleTeaching={() => useAppStore.getState().setTeachingEnabled(!teachingEnabled)} />
        <Layout>
          <Sider width={240} style={{ background: '#fff', borderRight: '1px solid #f0f0f0', overflow: 'auto' }}>
            <Sidebar />
          </Sider>
          <Content style={{ display: 'flex', flexDirection: 'column', background: '#f5f5f5' }}>
            {error && <ErrorAlert message={error} onClose={() => setError(null)} />}
            {dataFullscreen ? (
              <DataFullscreen />
            ) : (
              <ResultFlow onRerun={executeCommand} />
            )}
            <CommandLine onExecute={executeCommand} />
          </Content>
        </Layout>
      </Layout>
    </ConfigProvider>
  );
}
```

- [ ] **Step 3: 更新 Header**

移除"运行模型"按钮，添加教学开关：

```tsx
// Header.tsx 变更:
// - 移除: <Button htmlType="submit" form="model-form">运行模型</Button>
// + 添加: <Button onClick={onToggleTeaching}>📖 {teachingEnabled ? '教学开' : '教学关'}</Button>
```

- [ ] **Step 4: 更新 modelStore 的 ModelHistoryItem 类型**

```typescript
// modelStore.ts — ModelHistoryItem 添加 command 字段:
export interface ModelHistoryItem {
  id: string;
  command: string;      // ← 新增
  spec?: ModelSpec;
  result: ModelResult;
  timestamp: number;
}
```

- [ ] **Step 5: 运行完整测试套件**

```bash
cd apps/metrica-desktop && npx vitest run
```

- [ ] **Step 6: 启动 dev server 验证**

```bash
cd apps/metrica-desktop && npm run dev
```

验证：
- 命令行渲染在底部
- 输入 `use "data.csv"` 加载数据
- 侧边栏显示变量卡片
- 输入 `regress y x1 x2` 执行回归
- 结果流显示结果块
- 教学开关工作

- [ ] **Step 7: 提交**

```bash
git add apps/metrica-desktop/src-react/
git commit -m "feat: App 布局重构 — CLI + 结果流 + 教学层"
```

---

### Task 12: 清理旧代码

**Files:**
- Delete: `apps/metrica-desktop/src-react/components/ModelForm.tsx`
- Modify: `apps/metrica-desktop/src-react/stores/modelStore.ts` (移除不再需要的 flat fields)

- [ ] **Step 1: 删除 ModelForm.tsx**

```bash
rm apps/metrica-desktop/src-react/components/ModelForm.tsx
```

- [ ] **Step 2: 清理 modelStore 中不再需要的字段**

移除 CLI 不再直接写入的 flat state fields（modelType, formula, vcovType, etc.），保留 `lastResult`, `modelHistory`, `buildModelSpec`, `applyModelSpec`, `addToHistory`, `removeFromHistory`。

- [ ] **Step 3: 运行测试 + 提交**

```bash
cd apps/metrica-desktop && npx vitest run
git add -A apps/metrica-desktop/src-react/
git commit -m "refactor: 删除 ModelForm，清理 modelStore 冗余字段"
```

---

### Task 13: 端到端验证 + 收尾

- [ ] **Step 1: 启动完整应用**

```bash
# 终端 1: 启动 Julia Runtime
cd /Users/skahanium/Metrica && julia --project=runtime -e 'include("scripts/julia_daemon.jl")'

# 终端 2: 启动前端
cd apps/metrica-desktop && npm run dev
```

- [ ] **Step 2: 走通完整分析流**

1. `use "datasets/demo/ols_demo.csv"` → 数据加载，侧边栏显示变量卡片
2. `summarize` → 描述性统计
3. `regress y x1 x2, robust` → OLS 结果块（Glance + 系数表 + 诊断图）
4. `ovtest` → RESET 诊断
5. 开启/关闭教学层 → 验证教学卡片
6. 点击诊断图 → 展开/收起
7. 切换到数据全屏视图 → 浏览表格，查看列统计
8. `describe` → 变量列表

- [ ] **Step 3: 最终提交**

```bash
git add -A
git commit -m "chore: 端到端验证通过，交互纯粹化重构完成"
```

---

## 验证计划

| # | 验证项 | 方式 |
|---|--------|------|
| 1 | 命令解析正确性 | `npx vitest run __tests__/commandParser.test.ts` |
| 2 | 补全引擎正确性 | `npx vitest run __tests__/autocomplete.test.ts` |
| 3 | CommandLine 渲染与交互 | `npx vitest run __tests__/CommandLine.test.tsx` |
| 4 | 全测试套件无回归 | `npx vitest run` |
| 5 | dev server 可启动 | `npm run dev`，访问 http://localhost:5173 |
| 6 | 数据加载 + 回归 + 诊断 全流程 | 手动 E2E |
