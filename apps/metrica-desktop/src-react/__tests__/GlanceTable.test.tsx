import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { GlanceTable } from '../components/GlanceTable';
import type { ModelResult } from '../types/protocol';

const mockResult: ModelResult = {
  glance: { model: 'ols', nobs: 128, dof: 124, metrics: { r2: 0.81, adj_r2: 0.80, sigma: 1.5, rss: 280.0, tss: 1473.0 } },
  tidy: [],
  diagnostics: {},
  warnings: [],
};

describe('GlanceTable', () => {
  it('renders nothing when no result is provided', () => {
    const { container } = render(<GlanceTable />);
    expect(container.firstChild).toBeNull();
  });

  it('renders glance metrics with Chinese labels', () => {
    render(<GlanceTable result={mockResult} />);
    expect(screen.getByText('OLS')).toBeDefined();
    expect(screen.getByText('128')).toBeDefined();
    expect(screen.getByText('0.8100')).toBeDefined();
  });
});
