import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { DataFullscreen } from '../components/DataFullscreen';
import { useAppStore } from '../stores/appStore';
import { useDatasetStore } from '../stores/datasetStore';

vi.mock('ag-grid-react', () => ({
  AgGridReact: ({ columnDefs }: { columnDefs: Array<{ headerName?: string }> }) => (
    <div data-testid="grid-columns">{columnDefs.map((col) => col.headerName).filter(Boolean).join(',')}</div>
  ),
}));

describe('DataFullscreen', () => {
  beforeEach(() => {
    useAppStore.setState({
      dataFullscreen: true,
      setDataFullscreen: vi.fn(),
    });
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 2,
        columns: [
          { name: 'y', inferred_type: 'Float64', missing_count: 0 },
          { name: 'x1', inferred_type: 'Float64', missing_count: 0 },
        ],
        preview: [{ y: 1, x1: 3 }, { y: 2, x1: 4 }],
      },
      browseColumns: ['x1'],
      browseReadonly: true,
    });
  });

  it('filters columns and hides transform actions in readonly browse mode', () => {
    render(<DataFullscreen />);

    expect(screen.getByTestId('grid-columns').textContent).not.toContain('y');
    expect(screen.getByTestId('grid-columns').textContent).toContain('x1');
    expect(screen.queryByText('变换')).toBeNull();
  });
});
