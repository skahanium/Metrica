import { describe, it, expect } from 'vitest';
import { tokenize, parse, parseToModelSpec, parseToDiagnosticSpec, isDiagnosticVerb } from '../services/commandParser';

describe('tokenize', () => {
  it('splits by spaces', () => {
    expect(tokenize('regress y x1 x2')).toEqual(['regress', 'y', 'x1', 'x2']);
  });

  it('preserves quoted strings', () => {
    expect(tokenize('use "path/to data.csv"')).toEqual(['use', '"path/to data.csv"']);
  });

  it('handles single quotes', () => {
    expect(tokenize("use 'path/to data.csv'")).toEqual(['use', "'path/to data.csv'"]);
  });

  it('handles empty input', () => {
    expect(tokenize('')).toEqual([]);
  });

  it('handles multiple spaces', () => {
    expect(tokenize('regress   y    x1')).toEqual(['regress', 'y', 'x1']);
  });

  it('preserves quantile(...) as single option token', () => {
    expect(tokenize('qreg y x1 x2, quantile(0.5)')).toEqual(['qreg', 'y', 'x1', 'x2', ',', 'quantile(0.5)']);
  });
});

describe('parse', () => {
  it('parses simple regress', () => {
    const r = parse('regress gdp inflation year');
    expect(r.verb).toBe('regress');
    expect(r.positionals).toEqual(['gdp', 'inflation', 'year']);
    expect(r.options).toEqual([]);
    expect(r.error).toBeUndefined();
  });

  it('parses sur with parenthesis equation blocks', () => {
    const r = parse('sur (y1 x1 x2) (y2 x1 x2)');
    expect(r.verb).toBe('sur');
    expect(r.positionals).toEqual(['(y1 x1 x2)', '(y2 x1 x2)']);
  });

  it('parses regress with options', () => {
    const r = parse('regress gdp inflation, robust');
    expect(r.positionals).toEqual(['gdp', 'inflation']);
    expect(r.options).toEqual([{ name: 'robust' }]);
  });

  it('parses key-value options', () => {
    const r = parse('regress gdp inflation, cluster(region) robust');
    expect(r.options).toEqual([
      { name: 'cluster', value: 'region' },
      { name: 'robust' },
    ]);
  });

  it('returns error for unknown verb', () => {
    const r = parse('unknown_cmd x y');
    expect(r.error).toBeDefined();
    expect(r.error).toContain('未知命令');
  });

  it('parses compare with multiple run ids', () => {
    const r = parse('compare run-1 run-2');
    expect(r.verb).toBe('compare');
    expect(r.positionals).toEqual(['run-1', 'run-2']);
    expect(r.options).toEqual([]);
  });

  it('parses export markdown with run id and using option', () => {
    const r = parse('export markdown run-1, using("/tmp/a.md")');
    expect(r.verb).toBe('export');
    expect(r.positionals).toEqual(['markdown', 'run-1']);
    expect(r.options).toEqual([{ name: 'using', value: '"/tmp/a.md"' }]);
  });

  it('parses export plot with format and using', () => {
    const r = parse('export plot run-event, format(svg) using("/tmp/a.svg")');
    expect(r.verb).toBe('export');
    expect(r.positionals).toEqual(['plot', 'run-event']);
    expect(r.options).toEqual([
      { name: 'format', value: 'svg' },
      { name: 'using', value: '"/tmp/a.svg"' },
    ]);
  });

  it('load is standalone verb (not mapped to project)', () => {
    const r = parse('load "/tmp/proj.metrica"');
    expect(r.verb).toBe('load');
    expect(r.positionals).toEqual(['"/tmp/proj.metrica"']);
  });

  it('returns error for empty input', () => {
    const r = parse('');
    expect(r.error).toBe('空命令');
  });

  it('parses xtreg with all panel options', () => {
    const r = parse('xtreg gdp capital labor, id(country) time(year) method(fe) robust');
    expect(r.verb).toBe('xtreg');
    expect(r.positionals).toEqual(['gdp', 'capital', 'labor']);
    expect(r.options).toHaveLength(4);
    expect(r.options.find(o => o.name === 'method')?.value).toBe('fe');
  });
});

describe('parseToModelSpec', () => {
  it('converts sur to ModelSpec with equations', () => {
    const r = parse('sur (y1 x1 x2) (y2 x1 x2)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('sur');
      expect(spec.formula).toBe('');
      expect(spec.equations).toEqual(['y1 ~ x1 + x2', 'y2 ~ x1 + x2']);
    }
  });

  it('converts reg3 to system_2sls with pipe segments', () => {
    const r = parse('reg3 (y1 x1 x2), endogenous(x1) instruments(z1)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('system_2sls');
      expect(spec.equations).toEqual(['y1 ~ x1 + x2']);
      expect(spec.system_endogenous).toEqual([['x1']]);
      expect(spec.system_instruments).toEqual([['z1']]);
    }
  });

  it('converts reg3 method(3sls) to system_3sls', () => {
    const r = parse('reg3 (y1 x1 x2), endogenous(x1) instruments(z1) method(3sls)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('system_3sls');
    }
  });

  it('converts regress to ols ModelSpec', () => {
    const r = parse('regress gdp inflation year, robust');
    const spec = parseToModelSpec(r);
    expect(spec).not.toHaveProperty('error');
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('ols');
      expect(spec.formula).toBe('gdp ~ inflation + year');
      expect(spec.vcov).toEqual({ type: 'HC1' });
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

  it('converts ivregress to IV ModelSpec', () => {
    const r = parse('ivregress y x1 x2, endogenous(x1) instruments(z1 z2)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('iv');
      expect(spec.endog_columns).toEqual(['x1']);
      expect(spec.instruments).toEqual(['z1', 'z2']);
    }
  });

  it('converts gmm to gmm_linear ModelSpec with weight', () => {
    const r = parse('gmm y x1 x2, endogenous(x1) instruments(z1 z2) weight(one_step)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('gmm_linear');
      expect(spec.endog_columns).toEqual(['x1']);
      expect(spec.instruments).toEqual(['z1', 'z2']);
      expect(spec.gmm_weight).toBe('one_step');
    }
  });

  it('converts gmm without weight (defaults on backend)', () => {
    const r = parse('gmm y x1 x2, endogenous(x1) instruments(z1 z2)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('gmm_linear');
      expect(spec.gmm_weight).toBeUndefined();
    }
  });

  it('converts qreg with quantile(0.5) to quantile ModelSpec', () => {
    const r = parse('qreg y x1 x2, quantile(0.5)');
    const spec = parseToModelSpec(r);
    expect(spec).not.toHaveProperty('error');
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('quantile');
      expect(spec.formula).toBe('y ~ x1 + x2');
      expect(spec.quantile_tau).toBe(0.5);
      expect(spec.vcov).toBeUndefined();
    }
  });

  it('defaults qreg tau to 0.5 when quantile omitted', () => {
    const r = parse('qreg y x1 x2');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('quantile');
      expect(spec.quantile_tau).toBe(0.5);
    }
  });

  it('rejects illegal quantile boundary', () => {
    const r = parse('qreg y x1, quantile(1)');
    const spec = parseToModelSpec(r);
    expect(spec).toHaveProperty('error');
  });

  it('converts nls with start to ModelSpec', () => {
    const r = parse('nls y x, start(0.5 0.5 0.05)');
    const spec = parseToModelSpec(r);
    expect(spec).not.toHaveProperty('error');
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('nls');
      expect(spec.formula).toBe('y ~ x');
      expect(spec.nls_start).toEqual([0.5, 0.5, 0.05]);
      expect(spec.nls_family).toBe('exp_growth');
    }
  });

  it('rejects nls without start', () => {
    const r = parse('nls y x');
    const spec = parseToModelSpec(r);
    expect(spec).toHaveProperty('error');
  });

  it('converts threg with qvar and grid', () => {
    const r = parse('threg y x q, qvar(q) grid(-1 1 5)');
    const spec = parseToModelSpec(r);
    expect(spec).not.toHaveProperty('error');
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('threshold');
      expect(spec.threshold_variable).toBe('q');
      expect(spec.threshold_grid?.length).toBe(5);
      expect(spec.formula).toContain('q');
    }
  });

  it('rejects threg grid with too many points', () => {
    const r = parse('threg y x q, qvar(q) grid(0 1 501)');
    const spec = parseToModelSpec(r);
    expect(spec).toHaveProperty('error');
  });

  it('converts xtivreg to panel IV ModelSpec', () => {
    const r = parse('xtivreg y x1 x2, id(firm) time(year) endogenous(x1) instruments(z1 z2) robust');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('panel_iv');
      expect(spec.panel_id).toBe('firm');
      expect(spec.panel_time).toBe('year');
      expect(spec.endog_columns).toEqual(['x1']);
      expect(spec.instruments).toEqual(['z1', 'z2']);
      expect(spec.vcov).toEqual({ type: 'HC1' });
    }
  });

  it('converts xtabond to dynamic_panel_gmm ModelSpec', () => {
    const r = parse('xtabond y x, id(firm) time(year) lags(2 4) weight(two_step)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('dynamic_panel_gmm');
      expect(spec.panel_id).toBe('firm');
      expect(spec.panel_time).toBe('year');
      expect(spec.instrument_lags).toEqual([2, 4]);
      expect(spec.gmm_weight).toBe('two_step');
    }
  });

  it('converts did to DID ModelSpec', () => {
    const r = parse('did gdp, id(country) time(year) treat(reform) post(after2010)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('did');
      expect(spec.panel_id).toBe('country');
      expect(spec.panel_time).toBe('year');
      expect(spec.treated_column).toBe('reform');
      expect(spec.post_column).toBe('after2010');
    }
  });

  it('converts logit to logit ModelSpec', () => {
    const r = parse('logit y x1 x2, robust');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('logit');
      expect(spec.vcov).toEqual({ type: 'HC1' });
    }
  });

  it('propagates parse error', () => {
    const r = parse('unknown_cmd x y');
    const spec = parseToModelSpec(r);
    expect(spec).toHaveProperty('error');
  });

  it('converts arima with order options', () => {
    const r = parse('arima gdp, time(year) ar(1) i(1) ma(0)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('arima');
      expect(spec.variable).toBe('gdp');
      expect(spec.time_column).toBe('year');
      expect(spec.order).toEqual([1, 1, 0]);
    }
  });

  it('converts var with variables and time column', () => {
    const r = parse('var gdp inflation, time(year) lags(2)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('var');
      expect(spec.variables).toEqual(['gdp', 'inflation']);
      expect(spec.time_column).toBe('year');
      expect(spec.lags).toBe(2);
    }
  });

  it('converts ipw with propensity formula', () => {
    const r = parse('ipw, treat(treated) outcome(y) propensity(treated ~ x1 + x2)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('ipw');
      expect(spec.treatment_column).toBe('treated');
      expect(spec.outcome_column).toBe('y');
      expect(spec.propensity_formula).toBe('treated ~ x1 + x2');
    }
  });

  it('converts aipw with propensity and outcome formulas', () => {
    const r = parse('aipw, treat(treated) outcome(y) propensity(treated ~ x1 + x2) outcome_model(y ~ x1 + x2)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('aipw');
      expect(spec.propensity_formula).toBe('treated ~ x1 + x2');
      expect(spec.outcome_formula).toBe('y ~ x1 + x2');
    }
  });

  it('handles noconstant option', () => {
    const r = parse('regress gdp inflation, noconstant');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.formula).toBe('gdp ~ 0 + inflation');
    }
  });

  it('keeps multiple regressors separate under noconstant', () => {
    const r = parse('regress y x1 x2, noconstant');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.formula).toBe('y ~ 0 + x1 + x2');
    }
  });

  it('converts svy to survey ModelSpec', () => {
    const r = parse('svy ols gdp inflation, strata(region) psu(cluster_id) weights(pop_wt)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('survey_ols');
      expect(spec.formula).toBe('gdp ~ inflation');
      expect(spec.strata_column).toBe('region');
      expect(spec.psu_column).toBe('cluster_id');
      expect(spec.weights_column).toBe('pop_wt');
    }
  });

  it('converts dfuller with deterministic option', () => {
    const r = parse('dfuller gdp, time(year) deterministic(trend)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('unitroot');
      expect(spec.variable).toBe('gdp');
      expect(spec.time_column).toBe('year');
      expect(spec.deterministic).toBe('trend');
    }
  });

  it('summarize does not produce a ModelSpec', () => {
    const parsed = parse('summarize y x1');
    const spec = parseToModelSpec(parsed);
    expect('error' in spec).toBe(true);
    if ('error' in spec) {
      expect(spec.error).toContain('暂不支持');
    }
  });

  it('describe does not produce a ModelSpec', () => {
    const parsed = parse('describe');
    const spec = parseToModelSpec(parsed);
    expect('error' in spec).toBe(true);
  });
});

describe('isDiagnosticVerb', () => {
  it('returns true for diagnostic verb', () => {
    expect(isDiagnosticVerb('diagnostic')).toBe(true);
  });

  it('returns true for alias verbs', () => {
    expect(isDiagnosticVerb('hettest')).toBe(true);
    expect(isDiagnosticVerb('bgodfrey')).toBe(true);
    expect(isDiagnosticVerb('dwstat')).toBe(true);
    expect(isDiagnosticVerb('vif')).toBe(true);
    expect(isDiagnosticVerb('ovtest')).toBe(true);
  });

  it('returns false for non-diagnostic verbs', () => {
    expect(isDiagnosticVerb('regress')).toBe(false);
    expect(isDiagnosticVerb('summarize')).toBe(false);
  });
});

describe('parseToDiagnosticSpec', () => {
  it('parses bp diagnostic', () => {
    const parsed = parse('diagnostic bp');
    const spec = parseToDiagnosticSpec(parsed);
    expect(spec).toEqual({ test: 'bp' });
  });

  it('parses bg with lags', () => {
    const parsed = parse('diagnostic bg, lags(3)');
    const spec = parseToDiagnosticSpec(parsed);
    expect(spec).toEqual({ test: 'bg', lags: 3 });
  });

  it('parses alias hettest as bp', () => {
    const parsed = parse('hettest');
    const spec = parseToDiagnosticSpec(parsed);
    expect(spec).toEqual({ test: 'bp' });
  });

  it('parses bgodfrey alias with lags', () => {
    const parsed = parse('bgodfrey, lags(4)');
    const spec = parseToDiagnosticSpec(parsed);
    expect(spec).toEqual({ test: 'bg', lags: 4 });
  });

  it('parses dwstat alias as dw', () => {
    const parsed = parse('dwstat');
    const spec = parseToDiagnosticSpec(parsed);
    expect(spec).toEqual({ test: 'dw' });
  });

  it('returns error for unknown test', () => {
    const parsed = parse('diagnostic unknown');
    const spec = parseToDiagnosticSpec(parsed);
    expect(spec).toHaveProperty('error');
  });

  it('propagates parse error', () => {
    const parsed = parse('unknown_cmd x y');
    const spec = parseToDiagnosticSpec(parsed);
    expect(spec).toHaveProperty('error');
  });
});
