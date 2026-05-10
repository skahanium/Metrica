import React from 'react';
import { Typography, Table, Card, Space, Tag } from 'antd';
import type { DataResult, DescribeVariable, SummarizeVariable, TabulateRow } from '../types/protocol';

const { Text } = Typography;

interface DataResultBlockProps {
  command: string;
  result: DataResult;
}

export const DataResultBlock: React.FC<DataResultBlockProps> = ({ command, result }) => {
  const renderDescribe = () => {
    if (result.kind !== 'describe') return null;
    const dataSource = result.variables.map((col: DescribeVariable, idx) => ({
      key: idx,
      name: col.name,
      inferred_type: col.inferred_type || 'unknown',
      missing_count: col.missing_count || 0,
      non_missing_count: col.non_missing_count || 0,
    }));

    const columns = [
      { title: '变量名', dataIndex: 'name', key: 'name', width: 150 },
      { title: '推断类型', dataIndex: 'inferred_type', key: 'inferred_type', width: 100 },
      { title: '非缺失', dataIndex: 'non_missing_count', key: 'non_missing_count', width: 100 },
      {
        title: '缺失值', dataIndex: 'missing_count', key: 'missing_count', width: 80,
        render: (val: number) => val > 0 ? <Tag color="gold">{val}</Tag> : <Text type="secondary">0</Text>,
      },
    ];

    return (
      <Card size="small">
        <Space direction="vertical" style={{ width: '100%' }}>
          <Text strong>数据结构: {result.dataset_summary.row_count} 行 × {result.dataset_summary.column_count} 列</Text>
          <Table
            dataSource={dataSource}
            columns={columns}
            size="small"
            pagination={false}
            scroll={{ y: 300 }}
          />
        </Space>
      </Card>
    );
  };

  const renderSummarize = () => {
    if (result.kind !== 'summarize') return null;
    const dataSource = result.variables.map((stat: SummarizeVariable, idx) => ({
      key: idx,
      name: stat.name,
      inferred_type: stat.inferred_type || 'unknown',
      obs: stat.obs,
      mean: stat.mean,
      std_dev: stat.std_dev,
      min: stat.min,
      max: stat.max,
    }));

    const columns = [
      { title: '变量名', dataIndex: 'name', key: 'name', width: 150 },
      { title: '类型', dataIndex: 'inferred_type', key: 'inferred_type', width: 120 },
      { title: 'Obs', dataIndex: 'obs', key: 'obs', width: 80 },
      { title: 'Mean', dataIndex: 'mean', key: 'mean', width: 100, render: (value: number | null) => value === null ? <Text type="secondary">NA</Text> : value.toFixed(4) },
      { title: 'Std. dev.', dataIndex: 'std_dev', key: 'std_dev', width: 110, render: (value: number | null) => value === null ? <Text type="secondary">NA</Text> : value.toFixed(4) },
      { title: 'Min', dataIndex: 'min', key: 'min', width: 100, render: (value: number | null) => value === null ? <Text type="secondary">NA</Text> : value.toFixed(4) },
      { title: 'Max', dataIndex: 'max', key: 'max', width: 100, render: (value: number | null) => value === null ? <Text type="secondary">NA</Text> : value.toFixed(4) },
    ];

    return (
      <Card size="small">
        <Space direction="vertical" style={{ width: '100%' }}>
          <Text strong>描述性统计: {result.variables.length} 个变量</Text>
          <Table
            dataSource={dataSource}
            columns={columns}
            size="small"
            pagination={false}
            scroll={{ y: 300 }}
          />
        </Space>
      </Card>
    );
  };

  const renderTabulate = () => {
    if (result.kind !== 'tabulate') return null;
    const dataSource = result.rows.map((item: TabulateRow, idx) => ({
      key: idx,
      value: item.value,
      count: item.count,
      pct: item.pct.toFixed(1),
      cum_pct: item.cum_pct.toFixed(1),
    }));

    const columns = [
      { title: '值', dataIndex: 'value', key: 'value', width: 200 },
      { title: '频数', dataIndex: 'count', key: 'count', width: 100 },
      { title: '百分比', dataIndex: 'pct', key: 'pct', width: 100, render: (val: string) => `${val}%` },
      { title: '累计百分比', dataIndex: 'cum_pct', key: 'cum_pct', width: 120, render: (val: string) => `${val}%` },
    ];

    return (
      <Card size="small">
        <Space direction="vertical" style={{ width: '100%' }}>
          <Text strong>频数分布: {result.variable}，有效样本 {result.total}，缺失 {result.missing_count}</Text>
          <Table
            dataSource={dataSource}
            columns={columns}
            size="small"
            pagination={false}
            scroll={{ y: 300 }}
          />
        </Space>
      </Card>
    );
  };

  const renderContent = () => {
    switch (result.kind) {
      case 'describe': return renderDescribe();
      case 'summarize': return renderSummarize();
      case 'tabulate': return renderTabulate();
      default: return null;
    }
  };

  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ marginBottom: 8 }}>
        <Text code style={{ fontSize: 13 }}>&gt; {command}</Text>
      </div>
      {renderContent()}
    </div>
  );
};
