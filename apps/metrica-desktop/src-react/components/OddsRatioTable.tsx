import { Card, Table, Switch, Typography } from 'antd';
import { useState } from 'react';
import { useModelStore } from '../stores/modelStore';

export function OddsRatioTable() {
  const lastResult = useModelStore((s) => s.lastResult);
  const [showOR, setShowOR] = useState(true);

  if (!lastResult) return null;

  const irr = lastResult.incidence_rate_ratios;
  const ors = lastResult.odds_ratios;

  // Poisson: show IRR table
  if (lastResult.glance?.model === 'poisson' && irr) {
    const columns = [
      { title: '变量', dataIndex: 'term', key: 'term' },
      { title: '发病率比 (IRR)', dataIndex: 'irr', key: 'irr', render: (v: number) => v?.toFixed(4) },
    ];
    const data = irr.map((item: { term: string }, i: number) => ({ ...item, key: item.term ?? i }));

    return (
      <Card size="small" title="发病率比" style={{ marginBottom: 16 }}>
        <Table columns={columns} dataSource={data} pagination={false} size="small" />
      </Card>
    );
  }

  // Logit/Probit: show OR/coefficient toggle table
  if (ors) {
    const tidyRows = lastResult.tidy || [];

    const columns = showOR ? [
      { title: '变量', dataIndex: 'term', key: 'term' },
      { title: '比值比 (OR)', dataIndex: 'odds_ratio', key: 'or', render: (v: number) => v.toFixed(4) },
      { title: '95% CI 下限', dataIndex: 'ci_lower', key: 'lo', render: (v: number) => v.toFixed(4) },
      { title: '95% CI 上限', dataIndex: 'ci_upper', key: 'hi', render: (v: number) => v.toFixed(4) },
    ] : [
      { title: '变量', dataIndex: 'term', key: 'term' },
      { title: '系数', dataIndex: 'estimate', key: 'est', render: (v: number) => v?.toFixed(4) },
      { title: '标准误', dataIndex: 'std_error', key: 'se', render: (v: number) => v?.toFixed(4) },
      { title: 'z', dataIndex: 'statistic', key: 'z', render: (v: number) => v?.toFixed(4) },
      { title: 'p', dataIndex: 'p_value', key: 'p', render: (v: number) => v?.toFixed(4) },
    ];

    const data = ors.map((or: { term: string }, i: number) => ({
      ...or,
      estimate: tidyRows[i]?.estimate,
      std_error: tidyRows[i]?.std_error,
      statistic: tidyRows[i]?.statistic,
      p_value: tidyRows[i]?.p_value,
      key: or.term,
    }));

    return (
      <Card size="small" title="系数估计" style={{ marginBottom: 16 }}
        extra={
          <span>
            <Typography.Text type="secondary" style={{ marginRight: 8 }}>系数</Typography.Text>
            <Switch checked={showOR} onChange={setShowOR} size="small" />
            <Typography.Text type="secondary" style={{ marginLeft: 8 }}>OR</Typography.Text>
          </span>
        }>
        <Table columns={columns} dataSource={data} pagination={false} size="small" />
      </Card>
    );
  }

  return null;
}
