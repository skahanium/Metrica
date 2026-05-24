import { describe, it, expect, vi } from 'vitest';
import {
  buildDataCommandRequest,
  buildFitModelRequest, buildLoadProjectRequest, buildRerunTaskRequest,
  buildSaveProjectRequest, buildTransformRequest, listRuns, transformDataset, transformTask,
  saveProject, loadProject, rerunTask, inspectDataset, runDataCommand,
  buildDiagnosticRequest,
} from '../services/runtimeClient';

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
    expect(req.model_spec.params.panel_id).toBe('firm');
    expect(req.model_spec.params.panel_time).toBe('year');
  });

  it('builds spatial_lag request with spatial fields', () => {
    const req = buildFitModelRequest({
      datasetPath: 'datasets/demo/spatial_demo.csv',
      formula: 'y ~ x1',
      modelType: 'spatial_lag',
      workingDir: '/repo/root',
      spatialWeightsPath: 'datasets/demo/spatial_demo_W.csv',
      spatialIdColumn: 'region',
      spatialRowStandardize: true,
    });
    expect(req.model_spec.model_type).toBe('spatial_lag');
    expect(req.model_spec.params.spatial_weights_path).toBe('datasets/demo/spatial_demo_W.csv');
    expect(req.model_spec.params.spatial_id_column).toBe('region');
    expect(req.model_spec.params.spatial_row_standardize).toBe(true);
    expect(req.model_spec.vcov?.type).toBe('classical');
  });

  it('builds duration_cox request with duration columns', () => {
    const req = buildFitModelRequest({
      datasetPath: 'datasets/demo/duration_demo.csv',
      formula: 'ph ~ x1',
      modelType: 'duration_cox',
      workingDir: '/repo/root',
      durationTimeColumn: 'time',
      durationEventColumn: 'fail',
    });
    expect(req.model_spec.model_type).toBe('duration_cox');
    expect(req.model_spec.params.duration_time_column).toBe('time');
    expect(req.model_spec.params.duration_event_column).toBe('fail');
    expect(req.model_spec.vcov).toBeUndefined();
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

  it('passes IV instruments as array without corruption', () => {
    const req = buildFitModelRequest({
      datasetPath: 'data.csv',
      formula: 'y ~ x1',
      modelType: 'iv',
      instruments: 'z1,z2',
      endogColumns: 'x1',
      vcovType: 'classical',
    });
    expect(req.model_spec.params.instruments).toEqual(['z1', 'z2']);
    expect(req.model_spec.params.endog_columns).toEqual(['x1']);
  });

  it('passes panel IV fields without dropping panel identity', () => {
    const req = buildFitModelRequest({
      datasetPath: 'panel.csv',
      formula: 'y ~ x1 + x2',
      modelType: 'panel_iv',
      panelId: 'firm',
      panelTime: 'year',
      instruments: 'z1 z2',
      endogColumns: 'x1',
      vcovType: 'HC1',
    });
    expect(req.model_spec.model_type).toBe('panel_iv');
    expect(req.model_spec.params.panel_id).toBe('firm');
    expect(req.model_spec.params.panel_time).toBe('year');
    expect(req.model_spec.params.instruments).toEqual(['z1', 'z2']);
    expect(req.model_spec.params.endog_columns).toEqual(['x1']);
    expect(req.model_spec.vcov?.type).toBe('HC1');
  });

  it('handles space-separated instruments', () => {
    const req = buildFitModelRequest({
      datasetPath: 'data.csv',
      formula: 'y ~ x1',
      modelType: 'iv',
      instruments: 'z1 z2 z3',
      endogColumns: 'x1',
      vcovType: 'classical',
    });
    expect(req.model_spec.params.instruments).toEqual(['z1', 'z2', 'z3']);
  });

  it('sets treated_column for DID model', () => {
    const req = buildFitModelRequest({
      datasetPath: 'panel.csv',
      formula: 'y ~ x1',
      modelType: 'did',
      treatmentColumn: 'treated',
      panelId: 'id',
      panelTime: 'year',
    });
    expect(req.model_spec.params.treated_column).toBe('treated');
  });

  it('passes causal propensity and outcome formulas', () => {
    const req = buildFitModelRequest({
      datasetPath: 'causal.csv',
      formula: '',
      modelType: 'aipw',
      treatmentColumn: 'treated',
      outcomeColumn: 'y',
      propensityFormula: 'treated ~ x1 + x2',
      outcomeFormula: 'y ~ x1 + x2',
    });
    expect(req.model_spec.params.treatment_column).toBe('treated');
    expect(req.model_spec.params.outcome_column).toBe('y');
    expect(req.model_spec.params.propensity_formula).toBe('treated ~ x1 + x2');
    expect(req.model_spec.params.outcome_formula).toBe('y ~ x1 + x2');
  });

  it('passes time series fields', () => {
    const req = buildFitModelRequest({
      datasetPath: 'ts.csv',
      formula: 'gdp',
      modelType: 'var',
      timeColumn: 'year',
      tsVariables: 'gdp,inflation',
      tsLags: 2,
    });
    expect(req.model_spec.model_type).toBe('var');
    expect(req.model_spec.params.time_column).toBe('year');
    expect(req.model_spec.params.variables).toEqual(['gdp', 'inflation']);
    expect(req.model_spec.params.lags).toBe(2);
  });

  it('passes arch fields (arch_order, optional garch_max_iter / garch_tol)', () => {
    const req = buildFitModelRequest({
      datasetPath: 'demo/garch_demo.csv',
      formula: 'ret',
      modelType: 'arch',
      timeColumn: 'time',
      tsVariable: 'ret',
      archOrder: 2,
      garchMaxIter: 3000,
      garchTol: 1e-4,
    });
    expect(req.model_spec.model_type).toBe('arch');
    expect(req.model_spec.params.time_column).toBe('time');
    expect(req.model_spec.params.variable).toBe('ret');
    expect(req.model_spec.params.arch_order).toBe(2);
    expect(req.model_spec.params.garch_max_iter).toBe(3000);
    expect(req.model_spec.params.garch_tol).toBe(1e-4);
    expect(req.model_spec.params.order).toBeUndefined();
    expect(req.model_spec.params.lags).toBeUndefined();
  });

  it('passes garch fields (garch_p / garch_q and shared optimizer keys)', () => {
    const req = buildFitModelRequest({
      datasetPath: 'demo/garch_demo.csv',
      formula: 'ret',
      modelType: 'garch',
      timeColumn: 'time',
      tsVariable: 'ret',
      garchP: 1,
      garchQ: 1,
      garchMaxIter: 4000,
      garchTol: 1e-5,
    });
    expect(req.model_spec.model_type).toBe('garch');
    expect(req.model_spec.params.time_column).toBe('time');
    expect(req.model_spec.params.variable).toBe('ret');
    expect(req.model_spec.params.garch_p).toBe(1);
    expect(req.model_spec.params.garch_q).toBe(1);
    expect(req.model_spec.params.garch_max_iter).toBe(4000);
    expect(req.model_spec.params.garch_tol).toBe(1e-5);
    expect(req.model_spec.params.arch_order).toBeUndefined();
    expect(req.model_spec.params.order).toBeUndefined();
  });

  it('passes dynamic_panel_gmm panel index and instrument_lags', () => {
    const req = buildFitModelRequest({
      datasetPath: 'panel.csv',
      formula: 'y ~ x',
      modelType: 'dynamic_panel_gmm',
      panelId: 'firm',
      panelTime: 'year',
      instrumentLags: [2, 5],
      gmmWeight: 'one_step',
      dpgmmStyle: 'difference',
      collapseInstruments: false,
    });
    expect(req.model_spec.model_type).toBe('dynamic_panel_gmm');
    expect(req.model_spec.params.panel_id).toBe('firm');
    expect(req.model_spec.params.panel_time).toBe('year');
    expect(req.model_spec.params.instrument_lags).toEqual([2, 5]);
    expect(req.model_spec.params.gmm_weight).toBe('one_step');
    expect(req.model_spec.params.dpgmm_style).toBe('difference');
    expect(req.model_spec.params.collapse_instruments).toBe(false);
  });

  it('passes sur equations and optional sur_max_iter', () => {
    const req = buildFitModelRequest({
      datasetPath: 'sur.csv',
      formula: '',
      modelType: 'sur',
      equations: ['y1 ~ x1', 'y2 ~ x2'],
      surMaxIter: 8,
      surTol: 1e-5,
    });
    expect(req.model_spec.model_type).toBe('sur');
    expect(req.model_spec.params.equations).toEqual(['y1 ~ x1', 'y2 ~ x2']);
    expect(req.model_spec.params.sur_max_iter).toBe(8);
    expect(req.model_spec.params.sur_tol).toBe(1e-5);
    expect(req.model_spec.vcov).toBeUndefined();
  });

  it('passes system_2sls structured IV arrays', () => {
    const req = buildFitModelRequest({
      datasetPath: 's.csv',
      formula: '',
      modelType: 'system_2sls',
      equations: ['y1 ~ x1 + x2'],
      systemEndogenous: [['x1']],
      systemInstruments: [['z1']],
    });
    expect(req.model_spec.params.system_endogenous).toEqual([['x1']]);
    expect(req.model_spec.params.system_instruments).toEqual([['z1']]);
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

  it('returns full transform task response when requested', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        task_id: 'transform-task',
        status: 'success',
        messages: [],
        run_record: { run_id: 'run-1', action: 'transform' },
        result_payload: {
          operation: 'chain',
          status: 'ok',
          warnings: [],
        },
      }),
    });

    const result = await transformTask(
      { datasetPath: '/tmp/source.csv', operations: [{ op: 'filter', args: { condition: 'y > 0' } }] },
      'http://runtime.test',
      fetchImpl as unknown as typeof fetch,
    );

    expect(result.task_id).toBe('transform-task');
    expect(result.run_record?.run_id).toBe('run-1');
  });
});

describe('inspectDataset', () => {
  it('requests enough preview rows for the full data view', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        task_id: 'inspect-test',
        status: 'success',
        messages: [],
        result_payload: {
          dataset_summary: { row_count: 8, column_count: 3 },
          columns: [{ name: 'y', type: 'Int64' }],
          preview_rows: Array.from({ length: 8 }, (_, idx) => ({ y: idx + 1 })),
        },
      }),
    });

    const result = await inspectDataset(
      '/tmp/source.csv',
      '/tmp',
      'http://runtime.test',
      fetchImpl as unknown as typeof fetch,
    );
    const requestBody = JSON.parse(fetchImpl.mock.calls[0][1].body as string);

    expect(requestBody.options.preview_rows).toBeGreaterThanOrEqual(1_000_000);
    expect(result.preview).toHaveLength(8);
  });
});

describe('queryDataset', () => {
  it('builds a dedicated query_dataset request', () => {
    const request = buildDataCommandRequest({
      datasetPath: '/tmp/source.csv',
      command: {
        kind: 'summarize',
        variables: ['y', 'x1'],
      },
    });

    expect(request.action).toBe('query_dataset');
    expect(request.dataset_ref.path).toBe('/tmp/source.csv');
    expect(request.command.kind).toBe('summarize');
    expect(request.command.variables).toEqual(['y', 'x1']);
  });

  it('normalizes describe payloads from runtime', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        task_id: 'query-test',
        status: 'success',
        messages: [],
        result_payload: {
          kind: 'describe',
          dataset_summary: { row_count: 8, column_count: 2 },
          variables: [{ name: 'y', inferred_type: 'Float64', missing_count: 0 }],
        },
      }),
    });

    const result = await runDataCommand(
      {
        datasetPath: '/tmp/source.csv',
        command: { kind: 'describe', variables: ['y'] },
      },
      'http://runtime.test',
      fetchImpl as unknown as typeof fetch,
    );

    expect(fetchImpl).toHaveBeenCalledWith(
      'http://runtime.test/query_dataset',
      expect.objectContaining({ method: 'POST' }),
    );
    expect(result.kind).toBe('describe');
    expect(result.dataset_summary.row_count).toBe(8);
  });

  it('rejects legacy model payloads returned from query_dataset', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        task_id: 'query-legacy',
        status: 'success',
        messages: [],
        result_payload: {
          glance: { model: 'describe', nobs: 8, dof: 0, metrics: {} },
          tidy: [],
          diagnostics: {},
          warnings: [],
        },
      }),
    });

    await expect(runDataCommand(
      {
        datasetPath: '/tmp/source.csv',
        command: { kind: 'describe' },
      },
      'http://runtime.test',
      fetchImpl as unknown as typeof fetch,
    )).rejects.toThrow(/旧版模型结果/);
  });
});

describe('project runtime requests', () => {
  it('builds save project request', () => {
    const req = buildSaveProjectRequest({
      project_id: 'p1',
      version: 1,
      created_at: '1',
      updated_at: '2',
      source_dataset: '/tmp/demo.csv',
      active_dataset: '/tmp/demo.csv',
      saved_model_specs: [{ model_type: 'ols', formula: 'y ~ x1' }],
      last_run_id: null,
      ui_state: {},
      data_lineage: null,
    }, '/tmp');
    expect(req.action).toBe('save_project');
    expect(req.project_context.working_dir).toBe('/tmp');
  });

  it('builds load and rerun requests', () => {
    expect(buildLoadProjectRequest('/tmp').action).toBe('load_project');
    expect(buildRerunTaskRequest('run-1', '/tmp').run_id).toBe('run-1');
  });

  it('lists runs from runtime', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        task_id: 'runs',
        status: 'success',
        messages: [],
        result_payload: { runs: [{ run_id: 'run-1', action: 'fit_model', dataset_ref: { source: 'file', path: '/tmp/demo.csv', format: 'csv' }, warnings: [], messages: [], artifacts: [], started_at: '1', finished_at: '2', status: 'success' }] },
      }),
    });
    const runs = await listRuns('/tmp', 'alpha-demo', 'http://runtime.test', fetchImpl as unknown as typeof fetch);
    expect(runs[0].run_id).toBe('run-1');
  });

  it('saves project and returns manifest', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        task_id: 'save-1',
        status: 'success',
        messages: [],
        result_payload: {
          project_path: '/tmp/.metrica/project.json',
          manifest: { project_id: 'p1', version: 1 },
        },
      }),
    });
    const result = await saveProject(
      {
        project_id: 'p1', version: 1, created_at: '1', updated_at: '2',
        source_dataset: '/tmp/demo.csv', active_dataset: '/tmp/demo.csv',
        saved_model_specs: [], last_run_id: null, ui_state: {}, data_lineage: null,
      },
      '/tmp',
      'http://runtime.test',
      fetchImpl as unknown as typeof fetch,
    );
    expect(result.project_path).toBe('/tmp/.metrica/project.json');
    expect(result.manifest.project_id).toBe('p1');
    expect(fetchImpl).toHaveBeenCalledWith(
      'http://runtime.test/save_project',
      expect.objectContaining({ method: 'POST' }),
    );
  });

  it('loads project and returns manifest', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        task_id: 'load-1',
        status: 'success',
        messages: [],
        result_payload: {
          project_path: '/tmp/.metrica/project.json',
          manifest: { project_id: 'p1', version: 1, source_dataset: '/tmp/demo.csv' },
        },
      }),
    });
    const result = await loadProject('/tmp', 'alpha-demo', 'http://runtime.test', fetchImpl as unknown as typeof fetch);
    expect(result.project_path).toBe('/tmp/.metrica/project.json');
    expect(result.manifest.project_id).toBe('p1');
    expect(fetchImpl).toHaveBeenCalledWith(
      'http://runtime.test/load_project',
      expect.objectContaining({ method: 'POST' }),
    );
  });

  it('reruns task and returns response', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        task_id: 'rerun-1',
        status: 'success',
        messages: [],
        run_record: { run_id: 'rerun-1', action: 'fit_model' },
        result_payload: { glance: { model: 'ols' } },
      }),
    });
    const result = await rerunTask('run-1', '/tmp', 'alpha-demo', 'http://runtime.test', fetchImpl as unknown as typeof fetch);
    expect(result.task_id).toBe('rerun-1');
    expect(result.status).toBe('success');
    expect(fetchImpl).toHaveBeenCalledWith(
      'http://runtime.test/rerun_task',
      expect.objectContaining({ method: 'POST' }),
    );
  });
});

describe('buildDiagnosticRequest', () => {
  it('builds request with test name', () => {
    const req = buildDiagnosticRequest({
      datasetPath: '/path/to/data.csv',
      formula: 'y ~ x1',
      modelType: 'ols',
      diagnostic: { test: 'bp' },
    });
    expect(req.action).toBe('run_diagnostic');
    expect(req.diagnostic.test).toBe('bp');
  });

  it('builds request with lags', () => {
    const req = buildDiagnosticRequest({
      datasetPath: '/path/to/data.csv',
      formula: 'y ~ x1',
      modelType: 'ols',
      diagnostic: { test: 'bg', lags: 3 },
    });
    expect(req.diagnostic.test).toBe('bg');
    expect(req.diagnostic.lags).toBe(3);
  });

  it('defaults modelType to ols', () => {
    const req = buildDiagnosticRequest({
      datasetPath: '/tmp/data.csv',
      formula: 'y ~ x1',
      diagnostic: { test: 'bp' },
    });
    expect(req.model_spec.model_type).toBe('ols');
  });

  it('includes dataset_ref and project_context', () => {
    const req = buildDiagnosticRequest({
      datasetPath: '/tmp/data.csv',
      formula: 'y ~ x1',
      diagnostic: { test: 'reset' },
      workingDir: '/tmp',
      projectId: 'test-project',
    });
    expect(req.dataset_ref.path).toBe('/tmp/data.csv');
    expect(req.project_context.working_dir).toBe('/tmp');
    expect(req.project_context.project_id).toBe('test-project');
  });
});
