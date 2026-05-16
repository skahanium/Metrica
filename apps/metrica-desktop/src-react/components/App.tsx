import { useEffect, useCallback, useState } from 'react';
import { ConfigProvider, theme, Alert, Typography, Tooltip } from 'antd';
import { SunOutlined, MoonOutlined } from '@ant-design/icons';
import zhCN from 'antd/locale/zh_CN';
import { CommandLine } from './CommandLine';
import type { CliFeedback } from '../types/protocol';
import { ResultFlow } from './ResultFlow';
import { DataFullscreen } from './DataFullscreen';
import { TrashPanel } from './TrashPanel';
import { DataHistoryPanel } from './DataHistoryPanel';
import { useAppStore } from '../stores/appStore';
import { startHealthPolling, stopHealthPolling, MAX_RESTARTS } from '../services/healthPolling';
import { useDatasetStore } from '../stores/datasetStore';
import { parse } from '../services/commandParser';
import {
  handleUse, handleProject, handleTrash, handleDatahistory, handleSave,
  handleLoad, handleRuns, handleRerun, handleExport, handleCompare,
  handleDataView, handleDataOp, handleModel,
  handleDiagnostic, handlePostest,
  requiresActiveDataset, isDiagnosticVerb, isPostestVerb,
} from '../services/commandExecutor';
import { isDataOperationVerb } from '../services/commandDataOps';

const { Text } = Typography;

export function App() {
  const {
    error, juliaHealthy, healthChecked, restartCount, dataFullscreen, setError,
  } = useAppStore();
  const activePath = useDatasetStore((s) => s.activePath);
  const [cliFeedback, setCliFeedback] = useState<CliFeedback | null>(null);

  // 深色模式：用户偏好（light / dark / system）
  const [themePreference, setThemePreference] = useState<'light' | 'dark' | 'system'>(() => {
    const saved = localStorage.getItem('metrica-theme');
    if (saved === 'light' || saved === 'dark') return saved;
    return 'system';
  });

  // 监听系统色彩方案变化
  const [systemIsDark, setSystemIsDark] = useState(() =>
    typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches,
  );

  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = (e: MediaQueryListEvent) => setSystemIsDark(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);

  // 解析最终主题
  const isDark = themePreference === 'dark' || (themePreference === 'system' && systemIsDark);

  // 同步 data-theme 属性（CSS 变量切换）与 localStorage
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
    localStorage.setItem('metrica-theme', themePreference);
  }, [isDark, themePreference]);

  // 循环切换：light → dark → system
  const cycleTheme = useCallback(() => {
    setThemePreference((prev) => {
      if (prev === 'light') return 'dark';
      if (prev === 'dark') return 'system';
      return 'light';
    });
  }, []);

  const themeIcon = themePreference === 'light' ? <SunOutlined />
    : themePreference === 'dark' ? <MoonOutlined />
    : <SunOutlined />;
  const themeLabel = themePreference === 'light' ? '浅色'
    : themePreference === 'dark' ? '深色'
    : '跟随系统';

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
      case 'load': return handleLoad(parsed, input, showCliFeedback);
      case 'runs': return handleRuns(parsed, input, showCliFeedback);
      case 'rerun': return handleRerun(parsed, input, showCliFeedback);
      case 'export': return handleExport(parsed, input, showCliFeedback);
      case 'compare': return handleCompare(parsed, input, showCliFeedback);
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
    <ConfigProvider theme={{ algorithm: isDark ? theme.darkAlgorithm : theme.defaultAlgorithm }} locale={zhCN}>
      <div style={{ position: 'fixed', inset: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {/* 品牌条 */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '0 24px', height: 48, background: 'var(--m-brand-bar-bg)',
          borderBottom: '1px solid var(--m-brand-bar-border)', flexShrink: 0,
        }}>
          <Text style={{ letterSpacing: 4, fontWeight: 700, color: 'var(--m-brand-text)', fontSize: 18 }}>
            METRICA
          </Text>
          <Tooltip title={`当前：${themeLabel} — 点击切换`}>
            <button
              type="button"
              onClick={cycleTheme}
              aria-label={`切换主题：${themeLabel}`}
              style={{
                border: 0,
                background: 'transparent',
                color: 'var(--m-brand-text)',
                cursor: 'pointer',
                fontSize: 18,
                padding: '4px 8px',
                borderRadius: 4,
                display: 'flex',
                alignItems: 'center',
                transition: 'color 0.2s',
              }}
            >
              {themeIcon}
            </button>
          </Tooltip>
        </div>

        {/* 主面板：消息流 + CLI */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: 'var(--m-panel-bg)', minHeight: 0 }}>
          {error && (
            <Alert type="error" message={error} closable onClose={() => setError(null)}
              showIcon style={{ flexShrink: 0, margin: '8px 16px 0' }} />
          )}
          {!healthChecked && (
            <Alert type="info"
              message="正在连接 Julia 计算引擎，首次启动需要 30–90 秒…"
              showIcon style={{ flexShrink: 0, margin: '8px 16px 0' }} />
          )}
          {healthChecked && !juliaHealthy && restartCount < MAX_RESTARTS && (
            <Alert type="warning"
              message={`Julia 计算引擎不可用（已自动重启 ${restartCount} 次）。运行时正在尝试自动恢复，请稍候重试。`}
              showIcon style={{ flexShrink: 0, margin: '8px 16px 0' }} />
          )}
          {healthChecked && !juliaHealthy && restartCount >= MAX_RESTARTS && (
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
