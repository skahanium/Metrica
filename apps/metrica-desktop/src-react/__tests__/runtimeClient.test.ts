import { describe, it, expect } from 'vitest';
import { buildFitModelRequest } from '../services/runtimeClient';

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
