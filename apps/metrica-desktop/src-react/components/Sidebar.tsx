import { Button, Typography } from 'antd';
import { TableOutlined } from '@ant-design/icons';
import { DataSourcePanel } from './DataSourcePanel';
import { VariableCard } from './VariableCard';
import { useDatasetStore } from '../stores/datasetStore';
import { useProjectStore } from '../stores/projectStore';
import { useCommandStore } from '../stores/commandStore';
import { useAppStore } from '../stores/appStore';

const { Title, Text } = Typography;

export function Sidebar() {
  const summary = useDatasetStore((s) => s.summary);
  const projectPath = useProjectStore((s) => s.projectPath);
  const setDataFullscreen = useAppStore((s) => s.setDataFullscreen);

  const handleVariableClick = (name: string) => {
    useCommandStore.getState().setInput(name, name.length);
  };

  return (
    <div style={{ padding: 12, background: '#fafafa', height: '100%', overflow: 'auto' }}>
      <Title level={5}>数据源</Title>
      <DataSourcePanel />
      {projectPath && (
        <div style={{ marginTop: 12 }}>
          <Title level={5}>项目</Title>
          <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>{projectPath}</Text>
        </div>
      )}
      <div style={{ marginTop: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
          <Title level={5} style={{ margin: 0 }}>变量</Title>
          {summary?.columns?.length ? (
            <Button
              size="small"
              icon={<TableOutlined />}
              onClick={() => setDataFullscreen(true)}
            >
              查看全部数据
            </Button>
          ) : null}
        </div>
        {!summary?.columns?.length ? (
          <Text type="secondary" style={{ display: 'block', marginTop: 8 }}>检查数据后将显示变量列表。</Text>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', marginTop: 8 }}>
            {summary.columns.map((column) => (
              <VariableCard key={column.name} column={column} onClick={handleVariableClick} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
