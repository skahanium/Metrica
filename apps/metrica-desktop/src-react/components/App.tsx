import { useEffect, useCallback, useState } from 'react';
import { ConfigProvider, theme, Alert } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { CommandLine } from './CommandLine';
import type { CliFeedback } from './CommandLine';
import { ResultFlow } from './ResultFlow';
import { DataFullscreen } from './DataFullscreen';
import { useAppStore, MAX_RESTARTS } from '../stores/appStore';
import { useModelStore } from '../stores/modelStore';
import { useDatasetStore } from '../stores/datasetStore';
import { parse, parseToModelSpec } from '../services/commandParser';
import { isDataOperationVerb, parseToDataOp } from '../services/commandDataOps';
import { executeDataOperations } from '../services/dataOperationExecutor';
import * as api from '../services/runtimeClient';

export function App() {
  const {
    error, juliaHealthy, restartCount, teachingEnabled, dataFullscreen,
    startHealthPolling, stopHealthPolling, setError, setLoading,
  } = useAppStore();
  const setLastResult = useModelStore((s) => s.setLastResult);
  const addToHistory = useModelStore((s) => s.addToHistory);
  const setSummary = useDatasetStore((s) => s.setSummary);
  const setSourceAndActivePath = useDatasetStore((s) => s.setSourceAndActivePath);
  const activePath = useDatasetStore((s) => s.activePath);
  const [cliFeedback, setCliFeedback] = useState<CliFeedback | null>(null);

  useEffect(() => {
    startHealthPolling();
    return () => stopHealthPolling();
  }, [startHealthPolling, stopHealthPolling]);

  const showCliFeedback = useCallback((level: CliFeedback['level'], message: string) => {
    setCliFeedback({ level, message });
  }, []);

  const executeCommand = useCallback((input: string): boolean | Promise<boolean> => {
    const parsed = parse(input);
    if (parsed.error) {
      const message = parsed.error.startsWith('未知命令:')
        ? `${parsed.error.replace(/^未知命令:\s*/, '未知命令：')}。请从补全列表选择可用命令。`
        : parsed.error;
      showCliFeedback('error', message);
      return false;
    }

    const verb = parsed.verb;

    // --- use "path" ---
    if (verb === 'use') {
      const raw = parsed.positionals[0] || '';
      if (raw === 'clear') {
        useDatasetStore.getState().setSourceAndActivePath('', '');
        useDatasetStore.getState().setSummary(null);
        setError(null);
        setCliFeedback(null);
        return true;
      }
      const filePath = raw.replace(/^["']|["']$/g, '');
      if (!filePath) {
        showCliFeedback('warning', 'use 命令需要指定数据文件路径');
        return false;
      }
      return (async () => {
        setLoading(true);
        try {
          const result = await api.inspectDataset(filePath);
          setSourceAndActivePath(filePath, filePath);
          setSummary(result);
          setError(null);
          setCliFeedback(null);
        } catch (e: any) {
          setError(e.message || '数据加载失败');
        } finally {
          setLoading(false);
        }
        return true;
      })();
    }

    // --- guard: need dataset ---
    if (!activePath) {
      showCliFeedback('warning', '请先加载数据集，再执行模型或数据操作命令');
      return false;
    }

    if (isDataOperationVerb(verb)) {
      const opResult = parseToDataOp(parsed);
      if ('error' in opResult) {
        showCliFeedback('warning', opResult.error);
        return false;
      }
      return (async () => {
        try {
          await executeDataOperations({
            operations: [opResult],
            commandLabel: input,
            source: 'cli',
          });
          setCliFeedback(null);
        } catch {
          // executeDataOperations 已经写入结构化错误状态。
        }
        return true;
      })();
    }

    // --- modeling commands ---
    const modelSpecResult = parseToModelSpec(parsed);
    if (!('error' in modelSpecResult)) {
      return (async () => {
        setLoading(true);
        try {
          const result = await api.fitModel({
            datasetPath: activePath,
            formula: modelSpecResult.formula || '',
            modelType: modelSpecResult.model_type,
            vcovType: (modelSpecResult.vcov as any)?.type || 'classical',
            weightsColumn: modelSpecResult.weights || modelSpecResult.weights_column || '',
            clusterColumn: modelSpecResult.cluster_column || '',
            panelId: modelSpecResult.panel_id || '',
            panelTime: modelSpecResult.panel_time || '',
            panelMethod: modelSpecResult.panel_method || '',
            instruments: Array.isArray(modelSpecResult.instruments)
              ? modelSpecResult.instruments.join(',')
              : (modelSpecResult.instruments || ''),
            endogColumns: Array.isArray(modelSpecResult.endog_columns)
              ? modelSpecResult.endog_columns.join(',')
              : (modelSpecResult.endog_columns || ''),
            treatmentColumn: modelSpecResult.treatment_column || modelSpecResult.treated_column || '',
            postColumn: modelSpecResult.post_column || '',
            eventTimeColumn: modelSpecResult.event_time_column || '',
            outcomeColumn: modelSpecResult.outcome_column || '',
            orderP: modelSpecResult.order?.[0],
            orderD: modelSpecResult.order?.[1],
            orderQ: modelSpecResult.order?.[2],
            strataColumn: modelSpecResult.strata_column || '',
            psuColumn: modelSpecResult.psu_column || '',
            fpcColumn: modelSpecResult.fpc_column || '',
          });
          const payload = (result as any).result_payload;
          if (payload && payload.glance) {
            setLastResult(payload);
            addToHistory({
              id: crypto.randomUUID(),
              label: input,
              runId: (result as any).task_id || '',
              modelType: modelSpecResult.model_type,
              formula: modelSpecResult.formula || '',
              datasetPath: activePath,
              result: payload,
              createdAt: new Date().toISOString(),
              command: input,
            });
            setError(null);
            setCliFeedback(null);
          } else {
            setError('模型返回结果异常');
          }
        } catch (e: any) {
          setError(e.message || '模型拟合失败');
        } finally {
          setLoading(false);
        }
        return true;
      })();
    }

    // parseToModelSpec returned error
    if ('error' in modelSpecResult) {
      showCliFeedback('warning', modelSpecResult.error);
      return false;
    }
    return true;
  }, [activePath, setLoading, setError, setLastResult, addToHistory, setSummary, setSourceAndActivePath, showCliFeedback]);

  return (
    <ConfigProvider theme={{ algorithm: theme.defaultAlgorithm }} locale={zhCN}>
      <div style={{ position: 'fixed', inset: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <div style={{ flexShrink: 0 }}>
          <Header
            teachingEnabled={teachingEnabled}
            onToggleTeaching={() => useAppStore.getState().setTeachingEnabled(!teachingEnabled)}
          />
        </div>
        <div style={{ flex: 1, display: 'flex', overflow: 'hidden', minHeight: 0 }}>
          <div style={{ width: 280, flexShrink: 0, background: '#fafafa', overflow: 'hidden', borderRight: '1px solid #f0f0f0' }}>
            <Sidebar />
          </div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: '#fff', minWidth: 0 }}>
            {error && (
              <Alert
                type="error"
                message={error}
                closable
                onClose={() => setError(null)}
                showIcon
                style={{ flexShrink: 0, margin: '8px 16px 0' }}
              />
            )}
            {!juliaHealthy && restartCount < MAX_RESTARTS && (
              <Alert
                type="warning"
                message={`Julia 计算引擎不可用（已自动重启 ${restartCount} 次）。运行时正在尝试自动恢复，请稍候重试。`}
                showIcon
                style={{ flexShrink: 0, margin: '8px 16px 0' }}
              />
            )}
            {!juliaHealthy && restartCount >= MAX_RESTARTS && (
              <Alert
                type="error"
                message={`Julia 计算引擎已崩溃 ${MAX_RESTARTS} 次，已达最大重启次数。请检查 Julia 环境后刷新页面。`}
                showIcon
                style={{ flexShrink: 0, margin: '8px 16px 0' }}
              />
            )}
            <div style={{ flex: 1, overflow: dataFullscreen ? 'hidden' : 'auto', minHeight: 0, display: 'flex' }}>
              {dataFullscreen ? <DataFullscreen /> : <ResultFlow onRerun={executeCommand} />}
            </div>
            <div style={{ flexShrink: 0 }}>
              <CommandLine
                onExecute={executeCommand}
                feedback={cliFeedback}
                onClearFeedback={() => setCliFeedback(null)}
              />
            </div>
          </div>
        </div>
      </div>
    </ConfigProvider>
  );
}
