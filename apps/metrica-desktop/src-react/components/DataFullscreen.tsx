import React, { useState, useMemo, useEffect } from 'react';
import { Button, Space, Empty, Typography, Tag, Drawer, message } from 'antd';
import { ArrowLeftOutlined, FilterOutlined, SwapOutlined, ExportOutlined } from '@ant-design/icons';
import { AgGridReact } from 'ag-grid-react';
import { ColDef } from 'ag-grid-community';
import { useDatasetStore } from '../stores/datasetStore';
import { useAppStore } from '../stores/appStore';
import { loadFullPreview } from '../services/commandExecutor';
import { DataOperationsPanel } from './DataOperationsPanel';
import { downloadText } from '../stores/exportStore';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-quartz.css';

const { Text } = Typography;

const missingLike = (value: unknown) =>
  value === null || value === undefined || value === '' || value === 'missing';

function csvValue(value: unknown): string {
  if (missingLike(value)) return '';
  const text = String(value);
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function buildCsv(columns: string[], rows: Record<string, unknown>[]): string {
  const header = columns.map(csvValue).join(',');
  const body = rows.map((row) => columns.map((col) => csvValue(row[col])).join(','));
  return [header, ...body].join('\n');
}

export const DataFullscreen: React.FC = () => {
  const summary = useDatasetStore((s) => s.summary);
  const activePath = useDatasetStore((s) => s.activePath);
  const setSummary = useDatasetStore((s) => s.setSummary);
  const browseColumns = useDatasetStore((s) => s.browseColumns);
  const browseReadonly = useDatasetStore((s) => s.browseReadonly);
  const clearBrowseContext = useDatasetStore((s) => s.clearBrowseContext);
  const setDataFullscreen = useAppStore((s) => s.setDataFullscreen);
  const [selectedColIndex, setSelectedColIndex] = useState<number | null>(null);
  const [isLoadingFullRows, setIsLoadingFullRows] = useState(false);
  const [fullRowsError, setFullRowsError] = useState<string | null>(null);
  const [showFilters, setShowFilters] = useState(false);
  const [transformOpen, setTransformOpen] = useState(false);

  useEffect(() => {
    if (!summary || !activePath || summary.preview.length >= summary.nrows) return;
    let cancelled = false;

    setIsLoadingFullRows(true);
    setFullRowsError(null);
    loadFullPreview(activePath)
      .then((nextSummary) => {
        if (cancelled) return;
        if (nextSummary.preview.length > summary.preview.length) {
          setSummary(nextSummary);
        }
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setFullRowsError(err instanceof Error ? err.message : '加载完整数据失败');
      })
      .finally(() => {
        if (!cancelled) setIsLoadingFullRows(false);
      });

    return () => {
      cancelled = true;
    };
  }, [activePath, setSummary, summary]);

  const visibleColumns = useMemo(() => {
    if (!summary?.columns) return [];
    if (!browseColumns || browseColumns.length === 0) return summary.columns;
    const allowed = new Set(browseColumns);
    return summary.columns.filter((col) => allowed.has(col.name));
  }, [browseColumns, summary?.columns]);

  const columnDefs: ColDef[] = useMemo(() => {
    if (!summary?.columns) return [];
    return [
      {
        headerName: '#',
        field: '_idx',
        width: 72,
        maxWidth: 86,
        pinned: 'left',
        sortable: false,
        filter: false,
        cellClass: 'metrica-row-index',
      },
      ...visibleColumns.map((col, idx) => ({
        field: `col_${idx}`,
        headerName: col.name,
        sortable: true,
        filter: true,
        resizable: true,
        minWidth: 132,
        tooltipField: `col_${idx}`,
        floatingFilter: showFilters,
        cellClass: (params: { value: unknown }) => missingLike(params.value) ? 'metrica-missing-cell' : '',
        valueFormatter: (params: { value: unknown }) => missingLike(params.value) ? '缺失' : String(params.value),
      })),
    ];
  }, [showFilters, summary?.columns, visibleColumns]);

  const rowData = useMemo(() => {
    if (!summary?.preview) return [];
    const cols = visibleColumns;
    return summary.preview.map((row, i) => {
      const obj: Record<string, unknown> = { _idx: i + 1 };
      const rowRecord = row as Record<string, unknown>;
      cols.forEach((col, j) => {
        obj[`col_${j}`] = rowRecord[col.name];
      });
      return obj;
    });
  }, [summary, visibleColumns]);

  if (!summary) return <Empty description="未加载数据" />;

  const selectedCol = selectedColIndex !== null && selectedColIndex < visibleColumns.length
    ? visibleColumns[selectedColIndex]
    : null;

  const missingCols = visibleColumns.filter((col) => (col.missing_count ?? col.missing ?? 0) > 0).length;
  const loadedText = rowData.length === summary.nrows
    ? `${rowData.length} 行全部载入`
    : `${rowData.length}/${summary.nrows} 行已载入`;

  const handleExportCsv = () => {
    if (!summary.preview.length) {
      message.warning('当前没有可导出的数据');
      return;
    }
    const columns = visibleColumns.map((col) => col.name);
    const csv = buildCsv(columns, summary.preview);
    const timestamp = new Date().toISOString().slice(0, 19).replace(/[:-]/g, '');
    downloadText(csv, `metrica_data_${timestamp}.csv`, 'text/csv;charset=utf-8');
    message.success(`已导出 ${summary.preview.length} 行数据`);
  };

  return (
    <div style={{ flex: 1, height: '100%', minHeight: 0, display: 'flex', flexDirection: 'column', padding: 0, background: 'var(--m-page-bg)' }}>
      <style>{`
        .metrica-data-grid .ag-root-wrapper {
          border: 1px solid var(--m-border-strong);
          border-radius: 20px;
          overflow: hidden;
          box-shadow: var(--m-shadow-lg);
        }
        .metrica-data-grid .ag-header {
          background: linear-gradient(180deg, var(--m-surface) 0%, var(--m-surface-hover) 100%);
          border-bottom: 1px solid var(--m-border-strong);
          color: var(--m-text-primary);
          font-weight: 800;
        }
        .metrica-data-grid .ag-row {
          border-bottom-color: var(--m-border);
          font-size: 13px;
        }
        .metrica-data-grid .ag-row-hover {
          background-color: var(--m-completion-item-hover) !important;
        }
        .metrica-data-grid .ag-cell {
          display: flex;
          align-items: center;
          color: var(--m-text-primary);
        }
        .metrica-data-grid .metrica-row-index {
          color: var(--m-text-muted);
          font-weight: 700;
          background: var(--m-surface-hover);
          justify-content: center;
        }
        .metrica-data-grid .metrica-missing-cell {
          color: var(--m-error);
          font-weight: 700;
          font-style: italic;
          background: linear-gradient(90deg, var(--m-accent-light), transparent);
        }
      `}</style>

      <div style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        padding: '16px 26px 12px',
        borderBottom: '1px solid var(--m-border)',
        background: 'var(--m-surface)',
        backdropFilter: 'blur(12px)',
      }}>
        <Space size={14}>
          <Button icon={<ArrowLeftOutlined />} onClick={() => {
            clearBrowseContext();
            setDataFullscreen(false);
          }}>返回结果</Button>
          <Text strong style={{ fontSize: 18 }}>{summary.nrows} obs x {summary.ncols} vars</Text>
          {browseReadonly ? <Tag color="cyan">browse 只读模式</Tag> : null}
          <Tag color={rowData.length === summary.nrows ? 'blue' : 'gold'}>{isLoadingFullRows ? '正在载入全部行' : loadedText}</Tag>
          <Tag color={missingCols > 0 ? 'orange' : 'default'}>{missingCols > 0 ? `${missingCols} 列有缺失` : '无缺失列'}</Tag>
          {fullRowsError ? <Tag color="red">{fullRowsError}</Tag> : null}
        </Space>
        <Space>
          <Button
            icon={<FilterOutlined />}
            type={showFilters ? 'primary' : 'default'}
            onClick={() => setShowFilters((v) => !v)}
          >
            筛选
          </Button>
          {!browseReadonly ? (
            <Button icon={<SwapOutlined />} onClick={() => setTransformOpen(true)}>变换</Button>
          ) : null}
          <Button icon={<ExportOutlined />} onClick={handleExportCsv}>导出</Button>
        </Space>
      </div>

      <div style={{
        display: 'flex',
        gap: 8,
        overflowX: 'auto',
        padding: '12px 26px 10px',
        borderBottom: '1px solid var(--m-border)',
        background: 'var(--m-surface-hover)',
      }}>
        {visibleColumns.map((col, idx) => {
          const missing = col.missing_count ?? col.missing ?? 0;
          const active = selectedColIndex === idx;
          return (
            <button
              key={col.name}
              type="button"
              onClick={() => setSelectedColIndex(idx)}
              style={{
                border: active ? '1px solid var(--m-accent)' : '1px solid var(--m-border)',
                background: active ? 'var(--m-info-bg)' : 'var(--m-surface)',
                borderRadius: 16,
                padding: '10px 14px',
                minWidth: 128,
                cursor: 'pointer',
                textAlign: 'left',
                boxShadow: active ? '0 14px 30px rgba(37, 99, 235, 0.14)' : '0 6px 18px rgba(15, 23, 42, 0.04)',
              }}
            >
              <div style={{ fontWeight: 850, color: 'var(--m-text-primary)', marginBottom: 6 }}>{col.name}</div>
              <Space size={6}>
                <Tag color="blue" style={{ marginInlineEnd: 0 }}>{col.inferred_type || col.type || '?'}</Tag>
                {missing > 0 ? <Tag color="orange" style={{ marginInlineEnd: 0 }}>缺失 {missing}</Tag> : null}
              </Space>
            </button>
          );
        })}
      </div>

      <div className="ag-theme-quartz metrica-data-grid" style={{ flex: 1, minHeight: 0, height: '100%', overflow: 'hidden', padding: '18px 26px 22px' }}>
        <AgGridReact
          columnDefs={columnDefs}
          rowData={rowData}
          rowHeight={42}
          headerHeight={44}
          animateRows
          suppressCellFocus
          defaultColDef={{ flex: 1, minWidth: 120, filter: true, sortable: true, resizable: true }}
          key={showFilters ? 'filters-on' : 'filters-off'}
          getRowStyle={(params) => params.node.rowIndex !== null && params.node.rowIndex % 2 === 1
            ? { background: 'var(--m-surface-hover)' }
            : { background: 'var(--m-surface)' }}
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

      {selectedCol && (
        <div style={{
          padding: '10px 26px',
          borderTop: '1px solid var(--m-border)',
          background: 'var(--m-surface)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
        }}>
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

      <Drawer
        title="数据变换"
        width={760}
        open={transformOpen}
        onClose={() => setTransformOpen(false)}
        destroyOnClose={false}
      >
        <DataOperationsPanel />
      </Drawer>
    </div>
  );
};
