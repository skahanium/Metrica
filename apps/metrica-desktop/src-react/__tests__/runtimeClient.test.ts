import { describe, it, expect, vi } from 'vitest';
import { buildFitModelRequest, buildTransformRequest, transformDataset } from '../services/runtimeClient';

describe('buildFitModelRequest', () => {
  it('builds OLS request with correct structure', () => {
    const req = buildFitModelRequest({
      datasetPath: '/tmp/demo.csv',
      formula: 'y ~ x1 + x2',
    });
    expect(req.action).toBe('fit_model');
    expect(req.dataset_ref.path).toBe('/tmp/demo.csv');
    expect(req.model_spec.model_type).toBe('ols');
  });

  it('builds panel request with panel fields', () => {
    const req = buildFitModelRequest({
      datasetPath: '/tmp/panel.csv',
      formula: 'invest ~ mvalue + capital',
      modelType: 'panel',
      panelId: 'firm',
      panelTime: 'year',
      panelMethod: 'fe',
    });
    expect(req.model_spec.model_type).toBe('panel');
    expect(req.model_spec.panel_id).toBe('firm');
    expect(req.model_spec.panel_time).toBe('year');
  });

  it('includes weights and cluster for OLS', () => {
    const req = buildFitModelRequest({
      datasetPath: '/tmp/demo.csv',
      formula: 'y ~ x1 + x2',
      vcovType: 'cluster',
      clusterColumn: 'group_id',
    });
    expect(req.model_spec.vcov?.type).toBe('cluster');
    expect(req.model_spec.cluster_column).toBe('group_id');
  });
});

describe('transformDataset', () => {
  it('builds task-style transform request', () => {
    const req = buildTransformRequest({
      datasetPath: '/tmp/source.csv',
      operations: [{ op: 'filter', args: { condition: 'year >= 2015' } }],
      previewRows: 5,
      persistOutput: true,
    });

    expect(req.action).toBe('transform');
    expect(req.dataset_ref.path).toBe('/tmp/source.csv');
    expect(req.operations[0].op).toBe('filter');
    expect(req.options.preview_rows).toBe(5);
    expect(req.options.persist_output).toBe(true);
  });

  it('unwraps TaskResponse result_payload', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        task_id: 'transform-test',
        status: 'success',
        messages: [],
        result_payload: {
          operation: 'chain',
          status: 'ok',
          result: { nrows: 2, ncols: 2, notes: 'ok', dataset_path: '/tmp/derived.csv' },
          preview: { columns: ['y'], rows: [{ y: 1 }] },
          warnings: [],
        },
      }),
    });

    const result = await transformDataset(
      { datasetPath: '/tmp/source.csv', operations: [{ op: 'filter', args: { condition: 'y > 0' } }] },
      'http://runtime.test',
      fetchImpl as unknown as typeof fetch,
    );

    expect(fetchImpl).toHaveBeenCalledWith(
      'http://runtime.test/transform',
      expect.objectContaining({ method: 'POST' }),
    );
    expect(result.result?.dataset_path).toBe('/tmp/derived.csv');
    expect(result.preview?.rows[0].y).toBe(1);
  });
});
