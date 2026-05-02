import { Empty } from 'antd';
import { AgGridReact } from 'ag-grid-react';
import { useDatasetStore } from '../stores/datasetStore';
import { useTransformStore } from '../stores/transformStore';

export function DataPreviewTable() {
  const summary = useDatasetStore((s) => s.summary);
  const lastTransformResult = useTransformStore((s) => s.lastTransformResult);

  const preview = lastTransformResult?.preview;
  const fallbackRows = summary?.preview ?? summary?.preview_rows ?? [];
  const rows = preview?.rows ?? fallbackRows;
  const columns = preview?.columns ?? (rows[0] ? Object.keys(rows[0]) : []);

  if (!rows.length || !columns.length) {
    return <Empty description="暂无数据预览" />;
  }

  return (
    <div className="ag-theme-alpine" style={{ height: Math.min(360, (rows.length + 1) * 42), width: '100%' }}>
      <AgGridReact
        rowData={rows}
        columnDefs={columns.map((field) => ({ field, sortable: true, filter: true, resizable: true }))}
        domLayout="autoHeight"
      />
    </div>
  );
}
