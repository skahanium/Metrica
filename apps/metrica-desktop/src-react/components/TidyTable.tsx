import { useMemo } from 'react';
import { AgGridReact } from 'ag-grid-react';
import { Card } from 'antd';
import type { ColDef } from 'ag-grid-community';
import type { TidyRow, ModelResult } from '../types/protocol';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-alpine.css';

const COLUMNS: ColDef<TidyRow>[] = [
  { field: 'term', headerName: '参数', width: 150 },
  { field: 'estimate', headerName: '估计值', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'std_error', headerName: '标准误', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'statistic', headerName: '统计量', width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
  { field: 'p_value', headerName: 'p 值', width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
];

interface TidyTableProps {
  result?: ModelResult;
}

export function TidyTable({ result }: TidyTableProps) {
  const rowData = useMemo(() => result?.tidy ?? [], [result]);

  if (!result || !rowData.length) return null;

  const gridHeight = Math.min(400, Math.max(120, (rowData.length + 1) * 42));

  return (
    <Card size="small">
      {result.vcov_label && (
        <div style={{ marginBottom: 8, color: '#8c8c8c', fontSize: 13 }}>{result.vcov_label}</div>
      )}
      <div className="ag-theme-alpine" style={{ height: gridHeight, width: '100%' }}>
        <AgGridReact<TidyRow>
          rowData={rowData}
          columnDefs={COLUMNS}
        />
      </div>
    </Card>
  );
}
