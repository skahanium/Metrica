import { Card, Table, Tag } from 'antd';
import { useModelStore } from '../stores/modelStore';

export function DEFFSummary() {
  const lastResult = useModelStore((s) => s.lastResult);

  if (!lastResult || !lastResult.design_effects) return null;

  const deffEntries = lastResult.design_effects;

  const columns = [
    { title: '变量', dataIndex: 'term', key: 'term' },
    {
      title: 'SRS 标准误', dataIndex: 'srs_se', key: 'srs_se',
      render: (v: number) => v?.toFixed(6),
    },
    {
      title: 'Survey 标准误', dataIndex: 'survey_se', key: 'survey_se',
      render: (v: number) => v?.toFixed(6),
    },
    {
      title: 'DEFF', dataIndex: 'deff', key: 'deff',
      render: (v: number) => {
        const color = v > 3 ? 'red' : v > 2 ? 'orange' : 'green';
        return <Tag color={color}>{v.toFixed(3)}</Tag>;
      },
    },
    {
      title: '有效 n', dataIndex: 'n_eff', key: 'n_eff',
      render: (v: number) => Math.round(v),
    },
  ];

  const data = deffEntries.map((item: { term: string }, i: number) => ({
    ...item,
    key: item.term || i,
  }));

  const meanDeff = deffEntries.length > 0
    ? deffEntries.reduce((sum: number, d: { deff: number }) => sum + d.deff, 0) / deffEntries.length
    : 1.0;

  return (
    <Card
      size="small"
      title="设计效应 (DEFF)"
      style={{ marginBottom: 16 }}
      extra={
        <span>
          平均 DEFF: <Tag color={meanDeff > 2 ? 'orange' : 'green'}>{meanDeff.toFixed(3)}</Tag>
        </span>
      }
    >
      <Table
        columns={columns}
        dataSource={data}
        pagination={false}
        size="small"
        summary={() =>
          data.length > 0 ? (
            <Table.Summary.Row>
              <Table.Summary.Cell index={0}>平均</Table.Summary.Cell>
              <Table.Summary.Cell index={1}>-</Table.Summary.Cell>
              <Table.Summary.Cell index={2}>-</Table.Summary.Cell>
              <Table.Summary.Cell index={3}>
                <Tag color={meanDeff > 2 ? 'orange' : 'green'}>{meanDeff.toFixed(3)}</Tag>
              </Table.Summary.Cell>
              <Table.Summary.Cell index={4}>
                {Math.round(
                  deffEntries.reduce((sum: number, d: { n_eff: number }) => sum + d.n_eff, 0) /
                    deffEntries.length
                )}
              </Table.Summary.Cell>
            </Table.Summary.Row>
          ) : undefined
        }
      />
    </Card>
  );
}
