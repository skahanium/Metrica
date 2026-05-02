import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { DataPreviewTable } from '../components/DataPreviewTable';
import { useDatasetStore } from '../stores/datasetStore';
import { useTransformStore } from '../stores/transformStore';

describe('DataPreviewTable', () => {
  beforeEach(() => {
    useDatasetStore.setState({ summary: null });
    useTransformStore.setState({ lastTransformResult: null });
  });

  it('renders inspect preview rows when no transform has run', async () => {
    useDatasetStore.setState({
      summary: {
        nrows: 1,
        ncols: 2,
        columns: [
          { name: 'country', type: 'String', missing: 0 },
          { name: 'year', type: 'Int64', missing: 0 },
        ],
        preview: [{ country: 'France', year: 2020 }],
      },
    });

    render(<DataPreviewTable />);

    expect(await screen.findByText('France')).toBeDefined();
    expect(screen.getByText('2020')).toBeDefined();
  });

  it('prefers transform preview rows', async () => {
    useTransformStore.setState({
      lastTransformResult: {
        operation: 'chain',
        status: 'ok',
        result: { nrows: 1, ncols: 1, notes: 'ok' },
        preview: { columns: ['log_gdp'], rows: [{ log_gdp: 9.1 }] },
        warnings: [],
      },
    });

    render(<DataPreviewTable />);

    expect(await screen.findByText('9.1')).toBeDefined();
  });
});
