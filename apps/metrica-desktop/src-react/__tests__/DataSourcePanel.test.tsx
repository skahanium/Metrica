import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { DataSourcePanel } from '../components/DataSourcePanel';
import { useDatasetStore } from '../stores/datasetStore';
import { useModelStore } from '../stores/modelStore';
import { useTransformStore } from '../stores/transformStore';
import { useAppStore } from '../stores/appStore';

const pickCsvFile = vi.fn();
const inspectDataset = vi.fn();

vi.mock('../services/nativeHost', () => ({
  pickCsvFile: (...args: unknown[]) => pickCsvFile(...args),
}));

vi.mock('../services/runtimeClient', async () => {
  const actual = await vi.importActual<typeof import('../services/runtimeClient')>('../services/runtimeClient');
  return {
    ...actual,
    inspectDataset: (...args: unknown[]) => inspectDataset(...args),
  };
});

describe('DataSourcePanel', () => {
  beforeEach(() => {
    useDatasetStore.setState({
      sourcePath: '/tmp/old.csv',
      activePath: '/tmp/derived.csv',
      summary: { nrows: 1, ncols: 1, columns: [], preview: [] },
    });
    useModelStore.setState({ lastResult: { glance: { model: 'ols', nobs: 1, dof: 1, metrics: {} }, tidy: [], diagnostics: {}, warnings: [] } });
    useTransformStore.setState({ operations: [{ op: 'filter', args: { condition: 'x > 0' } }], history: [{ operation: 'filter', status: 'ok', warnings: [] }], lastTransformResult: null, isTransforming: false });
    useAppStore.setState({ error: null });
    pickCsvFile.mockReset();
    inspectDataset.mockReset();
  });

  it('chooses csv and auto-inspects dataset', async () => {
    pickCsvFile.mockResolvedValue({ path: '/tmp/new.csv', cancelled: false });
    inspectDataset.mockResolvedValue({ nrows: 3, ncols: 2, columns: [], preview: [] });

    render(<DataSourcePanel />);
    fireEvent.click(screen.getByText('选择 CSV 文件'));

    await waitFor(() => {
      expect(inspectDataset).toHaveBeenCalledWith('/tmp/new.csv', '/tmp');
    });
    expect(useDatasetStore.getState().sourcePath).toBe('/tmp/new.csv');
    expect(useDatasetStore.getState().activePath).toBe('/tmp/new.csv');
    expect(useTransformStore.getState().operations).toEqual([]);
    expect(useTransformStore.getState().history).toEqual([]);
  });

  it('keeps current state when user cancels file picking', async () => {
    pickCsvFile.mockResolvedValue({ path: null, cancelled: true });

    render(<DataSourcePanel />);
    fireEvent.click(screen.getByText('选择 CSV 文件'));

    await waitFor(() => {
      expect(pickCsvFile).toHaveBeenCalled();
    });
    expect(inspectDataset).not.toHaveBeenCalled();
    expect(useDatasetStore.getState().sourcePath).toBe('/tmp/old.csv');
    expect(useDatasetStore.getState().activePath).toBe('/tmp/derived.csv');
  });

  it('shows unsupported-host error when native picker is unavailable', async () => {
    pickCsvFile.mockRejectedValue(new Error('当前宿主不支持选择本地 CSV 文件'));

    render(<DataSourcePanel />);
    fireEvent.click(screen.getByText('选择 CSV 文件'));

    await waitFor(() => {
      expect(useAppStore.getState().error).toBe('当前宿主不支持选择本地 CSV 文件');
    });
  });
});
