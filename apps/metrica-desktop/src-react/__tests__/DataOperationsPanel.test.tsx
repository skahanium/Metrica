import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { DataOperationsPanel } from '../components/DataOperationsPanel';
import { useDatasetStore } from '../stores/datasetStore';
import { useTransformStore } from '../stores/transformStore';
import { useAppStore } from '../stores/appStore';

describe('DataOperationsPanel', () => {
  beforeEach(() => {
    useDatasetStore.setState({
      sourcePath: '/tmp/source.csv',
      activePath: '/tmp/source.csv',
      summary: null,
    });
    useTransformStore.setState({
      operations: [],
      history: [],
      resultItems: [],
      lastTransformResult: null,
      isTransforming: false,
    });
    useAppStore.setState({ error: null });
    vi.unstubAllGlobals();
  });

  it('adds and removes an operation', () => {
    render(<DataOperationsPanel />);

    fireEvent.change(screen.getByPlaceholderText('year >= 2015'), { target: { value: 'year >= 2020' } });
    fireEvent.click(screen.getByText('添加'));

    expect(screen.getByText(/year >= 2020/)).toBeDefined();

    fireEvent.click(screen.getByLabelText('删除第 1 步'));
    expect(screen.getByText('尚未添加操作')).toBeDefined();
  });

  it('switches active dataset to derived csv after a successful transform', async () => {
    useTransformStore.setState({
      operations: [{ op: 'filter', args: { condition: 'year >= 2020' } }],
    });
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          task_id: 'transform-ok',
          status: 'success',
          messages: [],
          result_payload: {
            operation: 'chain',
            status: 'ok',
            result: { nrows: 1, ncols: 2, notes: 'ok', dataset_path: '/tmp/.metrica/derived/transform-ok.csv' },
            preview: { columns: ['year'], rows: [{ year: 2020 }] },
            warnings: [],
          },
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          task_id: 'inspect-derived',
          status: 'success',
          messages: [],
          result_payload: {
            nrows: 1,
            ncols: 2,
            columns: [{ name: 'year', type: 'Int64' }],
            preview: [{ year: 2020 }],
          },
        }),
      });
    vi.stubGlobal('fetch', fetchImpl);

    render(<DataOperationsPanel />);
    fireEvent.click(screen.getByText('运行数据操作'));

    await waitFor(() => {
      expect(useDatasetStore.getState().activePath).toBe('/tmp/.metrica/derived/transform-ok.csv');
    });
    expect(useDatasetStore.getState().isDerived()).toBe(true);
    expect(useTransformStore.getState().history.length).toBe(1);
    expect(useTransformStore.getState().resultItems[0].source).toBe('ui');
  });

  it('adds impute_missing operation without extra args', () => {
    render(<DataOperationsPanel />);

    fireEvent.mouseDown(screen.getByRole('combobox'));
    fireEvent.click(screen.getByText('自动插补缺失值 impute missing'));
    fireEvent.click(screen.getByText('添加'));

    expect(screen.getByText(/impute_missing/)).toBeDefined();
    expect(screen.getByText(/\{\}/)).toBeDefined();
  });
});
