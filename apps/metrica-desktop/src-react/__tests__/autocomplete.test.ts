import { describe, it, expect } from 'vitest';
import { getContext, getPartial, getCompletions, getCorrections, getGhostText } from '../services/autocomplete';
import type { ColumnSummary } from '../types/protocol';

const mockVars: ColumnSummary[] = [
  { name: 'gdp', type: 'Float64', inferred_type: 'continuous' },
  { name: 'inflation', type: 'Float64', inferred_type: 'continuous' },
  { name: 'year', type: 'Int64', inferred_type: 'discrete' },
  { name: 'region', type: 'String', inferred_type: 'categorical' },
];

describe('getContext', () => {
  it('detects verb context at start', () => {
    expect(getContext('reg', 3).kind).toBe('verb');
  });

  it('detects verb context for empty input', () => {
    expect(getContext('', 0).kind).toBe('verb');
  });

  it('detects depvar context after verb + space', () => {
    // "regress " -> cursor at end, at depvar position
    expect(getContext('regress ', 8).kind).toBe('depvar');
  });

  it('detects indepvar context after first positional', () => {
    expect(getContext('regress gdp ', 12).kind).toBe('indepvar');
  });

  it('detects option context after comma', () => {
    expect(getContext('regress y x, ', 13).kind).toBe('option');
  });

  it('detects option_value context inside parens', () => {
    expect(getContext('xtreg y x, id(', 14).kind).toBe('option_value');
    expect(getContext('xtreg y x, id(', 14).optionName).toBe('id');
  });
});

describe('getPartial', () => {
  it('extracts word being typed', () => {
    expect(getPartial('regress gd', 10)).toBe('gd');
  });

  it('returns empty at word boundary', () => {
    expect(getPartial('regress gdp ', 12)).toBe('');
  });

  it('extracts after comma', () => {
    expect(getPartial('regress y, rob', 14)).toBe('rob');
  });
});

describe('getCompletions', () => {
  it('returns verb completions', () => {
    const ctx = { kind: 'verb' as const };
    const c = getCompletions(ctx, mockVars, 'reg');
    expect(c.length).toBeGreaterThan(0);
    expect(c[0].text).toBe('regress');
    expect(c[0].kind).toBe('verb');
  });

  it('prioritizes continuous vars for depvar', () => {
    const ctx = { kind: 'depvar' as const };
    const c = getCompletions(ctx, mockVars, '');
    expect(c[0].text).toBe('gdp'); // continuous, priority 10
  });

  it('filters by partial', () => {
    const ctx = { kind: 'indepvar' as const };
    const c = getCompletions(ctx, mockVars, 'inf');
    expect(c).toHaveLength(1);
    expect(c[0].text).toBe('inflation');
  });

  it('returns empty for no match', () => {
    const ctx = { kind: 'indepvar' as const };
    const c = getCompletions(ctx, mockVars, 'zzz');
    expect(c).toHaveLength(0);
  });

  it('returns option completions for regress', () => {
    const ctx = { kind: 'option' as const, grammar: { syntax: [{ kind: 'option', label: '选项', required: false, multiple: true, children: { robust: { kind: 'option_value' as const, label: 'robust', required: false, multiple: false }, cluster: { kind: 'option_value' as const, label: 'cluster', required: false, multiple: false } } }] } as any };
    const c = getCompletions(ctx, mockVars, '');
    expect(c.length).toBe(2);
  });

  it('prioritizes categorical vars for cluster option value', () => {
    const ctx = { kind: 'option_value' as const, optionName: 'cluster' };
    const c = getCompletions(ctx, mockVars, '');
    expect(c[0].text).toBe('region'); // categorical, priority 10
  });
});

describe('getCorrections', () => {
  it('suggests close matches', () => {
    const c = getCorrections('inflaton', mockVars);
    expect(c.length).toBeGreaterThan(0);
    expect(c[0].text).toBe('inflation');
  });

  it('returns empty for exact match', () => {
    const c = getCorrections('gdp', mockVars, 3);
    expect(c).toHaveLength(0);
  });

  it('returns empty for too-distant matches', () => {
    const c = getCorrections('xyzabc', mockVars, 1);
    expect(c).toHaveLength(0);
  });
});

describe('getGhostText', () => {
  it('returns remainder for partial match', () => {
    const ctx = { kind: 'verb' as const };
    const text = getGhostText(ctx, mockVars, 'reg', 3);
    expect(text).toBe('ress'); // "reg" + "ress" = "regress"
  });

  it('returns null for complete match', () => {
    const ctx = { kind: 'verb' as const };
    const text = getGhostText(ctx, mockVars, 'regress', 7);
    expect(text).toBeNull();
  });

  it('returns null for no match', () => {
    const ctx = { kind: 'indepvar' as const };
    const text = getGhostText(ctx, mockVars, 'zz', 2);
    expect(text).toBeNull();
  });
});
