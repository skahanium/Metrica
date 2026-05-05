import React from 'react';
import { Table, Tag, Card } from 'antd';

interface UnitRootTestResult {
  test_name: string;
  test_statistic: number;
  p_value: number;
  lags_used: number;
  critical_values: Record<number, number>;
  conclusion: 'reject' | 'fail_to_reject';
}

interface UnitRootTableProps {
  adf?: UnitRootTestResult;
  pp?: UnitRootTestResult;
  kpss?: UnitRootTestResult;
}

export const UnitRootTable: React.FC<UnitRootTableProps> = ({
  adf,
  pp,
  kpss
}) => {
  const dataSource = [
    adf && {
      key: 'adf',
      test: 'ADF',
      statistic: adf.test_statistic.toFixed(4),
      p_value: adf.p_value.toFixed(4),
      lags: adf.lags_used,
      conclusion: adf.conclusion === 'reject' ?
        <Tag color="green">平稳</Tag> :
        <Tag color="red">非平稳</Tag>
    },
    pp && {
      key: 'pp',
      test: 'Phillips-Perron',
      statistic: pp.test_statistic.toFixed(4),
      p_value: pp.p_value.toFixed(4),
      lags: pp.lags_used,
      conclusion: pp.conclusion === 'reject' ?
        <Tag color="green">平稳</Tag> :
        <Tag color="red">非平稳</Tag>
    },
    kpss && {
      key: 'kpss',
      test: 'KPSS',
      statistic: kpss.test_statistic.toFixed(4),
      p_value: kpss.p_value.toFixed(4),
      lags: kpss.lags_used,
      conclusion: kpss.conclusion === 'reject' ?
        <Tag color="red">非平稳</Tag> :
        <Tag color="green">平稳</Tag>
    }
  ].filter(Boolean);

  const columns = [
    { title: '检验方法', dataIndex: 'test', key: 'test' },
    { title: '统计量', dataIndex: 'statistic', key: 'statistic' },
    { title: 'p 值', dataIndex: 'p_value', key: 'p_value' },
    { title: '滞后', dataIndex: 'lags', key: 'lags' },
    { title: '结论 (5%)', dataIndex: 'conclusion', key: 'conclusion' }
  ];

  return (
    <Card title="单位根检验结果" size="small">
      <Table
        dataSource={dataSource}
        columns={columns}
        pagination={false}
        size="small"
      />
    </Card>
  );
};

export default UnitRootTable;
