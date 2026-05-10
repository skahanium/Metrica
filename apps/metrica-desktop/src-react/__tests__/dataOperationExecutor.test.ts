import { beforeEach, describe, expect, it, vi } from 'vitest';
import { executeDataOperations } from '../services/dataOperationExecutor';
import { useAppStore } from '../stores/appStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useProjectStore } from '../stores/projectStore';
import { useTransformStore } from '../stores/transformStore';

describe('executeDataOperations', () => {
  beforeEach(() => {
    useAppStore.setState({ error: null, isLoading: false });
    useDatasetStore.setState({
      sourcePath: '/tmp/source.csv',
      activePath: '/tmp/source.csv',
      summary: { nrows: 2, ncols: 2, columns: [], preview: [] },
    });
    useProjectStore.setState({
      runHistory: [],
      isDirty: false,
      manifest: {
        project_id: 'p1',
        version: 1,
        created_at: '1',
        updated_at: '1',
        source_dataset: '/tmp/source.csv',
        active_dataset: '/tmp/source.csv',
        saved_model_specs: [],
        ui_state: {},
        data_lineage: {
          source_dataset: '/tmp/source.csv',
          active_dataset: '/tmp/source.csv',
          operations: [],
          notes: [],
        },
      },
    });
    useTransformStore.setState({
      operations: [],
      history: [],
      resultItems: [],
      lastTransformResult: null,
      isTransforming: false,
    });
    vi.unstubAllGlobals();
  });

  it('runs transform and refreshes shared state for cli and ui callers', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          task_id: 'transform-ok',
          status: 'success',
          messages: [],
          run_record: {
            run_id: 'transform-ok',
            action: 'transform',
            status: 'success',
            started_at: '1',
            finished_at: '2',
            dataset_ref: { source: 'file', path: '/tmp/source.csv', format: 'csv' },
            warnings: [],
            messages: [],
            artifacts: [],
            result_summary: null,
            operations: [{ op: 'filter', args: { condition: 'x > 1' } }],
          },
          result_payload: {
            operation: 'filter',
            status: 'ok',
            result: { nrows: 1, ncols: 2, notes: 'ok', dataset_path: '/tmp/derived.csv' },
            preview: { columns: ['x'], rows: [{ x: 2 }] },
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
            columns: [{ name: 'x', type: 'Int64' }],
            preview: [{ x: 2 }],
          },
        }),
      });
    vi.stubGlobal('fetch', fetchImpl);

    await executeDataOperations({
      operations: [{ op: 'filter', args: { condition: 'x > 1' } }],
      commandLabel: 'filter x > 1',
      source: 'cli',
    });

    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(useDatasetStore.getState().activePath).toBe('/tmp/derived.csv');
    expect(useDatasetStore.getState().summary?.nrows).toBe(1);
    expect(useTransformStore.getState().history).toHaveLength(1);
    expect(useTransformStore.getState().resultItems[0].command).toBe('filter x > 1');
    expect(useProjectStore.getState().runHistory[0].run_id).toBe('transform-ok');
    expect(useProjectStore.getState().isDirty).toBe(true);
  });
});
