import { useEffect } from 'react';
import { ConfigProvider, Layout, Tabs, theme, Alert } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { ModelForm } from './ModelForm';
import { GlanceTable } from './GlanceTable';
import { TidyTable } from './TidyTable';
import { DiscreteGlanceCards } from './DiscreteGlanceCards';
import { OddsRatioTable } from './OddsRatioTable';
import { DiagnosticCards } from './DiagnosticCards';
import { DiagnosticCharts } from './DiagnosticCharts';
import { AugmentPreview } from './AugmentPreview';
import { ErrorPanel } from './ErrorPanel';
import { WarningPanel } from './WarningPanel';
import { DataOperationsPanel } from './DataOperationsPanel';
import { OperationHistory } from './OperationHistory';
import { DataPreviewTable } from './DataPreviewTable';
import { ProjectPanel } from './ProjectPanel';
import { ExportPanel } from './ExportPanel';
import { ModelComparison } from './ModelComparison';
import { useAppStore, MAX_RESTARTS } from '../stores/appStore';
import { useModelStore } from '../stores/modelStore';

const { Content, Sider } = Layout;

export function App() {
  const {
    activeTab, setActiveTab, error,
    juliaHealthy, restartCount,
    startHealthPolling, stopHealthPolling,
  } = useAppStore();
  const lastResult = useModelStore((s) => s.lastResult);

  useEffect(() => {
    startHealthPolling();
    return () => stopHealthPolling();
  }, [startHealthPolling, stopHealthPolling]);

  return (
    <ConfigProvider theme={{ algorithm: theme.defaultAlgorithm }} locale={zhCN}>
      <Layout style={{ minHeight: '100vh' }}>
        <Header />
        <Layout>
          <Sider width={280} style={{ background: '#fafafa' }}>
            <Sidebar />
          </Sider>
          <Content style={{ padding: 24, background: '#fff' }}>
            <ModelForm />

            {/* 操作错误 */}
            {error && <ErrorPanel messages={[{ code: 'ERROR', text: error }]} />}

            {/* Julia 健康降级横幅 */}
            {!juliaHealthy && restartCount < MAX_RESTARTS && (
              <Alert
                type="warning"
                message={`Julia 计算引擎不可用（已自动重启 ${restartCount} 次）。运行时正在尝试自动恢复，请稍候重试。`}
                showIcon
                style={{ marginBottom: 16 }}
              />
            )}
            {!juliaHealthy && restartCount >= MAX_RESTARTS && (
              <Alert
                type="error"
                message={`Julia 计算引擎已崩溃 ${MAX_RESTARTS} 次，已达最大重启次数。请检查 Julia 环境后刷新页面。`}
                showIcon
                style={{ marginBottom: 16 }}
              />
            )}

            {/* 模型警告 */}
            {lastResult?.warnings && <WarningPanel warnings={lastResult.warnings} />}

            <Tabs
              activeKey={activeTab}
              onChange={setActiveTab}
              items={[
                { key: 'data', label: '数据处理', children: <><DataOperationsPanel /><OperationHistory /><DataPreviewTable /></> },
                { key: 'project', label: '项目', children: <ProjectPanel /> },
                { key: 'glance', label: '模型概览', children: <><GlanceTable /><DiscreteGlanceCards /></> },
                { key: 'tidy', label: '系数表', children: <><TidyTable /><OddsRatioTable /></> },
                { key: 'diagnostics', label: '诊断', children: <><DiagnosticCards /><DiagnosticCharts /></> },
                { key: 'augment', label: '拟合值', children: <AugmentPreview /> },
                { key: 'comparison', label: '模型对比', children: <ModelComparison /> },
                { key: 'export', label: '导出', children: <ExportPanel /> },
              ]}
            />
          </Content>
        </Layout>
      </Layout>
    </ConfigProvider>
  );
}
