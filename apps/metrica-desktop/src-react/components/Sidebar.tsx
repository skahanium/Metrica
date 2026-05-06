import { Typography } from 'antd';
import { DataSourcePanel } from './DataSourcePanel';
import { VariableCard } from './VariableCard';
import { useDatasetStore } from '../stores/datasetStore';
import { useProjectStore } from '../stores/projectStore';
import { useCommandStore } from '../stores/commandStore';

const { Title, Text } = Typography;

export function Sidebar() {
  const summary = useDatasetStore((s) => s.summary);
  const projectPath = useProjectStore((s) => s.projectPath);

  const handleVariableClick = (name: string) => {
    useCommandStore.getState().setInput(name, name.length);
  };

  return (
    <div style={{ padding: 16, width: 280, background: '#fafafa', borderRight: '1px solid #f0f0f0', height: '100%' }}>
      <Title level={5}>数据源</Title>
      <DataSourcePanel />
      {projectPath && (
        <div style={{ marginTop: 12 }}>
          <Title level={5}>项目</Title>
          <Text type="secondary" style={{ fontSize: 12, wordBreak: 'break-all' }}>{projectPath}</Text>
        </div>
      )}
      <div style={{ marginTop: 24 }}>
        <Title level={5}>变量</Title>
        {!summary?.columns?.length ? (
          <Text type="secondary">检查数据后将显示变量列表。</Text>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {summary.columns.map((column) => (
              <VariableCard key={column.name} column={column} onClick={handleVariableClick} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
