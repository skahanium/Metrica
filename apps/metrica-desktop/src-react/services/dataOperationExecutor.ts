import type { DataOp, TransformResult } from '../types/protocol';
import { useAppStore } from '../stores/appStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useProjectStore } from '../stores/projectStore';
import { useTransformStore } from '../stores/transformStore';
import { inferWorkingDir, inspectDataset, transformTask } from './runtimeClient';

interface ExecuteDataOperationsParams {
  operations: DataOp[];
  commandLabel: string;
  source: 'cli' | 'ui';
}

function resultId(prefix: string): string {
  return globalThis.crypto?.randomUUID?.() ?? `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function collectStepResults(result: TransformResult): TransformResult[] {
  return result.operations?.length ? result.operations : [result];
}

export async function executeDataOperations(params: ExecuteDataOperationsParams): Promise<TransformResult> {
  const { operations, commandLabel, source } = params;
  const datasetStore = useDatasetStore.getState();
  const activePath = datasetStore.activePath;

  if (!activePath) {
    throw new Error('请先选择数据集');
  }
  if (!operations.length) {
    throw new Error('请先添加至少一个数据操作');
  }

  const appStore = useAppStore.getState();
  const transformStore = useTransformStore.getState();

  appStore.setLoading(true);
  transformStore.setTransforming(true);
  appStore.setError(null);

  try {
    const workingDir = inferWorkingDir(activePath);
    const task = await transformTask({
      datasetPath: activePath,
      operations,
      workingDir,
      previewRows: 10,
      persistOutput: true,
    });
    const result = task.result_payload;
    if (!result) {
      throw new Error(task.messages?.map((message) => message.text).join('; ') || '数据操作失败');
    }

    const currentTransformStore = useTransformStore.getState();
    currentTransformStore.setLastTransformResult(result);
    currentTransformStore.addResultItem({
      id: task.task_id || resultId('transform'),
      command: commandLabel,
      source,
      datasetPath: result.result?.dataset_path || activePath,
      result,
      createdAt: new Date().toISOString(),
    });
    if (task.run_record) {
      useProjectStore.getState().appendRunRecord(task.run_record);
    }

    if (result.status === 'error') {
      appStore.setError(result.error?.message ?? '数据操作失败');
      return result;
    }

    currentTransformStore.appendHistory(collectStepResults(result));

    const currentProjectStore = useProjectStore.getState();
    currentProjectStore.appendLineageOperations(operations);
    if (result.result) {
      currentProjectStore.updateLineageRowCounts(datasetStore.summary?.nrows ?? 0, result.result.nrows);
    }
    currentProjectStore.setDirty(true);

    const derivedPath = result.result?.dataset_path;
    if (derivedPath) {
      useDatasetStore.getState().setActivePath(derivedPath);
      const summary = await inspectDataset(derivedPath, inferWorkingDir(derivedPath));
      useDatasetStore.getState().setSummary(summary);
    }

    return result;
  } catch (error) {
    appStore.setError(error instanceof Error ? error.message : '数据操作失败');
    throw error;
  } finally {
    useTransformStore.getState().setTransforming(false);
    useAppStore.getState().setLoading(false);
  }
}
