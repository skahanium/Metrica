import { useMemo } from 'react';
import { Card, Table, Typography } from 'antd';
import type { TableColumnsType } from 'antd';
import type { TidyRow, ModelResult } from '../types/protocol';

const { Text } = Typography;

const BASE_COLUMNS: TableColumnsType<TidyRow> = [
  { dataIndex: 'term', title: '参数', width: 180 },
  { dataIndex: 'estimate', title: '估计值', align: 'right', render: (v: number | null) => v != null ? v.toFixed(6) : '—' },
  { dataIndex: 'std_error', title: '标准误', align: 'right', render: (v: number | null) => v != null ? v.toFixed(6) : '—' },
  { dataIndex: 'statistic', title: '统计量', align: 'right', render: (v: number | null) => v != null ? v.toFixed(4) : '—' },
  { dataIndex: 'p_value', title: 'p 值', align: 'right', render: (v: number | null) => v != null ? v.toFixed(4) : '—' },
  { dataIndex: 'ci_lower', title: 'CI 下限', align: 'right', render: (v: number | null | undefined) => v != null ? v.toFixed(6) : '—' },
  { dataIndex: 'ci_upper', title: 'CI 上限', align: 'right', render: (v: number | null | undefined) => v != null ? v.toFixed(6) : '—' },
];

/** 将后端字段名 (name/stderror/pvalue) 映射为前端 TidyRow 字段名 */
function normalizeRows(raw: Record<string, unknown>[]): TidyRow[] {
  return raw.map((r) => ({
    equation: (r.equation as string | undefined) || undefined,
    term: (r.name ?? r.term ?? '') as string,
    estimate: (r.estimate ?? null) as number | null,
    std_error: (r.stderror ?? r.std_error ?? null) as number | null,
    statistic: (r.statistic ?? null) as number | null,
    p_value: (r.pvalue ?? r.p_value ?? null) as number | null,
    ci_lower: (r.ci_lower ?? undefined) as number | undefined,
    ci_upper: (r.ci_upper ?? undefined) as number | undefined,
  }));
}

interface TidyTableProps {
  result?: ModelResult;
}

export function TidyTable({ result }: TidyTableProps) {
  const rowData = useMemo(
    () => normalizeRows((result?.tidy ?? []) as unknown as Record<string, unknown>[]),
    [result],
  );

  const showEquation = useMemo(() => rowData.some((r) => !!r.equation), [rowData]);

  const columns = useMemo(() => {
    if (!showEquation) return BASE_COLUMNS;
    const eqCol: TableColumnsType<TidyRow>[0] = {
      dataIndex: 'equation',
      title: '方程',
      width: 200,
      ellipsis: true,
    };
    return [eqCol, ...BASE_COLUMNS];
  }, [showEquation]);

  if (!result || !rowData.length) return null;

  return (
    <Card size="small">
      {result.vcov_label && (
        <Text type="secondary" style={{ display: 'block', marginBottom: 8 }}>{result.vcov_label}</Text>
      )}
      <div style={{ overflowX: 'auto' }}>
        <Table<TidyRow>
          bordered
          columns={columns}
          dataSource={rowData}
          pagination={false}
          rowKey={(r) => `${r.equation ?? ''}::${r.term}`}
          size="small"
        />
      </div>
    </Card>
  );
}
