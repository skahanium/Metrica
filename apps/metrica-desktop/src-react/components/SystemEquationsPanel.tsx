import React, { useMemo } from 'react';
import { Card, Table, Typography } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import type { GlanceResult, ModelResult, SystemEquationsDiagnostics } from '../types/protocol';

const { Text, Title } = Typography;

function isSystemDiag(d: ModelResult['diagnostics']): d is SystemEquationsDiagnostics {
  return !!d && typeof d === 'object' && ('sigma_residual' in d || 'system_method' in d);
}

/** 将方阵转为 Ant Table 行（每行带 rowKey） */
function matrixToRows(mat: number[][]): Record<string, number | string>[] {
  return mat.map((row, ri) => {
    const r: Record<string, number | string> = { _row: String(ri + 1) };
    row.forEach((v, ci) => {
      r[`c${ci}`] = v;
    });
    return r;
  });
}

function matrixColumns(mat: number[][]): ColumnsType<Record<string, number | string>> {
  const n = mat[0]?.length ?? 0;
  const cols: ColumnsType<Record<string, number | string>> = [
    { title: ' ', dataIndex: '_row', key: '_row', width: 48, align: 'center' },
  ];
  for (let j = 0; j < n; j++) {
    const cj = `c${j}`;
    cols.push({
      title: `${j + 1}`,
      dataIndex: cj,
      key: cj,
      align: 'right',
      render: (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v.toFixed(6) : '—'),
    });
  }
  return cols;
}

export const SystemEquationsPanel: React.FC<{ result: ModelResult }> = ({ result }) => {
  const glances = result.equation_glances;
  if (!glances?.length) return null;

  const diag = isSystemDiag(result.diagnostics) ? result.diagnostics : undefined;
  const sigma = diag?.sigma_residual;
  const corr = diag?.equation_correlation;

  const columns: ColumnsType<GlanceResult & { key: string }> = [
    { title: '方程', dataIndex: 'model', key: 'model', ellipsis: true, width: 220 },
    { title: 'n', dataIndex: 'nobs', key: 'nobs', width: 72, align: 'right' },
    { title: 'dof', dataIndex: 'dof', key: 'dof', width: 72, align: 'right' },
    {
      title: 'R²',
      key: 'r2',
      width: 88,
      align: 'right',
      render: (_, row) => {
        const r2 = row.metrics?.r2;
        return r2 != null ? r2.toFixed(4) : '—';
      },
    },
  ];

  const rows = glances.map((g, i) => ({ ...g, key: `eq-${i}` }));

  const sigmaRows = useMemo(() => (sigma?.matrix ? matrixToRows(sigma.matrix as number[][]) : []), [sigma]);
  const sigmaCols = useMemo(() => (sigma?.matrix ? matrixColumns(sigma.matrix as number[][]) : []), [sigma]);
  const corrRows = useMemo(() => (corr?.matrix ? matrixToRows(corr.matrix as number[][]) : []), [corr]);
  const corrCols = useMemo(() => (corr?.matrix ? matrixColumns(corr.matrix as number[][]) : []), [corr]);

  return (
    <div style={{ marginTop: 12 }}>
      <Title level={5} style={{ marginBottom: 8 }}>多方程摘要</Title>
      <Table<GlanceResult & { key: string }>
        size="small"
        bordered
        pagination={false}
        columns={columns}
        dataSource={rows}
      />
      {diag?.system_method && (
        <Text type="secondary" style={{ display: 'block', marginTop: 8 }}>
          系统方法：{diag.system_method}
          {typeof diag.iterations === 'number' ? ` · 迭代：${diag.iterations}` : ''}
        </Text>
      )}
      {sigmaRows.length > 0 && (
        <Card size="small" title="残差协方差 Σ̂（结构化）" style={{ marginTop: 12 }}>
          <Table<Record<string, number | string>>
            size="small"
            pagination={false}
            rowKey={(_, i) => `s-${i}`}
            columns={sigmaCols}
            dataSource={sigmaRows}
          />
        </Card>
      )}
      {corrRows.length > 0 && (
        <Card size="small" title="方程间残差相关" style={{ marginTop: 12 }}>
          <Table<Record<string, number | string>>
            size="small"
            pagination={false}
            rowKey={(_, i) => `c-${i}`}
            columns={corrCols}
            dataSource={corrRows}
          />
        </Card>
      )}
    </div>
  );
};
