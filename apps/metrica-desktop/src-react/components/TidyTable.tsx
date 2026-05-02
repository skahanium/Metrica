import { useMemo } from 'react';
import { AgGridReact } from 'ag-grid-react';
import { Card } from 'antd';
import { useModelStore } from '../stores/modelStore';
import { EmptyState } from './EmptyState';
import type { ColDef } from 'ag-grid-community';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-alpine.css';
import type { TidyRow } from '../types/protocol';

const COLUMNS: ColDef<TidyRow>[] = [
  { field: 'term', headerName: '参数', width: 150 },
  { field: 'estimate', headerName: '估计值', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'std_error', headerName: '标准误', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'statistic', headerName: '统计量', width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
  { field: 'p_value', headerName: 'p 值', width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
];

export function TidyTable() {
  const lastResult = useModelStore((s) => s.lastResult);
  const rowData = useMemo(() => lastResult?.tidy ?? [], [lastResult]);

  if (!lastResult) return <EmptyState title="尚未运行模型" />;

  return (
    <Card size="small">
      {lastResult.vcov_label && (
        <div style={{ marginBottom: 8, color: '#8c8c8c', fontSize: 13 }}>{lastResult.vcov_label}</div>
      )}
      <div className="ag-theme-alpine" style={{ height: Math.min(400, (rowData.length + 1) * 42) }}>
        <AgGridReact<TidyRow>
          rowData={rowData}
          columnDefs={COLUMNS}
          domLayout="autoHeight"
        />
      </div>
    </Card>
  );
}
