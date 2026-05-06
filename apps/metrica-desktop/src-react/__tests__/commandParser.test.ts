import { describe, it, expect } from 'vitest';
import { tokenize, parse, parseToModelSpec } from '../services/commandParser';

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
});

describe('parse', () => {
  it('parses simple regress', () => {
    const r = parse('regress gdp inflation year');
    expect(r.verb).toBe('regress');
    expect(r.positionals).toEqual(['gdp', 'inflation', 'year']);
    expect(r.options).toEqual([]);
    expect(r.error).toBeUndefined();
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
  it('converts regress to ols ModelSpec', () => {
    const r = parse('regress gdp inflation year, robust');
    const spec = parseToModelSpec(r);
    expect(spec).not.toHaveProperty('error');
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('ols');
      expect(spec.formula).toBe('gdp ~ inflation + year');
      expect(spec.vcov).toEqual({ type: 'hc1' });
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
      expect(spec.vcov).toEqual({ type: 'hc1' });
    }
  });

  it('propagates parse error', () => {
    const r = parse('unknown_cmd x y');
    const spec = parseToModelSpec(r);
    expect(spec).toHaveProperty('error');
  });

  it('converts arima with order options', () => {
    const r = parse('arima gdp, ar(1) i(1) ma(0)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('arima');
      expect(spec.order).toEqual([1, 1, 0]);
    }
  });

  it('handles noconstant option', () => {
    const r = parse('regress gdp inflation, noconstant');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.formula).toBe('gdp ~ inflation - 1');
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
    const r = parse('dfuller gdp, deterministic(trend)');
    const spec = parseToModelSpec(r);
    if (!('error' in spec)) {
      expect(spec.model_type).toBe('unitroot');
      expect(spec.deterministic).toBe('trend');
    }
  });
});
