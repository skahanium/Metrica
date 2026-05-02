import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { DiagnosticCards } from '../components/DiagnosticCards';
import { useModelStore } from '../stores/modelStore';

describe('DiagnosticCards', () => {
  it('renders OLS diagnostics', () => {
    useModelStore.setState({
      lastResult: {
        glance: { model: 'ols', nobs: 128, dof: 124, metrics: { r2: 0.81 } },
        tidy: [],
        diagnostics: {
          breusch_pagan: { statistic: 3.2, pvalue: 0.0736, dof: 2 },
          white_test: { statistic: 5.1, pvalue: 0.0778, dof: 2 },
          durbin_watson: { statistic: 1.85, pvalue: 0.62 },
        },
        warnings: [],
      },
    });
    render(<DiagnosticCards />);
    expect(screen.getByText('Breusch-Pagan 异方差检验')).toBeDefined();
    expect(screen.getByText('Durbin-Watson 自相关检验')).toBeDefined();
  });

  it('shows unavailable diagnostic gracefully', () => {
    useModelStore.setState({
      lastResult: {
        glance: { model: 'ols', nobs: 128, dof: 124, metrics: { r2: 0.81 } },
        tidy: [],
        diagnostics: {
          breusch_pagan: { statistic: null, pvalue: null, available: false, note: '样本不足' },
        },
        warnings: [],
      },
    });
    render(<DiagnosticCards />);
    expect(screen.getAllByText('不可用').length).toBeGreaterThan(0);
  });
});
