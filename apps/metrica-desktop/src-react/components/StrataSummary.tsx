import { Card, Table } from 'antd';
import { useModelStore } from '../stores/modelStore';

export function StrataSummary() {
  const lastResult = useModelStore((s) => s.lastResult);

  if (!lastResult || !lastResult.strata_summary) return null;

  const strataEntries = lastResult.strata_summary;

  const columns = [
    { title: '层', dataIndex: 'stratum', key: 'stratum' },
    { title: '样本量 (n)', dataIndex: 'n', key: 'n' },
    {
      title: '权重总和', dataIndex: 'sum_weights', key: 'sum_weights',
      render: (v: number) => v?.toFixed(2),
    },
    {
      title: '平均权重', dataIndex: 'mean_weight', key: 'mean_weight',
      render: (v: number) => v?.toFixed(4),
    },
    {
      title: '最小权重', dataIndex: 'min_weight', key: 'min_weight',
      render: (v: number) => v?.toFixed(4),
    },
    {
      title: '最大权重', dataIndex: 'max_weight', key: 'max_weight',
      render: (v: number) => v?.toFixed(4),
    },
  ];

  const data = strataEntries.map((item: { stratum: string }, i: number) => ({
    ...item,
    key: item.stratum || i,
  }));

  const totalN = strataEntries.reduce((sum: number, s: { n: number }) => sum + s.n, 0);
  const totalWeights = strataEntries.reduce((sum: number, s: { sum_weights: number }) => sum + s.sum_weights, 0);

  return (
    <Card size="small" title="分层摘要" style={{ marginBottom: 16 }}>
      <Table
        columns={columns}
        dataSource={data}
        pagination={false}
        size="small"
        summary={() =>
          data.length > 0 ? (
            <Table.Summary.Row>
              <Table.Summary.Cell index={0}>合计</Table.Summary.Cell>
              <Table.Summary.Cell index={1}>{totalN}</Table.Summary.Cell>
              <Table.Summary.Cell index={2}>{totalWeights.toFixed(2)}</Table.Summary.Cell>
              <Table.Summary.Cell index={3}>-</Table.Summary.Cell>
              <Table.Summary.Cell index={4}>-</Table.Summary.Cell>
              <Table.Summary.Cell index={5}>-</Table.Summary.Cell>
            </Table.Summary.Row>
          ) : undefined
        }
      />
    </Card>
  );
}
