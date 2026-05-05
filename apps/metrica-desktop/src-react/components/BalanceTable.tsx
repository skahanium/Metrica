import { Card, Table, Tag } from 'antd';
import { useModelStore } from '../stores/modelStore';

export function BalanceTable() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult || lastResult.glance.model !== 'psm') return null;

  const balance = (lastResult as any).balance_table as Array<{
    variable: string; mean_treated: number; mean_control: number; std_bias: number;
  }> | undefined;

  if (!balance || balance.length === 0) return null;

  const columns = [
    { title: '变量', dataIndex: 'variable', key: 'variable' },
    { title: '处理组均值', dataIndex: 'mean_treated', key: 'mt', render: (v: number) => v?.toFixed(4) },
    { title: '对照组均值', dataIndex: 'mean_control', key: 'mc', render: (v: number) => v?.toFixed(4) },
    {
      title: '标准化偏差', dataIndex: 'std_bias', key: 'bias',
      render: (v: number) => {
        const absV = Math.abs(v);
        const color = absV < 10 ? 'green' : absV < 25 ? 'orange' : 'red';
        return <Tag color={color}>{v?.toFixed(2)}%</Tag>;
      },
    },
  ];

  return (
    <Card size="small" title="PSM 协变量平衡性检验" style={{ marginBottom: 16 }}>
      <Table columns={columns} dataSource={balance.map((item, i) => ({ ...item, key: item.variable || i }))} pagination={false} size="small" />
    </Card>
  );
}
