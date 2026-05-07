import { useEffect, useCallback } from 'react';
import { ConfigProvider, theme, Alert } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { CommandLine } from './CommandLine';
import { ResultFlow } from './ResultFlow';
import { DataFullscreen } from './DataFullscreen';
import { useAppStore, MAX_RESTARTS } from '../stores/appStore';
import { useModelStore } from '../stores/modelStore';
import { useDatasetStore } from '../stores/datasetStore';
import { parse, parseToModelSpec } from '../services/commandParser';
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

  useEffect(() => {
    startHealthPolling();
    return () => stopHealthPolling();
  }, [startHealthPolling, stopHealthPolling]);

  const executeCommand = useCallback(async (input: string) => {
    const parsed = parse(input);
    if (parsed.error) {
      setError(parsed.error);
      return;
    }

    const verb = parsed.verb;

    // --- use "path" ---
    if (verb === 'use') {
      const raw = parsed.positionals[0] || '';
      if (raw === 'clear') {
        useDatasetStore.getState().setSourceAndActivePath('', '');
        useDatasetStore.getState().setSummary(null);
        setError(null);
        return;
      }
      const filePath = raw.replace(/^["']|["']$/g, '');
      if (!filePath) { setError('请指定数据文件路径'); return; }
      setLoading(true);
      try {
        const result = await api.inspectDataset(filePath);
        setSourceAndActivePath(filePath, filePath);
        setSummary(result);
        setError(null);
      } catch (e: any) {
        setError(e.message || '数据加载失败');
      } finally {
        setLoading(false);
      }
      return;
    }

    // --- guard: need dataset ---
    if (!activePath) {
      setError('请先使用 use 命令加载数据集');
      return;
    }

    // --- modeling commands ---
    const modelSpecResult = parseToModelSpec(parsed);
    if (!('error' in modelSpecResult)) {
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
        } else {
          setError('模型返回结果异常');
        }
      } catch (e: any) {
        setError(e.message || '模型拟合失败');
      } finally {
        setLoading(false);
      }
      return;
    }

    // parseToModelSpec returned error
    if ('error' in modelSpecResult) {
      setError(modelSpecResult.error);
    }
  }, [activePath, setLoading, setError, setLastResult, addToHistory, setSummary, setSourceAndActivePath]);

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
            <div style={{ flex: 1, overflow: 'auto', minHeight: 0 }}>
              {dataFullscreen ? <DataFullscreen /> : <ResultFlow onRerun={executeCommand} />}
            </div>
            <div style={{ flexShrink: 0 }}>
              <CommandLine onExecute={executeCommand} />
            </div>
          </div>
        </div>
      </div>
    </ConfigProvider>
  );
}
