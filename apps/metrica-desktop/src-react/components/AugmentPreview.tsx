import { AgGridReact } from 'ag-grid-react';
import { Card, Empty } from 'antd';
import { useModelStore } from '../stores/modelStore';
import type { ColDef } from 'ag-grid-community';
import type { AugmentRow } from '../types/protocol';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-alpine.css';

const COLUMNS: ColDef<AugmentRow>[] = [
  { field: 'fitted', headerName: '拟合值', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'residual', headerName: '残差', width: 130, valueFormatter: (p) => p.value?.toFixed(6) },
  { field: 'std_residual', headerName: '标准化残差', width: 130, valueFormatter: (p) => p.value?.toFixed(4) },
  { field: 'leverage', headerName: '杠杆值', width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
  { field: 'cooks_d', headerName: "Cook's D", width: 120, valueFormatter: (p) => p.value?.toFixed(4) },
];

export function AugmentPreview() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult?.augment_preview?.length) return <Empty description="无增强数据。请在运行时开启 return_augment。" />;

  return (
    <Card size="small">
      <div className="ag-theme-alpine" style={{ height: Math.min(400, (lastResult.augment_preview!.length + 1) * 42) }}>
        <AgGridReact<AugmentRow> rowData={lastResult.augment_preview} columnDefs={COLUMNS} domLayout="autoHeight" />
      </div>
    </Card>
  );
}
