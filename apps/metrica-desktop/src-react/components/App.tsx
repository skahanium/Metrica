import { useEffect, useCallback, useState } from 'react';
import { ConfigProvider, theme, Alert, Typography } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { CommandLine } from './CommandLine';
import type { CliFeedback } from './CommandLine';
import { ResultFlow } from './ResultFlow';
import { DataFullscreen } from './DataFullscreen';
import { TrashPanel } from './TrashPanel';
import { DataHistoryPanel } from './DataHistoryPanel';
import { useAppStore, MAX_RESTARTS } from '../stores/appStore';
import { useDatasetStore } from '../stores/datasetStore';
import { parse } from '../services/commandParser';
import {
  handleUse, handleProject, handleTrash, handleDatahistory, handleSave,
  handleDataView, handleDataOp, handleModel,
  handleDiagnostic, handlePostest,
  requiresActiveDataset, isDiagnosticVerb, isPostestVerb,
} from '../services/commandExecutor';
import { isDataOperationVerb } from '../services/commandDataOps';

const { Text } = Typography;

export function App() {
  const {
    error, juliaHealthy, restartCount, dataFullscreen,
    startHealthPolling, stopHealthPolling, setError,
  } = useAppStore();
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
      const msg = parsed.error.startsWith('未知命令:')
        ? `${parsed.error.replace(/^未知命令:\s*/, '未知命令：')}。请从补全列表选择可用命令。`
        : parsed.error;
      showCliFeedback('error', msg);
      return false;
    }

    const { verb } = parsed;

    // 命令路由表
    switch (verb) {
      case 'use': return handleUse(parsed, input, showCliFeedback);
      case 'project': return handleProject(parsed, input, showCliFeedback);
      case 'trash': return handleTrash(parsed, input, showCliFeedback);
      case 'datahistory': return handleDatahistory(parsed, input, showCliFeedback);
      case 'save': return handleSave(parsed, input, showCliFeedback);
      default: {
        if (!activePath && requiresActiveDataset(verb)) {
          showCliFeedback('warning', '请先加载数据集，再执行模型或数据操作命令');
          return false;
        }
        if (verb === 'describe' || verb === 'browse' || verb === 'summarize' || verb === 'tabulate') {
          return handleDataView(parsed, input, showCliFeedback);
        }
        if (isDiagnosticVerb(verb)) return handleDiagnostic(parsed, input, showCliFeedback);
        if (isPostestVerb(verb)) return handlePostest(parsed, input, showCliFeedback);
        if (isDataOperationVerb(verb)) return handleDataOp(parsed, input, showCliFeedback);
        // fallthrough to model
        return handleModel(parsed, input, showCliFeedback);
      }
    }
  }, [activePath, showCliFeedback]);

  return (
    <ConfigProvider theme={{ algorithm: theme.defaultAlgorithm }} locale={zhCN}>
      <div style={{ position: 'fixed', inset: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {/* 品牌条 */}
        <div style={{
          display: 'flex', alignItems: 'center',
          padding: '0 24px', height: 48, background: '#fff',
          borderBottom: '1px solid #f0f0f0', flexShrink: 0,
        }}>
          <Text style={{ letterSpacing: 4, fontWeight: 700, color: '#8c8c8c', fontSize: 18 }}>
            METRICA
          </Text>
        </div>

        {/* 主面板：消息流 + CLI */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: '#fff', minHeight: 0 }}>
          {error && (
            <Alert type="error" message={error} closable onClose={() => setError(null)}
              showIcon style={{ flexShrink: 0, margin: '8px 16px 0' }} />
          )}
          {!juliaHealthy && restartCount < MAX_RESTARTS && (
            <Alert type="warning"
              message={`Julia 计算引擎不可用（已自动重启 ${restartCount} 次）。运行时正在尝试自动恢复，请稍候重试。`}
              showIcon style={{ flexShrink: 0, margin: '8px 16px 0' }} />
          )}
          {!juliaHealthy && restartCount >= MAX_RESTARTS && (
            <Alert type="error"
              message={`Julia 计算引擎已崩溃 ${MAX_RESTARTS} 次，已达最大重启次数。请检查 Julia 环境后刷新页面。`}
              showIcon style={{ flexShrink: 0, margin: '8px 16px 0' }} />
          )}
          <div style={{ flex: 1, overflow: dataFullscreen ? 'hidden' : 'auto', minHeight: 0 }}>
            {dataFullscreen ? <DataFullscreen /> : <ResultFlow />}
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
      <TrashPanel />
      <DataHistoryPanel />
    </ConfigProvider>
  );
}
