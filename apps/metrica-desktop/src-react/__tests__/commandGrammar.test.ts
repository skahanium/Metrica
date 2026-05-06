import { describe, it, expect } from 'vitest';
import { getGrammar, COMMAND_GRAMMARS, COMMAND_LIST } from '../services/commandGrammar';

describe('commandGrammar', () => {
  it('has grammars for all common commands', () => {
    expect(getGrammar('regress')).toBeDefined();
    expect(getGrammar('ivregress')).toBeDefined();
    expect(getGrammar('xtreg')).toBeDefined();
    expect(getGrammar('logit')).toBeDefined();
    expect(getGrammar('did')).toBeDefined();
    expect(getGrammar('use')).toBeDefined();
    expect(getGrammar('summarize')).toBeDefined();
    expect(getGrammar('describe')).toBeDefined();
    expect(getGrammar('generate')).toBeDefined();
    expect(getGrammar('drop')).toBeDefined();
    expect(getGrammar('keep')).toBeDefined();
    expect(getGrammar('rename')).toBeDefined();
    expect(getGrammar('predict')).toBeDefined();
    expect(getGrammar('margins')).toBeDefined();
    expect(getGrammar('test')).toBeDefined();
    expect(getGrammar('export')).toBeDefined();
  });

  it('returns undefined for unknown verb', () => {
    expect(getGrammar('nonexistent')).toBeUndefined();
  });

  it('all model commands have depvar as first syntax node', () => {
    const modelVerbs = ['regress', 'ivregress', 'gls', 'xtreg', 'xtivreg',
      'logit', 'probit', 'poisson', 'ologit', 'mlogit', 'nbreg',
      'did', 'eventstudy', 'ipw', 'psm', 'aipw',
      'arima', 'var', 'dfuller', 'coint'];
    for (const verb of modelVerbs) {
      const g = getGrammar(verb);
      expect(g, `Missing grammar for ${verb}`).toBeDefined();
      expect(g!.syntax[0].kind, `${verb} first node should be depvar`).toBe('depvar');
    }
  });

  it('xtreg has required id, time, and method options', () => {
    const g = getGrammar('xtreg')!;
    const opts = g.syntax.find(n => n.kind === 'option')!;
    expect(opts.children!.id.required).toBe(true);
    expect(opts.children!.time.required).toBe(true);
    expect(opts.children!.method.required).toBe(true);
    expect(opts.children!.method.values).toEqual(['fe', 're', 'fd', 'between', 'hdfe', 'cre']);
  });

  it('diagnostic commands have no syntax nodes', () => {
    for (const verb of ['ovtest', 'hettest', 'vif', 'dwstat', 'bgodfrey', 'hausman']) {
      const g = getGrammar(verb);
      expect(g, `Missing grammar for ${verb}`).toBeDefined();
      expect(g!.syntax.length).toBe(0);
    }
  });

  it('COMMAND_LIST contains all grammars', () => {
    expect(COMMAND_LIST.length).toBe(Object.keys(COMMAND_GRAMMARS).length);
  });
});
