import { describe, it, expect } from 'vitest';
import { getGrammar, COMMAND_GRAMMARS, COMMAND_LIST } from '../services/commandGrammar';

describe('commandGrammar', () => {
  it('has grammars for all common commands', () => {
    expect(getGrammar('regress')).toBeDefined();
    expect(getGrammar('ivregress')).toBeDefined();
    expect(getGrammar('gmm')).toBeDefined();
    expect(getGrammar('qreg')).toBeDefined();
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
    expect(getGrammar('spreg')).toBeDefined();
    expect(getGrammar('stcox')).toBeDefined();
  });

  it('returns undefined for unknown verb', () => {
    expect(getGrammar('nonexistent')).toBeUndefined();
  });

  it('all model commands have depvar as first syntax node', () => {
    const modelVerbs = ['regress', 'ivregress', 'gmm', 'qreg', 'gls', 'xtreg', 'xtivreg',
      'logit', 'probit', 'poisson', 'ologit', 'mlogit', 'nbreg',
      'did', 'eventstudy', 'ipw', 'psm', 'aipw',
      'arima', 'var', 'dfuller', 'coint', 'garch', 'arch', 'spreg', 'stcox'];
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

  it('diagnostic commands have correct syntax', () => {
    for (const verb of ['ovtest', 'hettest', 'vif', 'dwstat', 'hausman']) {
      const g = getGrammar(verb);
      expect(g, `Missing grammar for ${verb}`).toBeDefined();
      expect(g!.syntax.length).toBe(0);
    }
    const bg = getGrammar('bgodfrey')!;
    expect(bg.syntax.length).toBe(2);
    expect(bg.syntax[0].kind).toBe('comma');
    expect(bg.syntax[1].kind).toBe('option');
  });

  it('diagnostic unified command has test_name positional', () => {
    const g = getGrammar('diagnostic')!;
    expect(g.category).toBe('diagnostic');
    expect(g.syntax[0].kind).toBe('indepvar');
    expect(g.syntax[0].values).toEqual(['bp', 'bg', 'reset', 'jb', 'dw', 'white', 'vif']);
  });

  it('COMMAND_LIST contains all grammars', () => {
    expect(COMMAND_LIST.length).toBe(Object.keys(COMMAND_GRAMMARS).length);
  });
});
