/**
 * Golden CLI → ModelSpec 映射：与 datasets/golden/*.json 的 model_type 对齐。
 */
import { describe, it, expect } from 'vitest';
import { parse, parseToModelSpec } from '../services/commandParser';

type GoldenCliCase = {
  id: string;
  command: string;
  model_type: string;
  formula?: string;
  paramKeys?: string[];
};

const GOLDEN_CLI_CASES: GoldenCliCase[] = [
  { id: 'linear_ols', command: 'regress y x1 x2', model_type: 'ols', formula: 'y ~ x1 + x2' },
  {
    id: 'linear_iv',
    command: 'ivregress y x1 x2, endogenous(x1) instruments(z1 z2)',
    model_type: 'iv',
    formula: 'y ~ x1 + x2',
    paramKeys: ['instruments', 'endog_columns'],
  },
  { id: 'linear_gls', command: 'gls y x1 x2', model_type: 'gls', formula: 'y ~ x1 + x2' },
  { id: 'discrete_logit', command: 'logit y x1 x2', model_type: 'logit', formula: 'y ~ x1 + x2' },
  { id: 'discrete_probit', command: 'probit y x1 x2', model_type: 'probit', formula: 'y ~ x1 + x2' },
  { id: 'discrete_poisson', command: 'poisson y x1 x2', model_type: 'poisson', formula: 'y ~ x1 + x2' },
  {
    id: 'panel_dynamic_gmm',
    command: 'xtabond y x, id(firm) time(year) lags(2 4) weight(two_step)',
    model_type: 'dynamic_panel_gmm',
    formula: 'y ~ x',
    paramKeys: ['panel_id', 'panel_time', 'instrument_lags', 'gmm_weight'],
  },
  {
    id: 'duration_cox',
    command: 'stcox time fail x1',
    model_type: 'duration_cox',
    formula: 'ph ~ x1',
    paramKeys: ['duration_time_column', 'duration_event_column'],
  },
  {
    id: 'causal_did',
    command: 'did y, id(id) time(time) treat(treated) post(post)',
    model_type: 'did',
    paramKeys: ['panel_id', 'panel_time', 'treated_column', 'post_column'],
  },
  {
    id: 'system_sur',
    command: 'sur (y1 x1 x2) (y2 x1 x2)',
    model_type: 'sur',
    paramKeys: ['equations'],
  },
  {
    id: 'gmm_linear',
    command: 'gmm y x1 x2, endogenous(x1) instruments(z1 z2) weight(two_step)',
    model_type: 'gmm_linear',
    formula: 'y ~ x1 + x2',
    paramKeys: ['instruments', 'endog_columns', 'gmm_weight'],
  },
  {
    id: 'timeseries_arima',
    command: 'arima y, time(time) ar(1) i(0) ma(0)',
    model_type: 'arima',
    paramKeys: ['variable', 'time_column', 'order'],
  },
];

describe('commandParser golden model_type mapping', () => {
  for (const c of GOLDEN_CLI_CASES) {
    it(`maps ${c.id} → ${c.model_type}`, () => {
      const r = parse(c.command);
      expect(r.error).toBeUndefined();
      const spec = parseToModelSpec(r);
      expect(spec).not.toHaveProperty('error');
      if ('error' in spec) return;
      expect(spec.model_type).toBe(c.model_type);
      if (c.formula) {
        expect(spec.formula).toBe(c.formula);
      }
      if (c.paramKeys) {
        for (const key of c.paramKeys) {
          expect(spec.params).toHaveProperty(key);
        }
      }
    });
  }
});
