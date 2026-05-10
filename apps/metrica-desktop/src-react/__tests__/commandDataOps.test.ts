import { describe, expect, it } from 'vitest';
import { parse } from '../services/commandParser';
import { parseToDataOp } from '../services/commandDataOps';

describe('parseToDataOp', () => {
  it('maps filter to DataOp', () => {
    expect(parseToDataOp(parse('filter x1 > 2'))).toEqual({
      op: 'filter',
      args: { condition: 'x1 > 2' },
    });
  });

  it('maps impute_missing to DataOp', () => {
    expect(parseToDataOp(parse('impute_missing'))).toEqual({
      op: 'impute_missing',
      args: {},
    });
  });

  it('maps generate assignment to DataOp', () => {
    expect(parseToDataOp(parse('generate z = x1 + x2'))).toEqual({
      op: 'generate',
      args: { name: 'z', expr: 'x1 + x2' },
    });
  });

  it('maps replace with explicit value and condition options', () => {
    expect(parseToDataOp(parse('replace flag, value("c") if(x > 1)'))).toEqual({
      op: 'replace',
      args: { col: 'flag', value: '"c"', condition: 'x > 1' },
    });
  });

  it('maps simple column list operations', () => {
    expect(parseToDataOp(parse('drop x1 x2'))).toEqual({ op: 'drop', args: { cols: ['x1', 'x2'] } });
    expect(parseToDataOp(parse('keep y x1'))).toEqual({ op: 'keep', args: { cols: ['y', 'x1'] } });
    expect(parseToDataOp(parse('sort year id'))).toEqual({ op: 'sort', args: { cols: ['year', 'id'] } });
  });

  it('maps rename to DataOp', () => {
    expect(parseToDataOp(parse('rename old_name new_name'))).toEqual({
      op: 'rename',
      args: { mapping: { old_name: 'new_name' } },
    });
  });

  it('maps merge to DataOp', () => {
    expect(parseToDataOp(parse('merge "/tmp/right.csv", on(id year) how(left)'))).toEqual({
      op: 'merge',
      args: { with: '/tmp/right.csv', on: ['id', 'year'], how: 'left' },
    });
  });

  it('maps reshape long and wide to DataOp', () => {
    expect(parseToDataOp(parse('reshape long gdp pop, id(country) time(year)'))).toEqual({
      op: 'reshape_long',
      args: { id_cols: ['country'], time_col: 'year', stub_cols: ['gdp', 'pop'] },
    });
    expect(parseToDataOp(parse('reshape wide gdp, id(country) time(year)'))).toEqual({
      op: 'reshape_wide',
      args: { id_cols: ['country'], time_col: 'year', value_cols: ['gdp'] },
    });
  });

  it('maps collapse to DataOp', () => {
    expect(parseToDataOp(parse('collapse gdp pop, by(country) stats(mean sum)'))).toEqual({
      op: 'collapse',
      args: { by: ['country'], stats: ['mean', 'sum'], value_cols: ['gdp', 'pop'] },
    });
  });
});
