import { describe, it, expect, vi } from 'vitest';
import {
  buildFitModelRequest, buildLoadProjectRequest, buildRerunTaskRequest,
  buildSaveProjectRequest, buildTransformRequest, listRuns, transformDataset, transformTask,
  saveProject, loadProject, rerunTask,
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
