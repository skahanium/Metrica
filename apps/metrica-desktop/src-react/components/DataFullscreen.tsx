import React, { useState, useMemo } from 'react';
import { Button, Space, Empty, Typography } from 'antd';
import { ArrowLeftOutlined, FilterOutlined, SwapOutlined, ExportOutlined } from '@ant-design/icons';
import { AgGridReact } from 'ag-grid-react';
import { ColDef } from 'ag-grid-community';
import { useDatasetStore } from '../stores/datasetStore';
import { useAppStore } from '../stores/appStore';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-alpine.css';

const { Text } = Typography;

export const DataFullscreen: React.FC = () => {
  const summary = useDatasetStore((s) => s.summary);
  const setDataFullscreen = useAppStore((s) => s.setDataFullscreen);
  const [selectedColIndex, setSelectedColIndex] = useState<number | null>(null);

  const columnDefs: ColDef[] = useMemo(() => {
    if (!summary?.columns) return [];
    return [
      { headerName: '#', field: '_idx', width: 60, sortable: false, filter: false },
      ...summary.columns.map((col, idx) => ({
        field: `col_${idx}`,
        headerName: col.name,
        sortable: true,
        filter: true,
        resizable: true,
      })),
    ];
  }, [summary]);

  const rowData = useMemo(() => {
    if (!summary?.preview) return [];
    const cols = summary.columns;
    return summary.preview.map((row, i) => {
      const obj: Record<string, unknown> = { _idx: i + 1 };
      const rowRecord = row as Record<string, unknown>;
      cols.forEach((col, j) => {
        obj[`col_${j}`] = rowRecord[col.name];
      });
      return obj;
    });
  }, [summary]);

  if (!summary) return <Empty description="未加载数据" />;

  const selectedCol = selectedColIndex !== null && selectedColIndex < summary.columns.length
    ? summary.columns[selectedColIndex]
    : null;

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: 0 }}>
      {/* Toolbar */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 16px', borderBottom: '1px solid #f0f0f0' }}>
        <Space>
          <Button icon={<ArrowLeftOutlined />} onClick={() => setDataFullscreen(false)}>返回结果</Button>
          <Text strong>{summary.nrows} obs x {summary.ncols} vars</Text>
        </Space>
        <Space>
          <Button icon={<FilterOutlined />}>筛选</Button>
          <Button icon={<SwapOutlined />}>变换</Button>
          <Button icon={<ExportOutlined />}>导出</Button>
        </Space>
      </div>

      {/* Data table */}
      <div className="ag-theme-alpine" style={{ flex: 1, overflow: 'auto' }}>
        <AgGridReact
          columnDefs={columnDefs}
          rowData={rowData}
          defaultColDef={{ flex: 1, minWidth: 100 }}
          onCellClicked={(e) => {
            if (e.colDef.field && e.colDef.field !== '_idx') {
              const match = e.colDef.field.match(/^col_(\d+)$/);
              if (match) {
                setSelectedColIndex(parseInt(match[1], 10));
              }
            }
          }}
        />
      </div>

      {/* Column stats panel */}
      {selectedCol && (
        <div style={{ padding: '8px 16px', borderTop: '1px solid #f0f0f0', background: '#fafafa', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Space>
            <Text strong>{selectedCol.name}</Text>
            <Text type="secondary">{selectedCol.inferred_type || selectedCol.type || '?'}</Text>
            {(selectedCol.missing_count ?? selectedCol.missing) ? (
              <Text type="warning">缺失: {selectedCol.missing_count ?? selectedCol.missing}</Text>
            ) : null}
          </Space>
          <Button size="small" onClick={() => setSelectedColIndex(null)}>关闭</Button>
        </div>
      )}
    </div>
  );
};
