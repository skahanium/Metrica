import { ConfigProvider, Layout, Tabs, theme } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { ModelForm } from './ModelForm';
import { GlanceTable } from './GlanceTable';
import { TidyTable } from './TidyTable';
import { DiagnosticCards } from './DiagnosticCards';
import { DiagnosticCharts } from './DiagnosticCharts';
import { AugmentPreview } from './AugmentPreview';
import { ErrorPanel } from './ErrorPanel';
import { WarningPanel } from './WarningPanel';
import { useAppStore } from '../stores/appStore';
import { useModelStore } from '../stores/modelStore';

const { Content, Sider } = Layout;

export function App() {
  const { activeTab, setActiveTab, error } = useAppStore();
  const lastResult = useModelStore((s) => s.lastResult);

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
            {error && <ErrorPanel messages={[{ code: 'ERROR', text: error }]} />}
            {lastResult?.warnings && <WarningPanel warnings={lastResult.warnings} />}
            <Tabs
              activeKey={activeTab}
              onChange={setActiveTab}
              items={[
                { key: 'glance', label: '模型概览', children: <GlanceTable /> },
                { key: 'tidy', label: '系数表', children: <TidyTable /> },
                { key: 'diagnostics', label: '诊断', children: <><DiagnosticCards /><DiagnosticCharts /></> },
                { key: 'augment', label: '拟合值', children: <AugmentPreview /> },
              ]}
            />
          </Content>
        </Layout>
      </Layout>
    </ConfigProvider>
  );
}
