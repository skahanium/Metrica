import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { TidyTable } from '../components/TidyTable';
import type { ModelResult } from '../types/protocol';

const mockResult: ModelResult = {
  glance: { model: 'ols', nobs: 7, dof: 4, metrics: {} },
  tidy: [
    { term: '(Intercept)', estimate: 2.914286, std_error: 4.777982, statistic: 0.6099, p_value: 0.5749 },
    { term: 'x1', estimate: 2.733333, std_error: 0.718022, statistic: 3.8068, p_value: 0.019 },
  ],
  diagnostics: {},
  warnings: [],
  vcov_label: 'classical',
};

describe('TidyTable', () => {
  it('renders coefficients with Ant Design table styling', () => {
    const { container } = render(<TidyTable result={mockResult} />);

    expect(screen.getByText('classical')).toBeDefined();
    expect(screen.getByText('(Intercept)')).toBeDefined();
    expect(screen.getByText('2.914286')).toBeDefined();
    expect(container.querySelector('.ant-table')).not.toBeNull();
    expect(container.querySelector('.ag-theme-alpine')).toBeNull();
  });

  it('displays — for missing statistics, not 0', () => {
    const result: ModelResult = {
      glance: { model: 'ols', nobs: 3, dof: 1, metrics: {} },
      tidy: [{ term: 'x1', estimate: 1.5, std_error: null, statistic: null, p_value: null }],
      diagnostics: {},
      warnings: [],
    };
    render(<TidyTable result={result} />);
    expect(screen.queryByText('0.0000')).toBeNull();
    expect(screen.queryByText('0.000000')).toBeNull();
    // 破折号表示缺失值
    const dashes = screen.getAllByText('—');
    expect(dashes.length).toBe(3); // std_error, statistic, p_value
  });
});
