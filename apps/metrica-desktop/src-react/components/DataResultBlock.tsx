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
      dtype: col.dtype || col.inferred_type || 'unknown',
      missing_count: col.missing_count ?? 0,
      unique_count: col.unique_count ?? 0,
      label: col.label || col.name,
    }));

    const columns = [
      { title: '变量名', dataIndex: 'name', key: 'name', width: 140 },
      { title: '类型', dataIndex: 'dtype', key: 'dtype', width: 90 },
      { title: '标签', dataIndex: 'label', key: 'label', width: 140, ellipsis: true },
      { title: '唯一值', dataIndex: 'unique_count', key: 'unique_count', width: 80 },
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
    const formatNum = (v: number | null) => v === null ? <Text type="secondary">NA</Text> : v.toFixed(4);
    const dataSource = result.variables.map((stat: SummarizeVariable, idx) => ({
      key: idx,
      name: stat.name,
      dtype: stat.dtype || stat.inferred_type || '',
      obs: stat.obs,
      mean: stat.mean,
      std_dev: stat.std_dev,
      min: stat.min,
      max: stat.max,
      p25: stat.p25 ?? null,
      p50: stat.p50 ?? null,
      p75: stat.p75 ?? null,
    }));

    const columns = [
      { title: '变量名', dataIndex: 'name', key: 'name', width: 120 },
      { title: 'N', dataIndex: 'obs', key: 'obs', width: 70 },
      { title: 'Mean', dataIndex: 'mean', key: 'mean', width: 90, render: formatNum },
      { title: 'SD', dataIndex: 'std_dev', key: 'std_dev', width: 90, render: formatNum },
      { title: 'Min', dataIndex: 'min', key: 'min', width: 90, render: formatNum },
      { title: 'P25', dataIndex: 'p25', key: 'p25', width: 90, render: formatNum },
      { title: 'P50', dataIndex: 'p50', key: 'p50', width: 90, render: formatNum },
      { title: 'P75', dataIndex: 'p75', key: 'p75', width: 90, render: formatNum },
      { title: 'Max', dataIndex: 'max', key: 'max', width: 90, render: formatNum },
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

  const renderRunsTable = () => {
    if (result.kind !== 'runs') return null;
    const dataSource = result.runs.map((r, idx) => ({ key: idx, ...r }));
    const columns = [
      { title: 'run_id', dataIndex: 'run_id', key: 'run_id', width: 220, ellipsis: true },
      { title: 'action', dataIndex: 'action', key: 'action', width: 100 },
      { title: 'model', dataIndex: 'model_type', key: 'model_type', width: 120 },
      { title: 'dataset', dataIndex: 'dataset_path', key: 'dataset_path', ellipsis: true },
      { title: 'status', dataIndex: 'status', key: 'status', width: 90 },
      { title: 'finished_at', dataIndex: 'finished_at', key: 'finished_at', width: 180 },
    ];
    return (
      <Card size="small">
        <Space direction="vertical" style={{ width: '100%' }}>
          <Text strong>
            运行记录（{result.dataset_summary.row_count} 行数据集上下文 × {result.runs.length} 条记录）
          </Text>
          <Table dataSource={dataSource} columns={columns} size="small" pagination={false} scroll={{ x: 900 }} />
        </Space>
      </Card>
    );
  };

  const renderExportPreview = () => {
    if (result.kind !== 'export_preview') return null;
    return (
      <Card size="small">
        <Space direction="vertical" style={{ width: '100%' }}>
          <Text strong>导出摘要</Text>
          <Text>run_id: <Text code>{result.run_id}</Text></Text>
          <Text>格式: <Text code>{result.format}</Text></Text>
          <Text>目标路径: {result.target_path ? <Text code>{result.target_path}</Text> : <Text type="secondary">（浏览器下载，路径为建议名）</Text>}</Text>
          <Text type="secondary">内容预览（截断）：</Text>
          <pre style={{ maxHeight: 200, overflow: 'auto', fontSize: 12, background: 'var(--m-panel-bg)' }}>
            {result.content_preview}
          </pre>
        </Space>
      </Card>
    );
  };

  const renderModelComparison = () => {
    if (result.kind !== 'model_comparison') return null;
    const keys = result.rows.length > 0 ? Object.keys(result.rows[0]) : [];
    const columns = keys.map((k) => ({
      title: k,
      dataIndex: k,
      key: k,
      ellipsis: true,
      render: (v: string | number | null) => (v === null || v === undefined ? <Text type="secondary">NA</Text> : String(v)),
    }));
    const dataSource = result.rows.map((row, idx) => ({ key: idx, ...row }));
    return (
      <Card size="small">
        <Space direction="vertical" style={{ width: '100%' }}>
          <Text strong>模型对比（{result.family}）</Text>
          <Table dataSource={dataSource} columns={columns} size="small" pagination={false} scroll={{ x: true }} />
        </Space>
      </Card>
    );
  };

  const renderContent = () => {
    switch (result.kind) {
      case 'describe': return renderDescribe();
      case 'summarize': return renderSummarize();
      case 'tabulate': return renderTabulate();
      case 'runs': return renderRunsTable();
      case 'export_preview': return renderExportPreview();
      case 'model_comparison': return renderModelComparison();
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
