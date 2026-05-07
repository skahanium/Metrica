import { useMemo } from 'react';
import { Card, Table, Empty, Typography, Tag, Alert, Button, message } from 'antd';
import { DownloadOutlined } from '@ant-design/icons';
import { useModelStore, type ModelHistoryItem } from '../stores/modelStore';
import { downloadText, generateExportFilename } from '../stores/exportStore';

const { Text } = Typography;

interface CompatibilityResult {
  compatible: boolean;
  errors: string[];
  warnings: string[];
}

function parseDepVar(formula: string): string {
  return formula.split('~')[0]?.trim() ?? '';
}

function modelFamily(modelType: string): 'cross_section' | 'panel' {
  if (modelType === 'panel') return 'panel';
  return 'cross_section';
}

function validateComparisonCompatibility(models: ModelHistoryItem[]): CompatibilityResult {
  const errors: string[] = [];
  const warnings: string[] = [];

  if (models.length < 2) {
    return { compatible: false, errors: ['请至少选择 2 个模型。'], warnings: [] };
  }

  // 检查数据集一致性
  const datasets = new Set(models.map((m) => m.datasetPath));
  if (datasets.size > 1) {
    errors.push('所选模型使用了不同的数据集，无法直接对比。');
    return { compatible: false, errors, warnings };
  }

  // 检查因变量一致性
  const depVars = new Set(models.map((m) => parseDepVar(m.formula)));
  if (depVars.size > 1) {
    errors.push(
      `所选模型的因变量不一致：${Array.from(depVars).join(' vs ')}。因变量不同的模型不具备可比性。`,
    );
  }

  // 检查模型族兼容性
  const families = new Set(models.map((m) => modelFamily(m.modelType)));
  if (families.size > 1) {
    warnings.push(
      `横截面模型 (OLS/IV/GLS) 与面板模型 (Panel) 的估计方法和假设不同，对比结果需谨慎解读。`,
    );
  }

  // 检查观测数一致性
  const nobsSet = new Set(models.map((m) => m.result.glance.nobs));
  if (nobsSet.size > 1) {
    warnings.push(
      `所选模型使用了不同数量的有效观测值：${Array.from(nobsSet).join(' vs ')}。可能由于缺失值处理或变换导致。`,
    );
  }

  // 检查公式一致性（因变量相同但公式不同）
  if (depVars.size === 1) {
    const formulas = new Set(models.map((m) => m.formula.trim()));
    if (formulas.size > 1) {
      warnings.push('模型公式不同，对比的是不同规格的模型。');
    }
  }

  return { compatible: errors.length === 0, errors, warnings };
}

interface ComparisonRow {
  term: string;
  [key: string]: string | number | null;
}

function buildComparisonTable(selectedModels: ModelHistoryItem[]): {
  glanceRows: Array<Record<string, string | number>>;
  tidyRows: ComparisonRow[];
} {
  if (selectedModels.length === 0) {
    return { glanceRows: [], tidyRows: [] };
  }

  // 动态收集所有 glance 指标
  const allMetrics = new Set<string>();
  const metricLabels: Record<string, string> = {
    model: '模型',
    nobs: '样本量',
    dof: '自由度',
    r2: 'R²',
    adj_r2: '调整 R²',
    sigma: 'Sigma',
    rss: 'RSS',
    tss: 'TSS',
    aic: 'AIC',
    bic: 'BIC',
    loglik: '对数似然',
    f_statistic: 'F 统计量',
  };

  selectedModels.forEach((m) => {
    Object.keys(m.result.glance.metrics).forEach((k) => allMetrics.add(k));
  });

  const baseMetrics = ['model', 'nobs', 'dof'];
  const standardMetrics = ['r2', 'adj_r2', 'sigma', 'rss', 'tss', 'aic', 'bic', 'loglik', 'f_statistic'];
  const orderedMetrics = [
    ...baseMetrics,
    ...standardMetrics.filter((k) => allMetrics.has(k)),
    ...Array.from(allMetrics).filter((k) => !baseMetrics.includes(k) && !standardMetrics.includes(k)),
  ];

  const glanceRows = orderedMetrics.map((metric) => {
    const row: Record<string, string | number> = {
      term: metric,
      metricLabel: metricLabels[metric] ?? metric,
    };
    selectedModels.forEach((m) => {
      const glance = m.result.glance;
      if (metric === 'model') {
        row[m.id] = glance.model;
      } else if (metric === 'nobs') {
        row[m.id] = glance.nobs;
      } else if (metric === 'dof') {
        row[m.id] = glance.dof;
      } else {
        row[m.id] = glance.metrics[metric] ?? '—';
      }
    });
    return row;
  });

  // Tidy 对比
  const allTerms = new Set<string>();
  selectedModels.forEach((m) => {
    m.result.tidy.forEach((row) => allTerms.add(row.term));
  });

  const tidyRows = Array.from(allTerms).map((term) => {
    const row: ComparisonRow = { term };
    selectedModels.forEach((m) => {
      const tidyRow = m.result.tidy.find((r) => r.term === term);
      if (tidyRow) {
        row[`${m.id}_estimate`] = tidyRow.estimate;
        row[`${m.id}_se`] = tidyRow.std_error;
        row[`${m.id}_pvalue`] = tidyRow.p_value;
      }
    });
    return row;
  });

  return { glanceRows, tidyRows };
}

function buildComparisonCSV(selectedModels: ModelHistoryItem[]): string {
  const { glanceRows, tidyRows } = buildComparisonTable(selectedModels);
  const lines: string[] = [];

  lines.push('# 模型对比报告');
  lines.push('');
  lines.push('## 模型摘要对比');
  const modelLabels = selectedModels.map((m) => m.label).join(',');
  lines.push(`指标,${modelLabels}`);
  glanceRows.forEach((row) => {
    const values = [row.metricLabel, ...selectedModels.map((m) => String(row[m.id] ?? '—'))];
    lines.push(values.join(','));
  });

  lines.push('');
  lines.push('## 系数表对比');
  const tidyHeaders = ['参数', ...selectedModels.flatMap((m) => [`${m.label} 估计值`, `${m.label} 标准误`, `${m.label} p值`])];
  lines.push(tidyHeaders.join(','));
  tidyRows.forEach((row) => {
    const values = [row.term, ...selectedModels.flatMap((m) => [
      String(row[`${m.id}_estimate`] ?? '—'),
      String(row[`${m.id}_se`] ?? '—'),
      String(row[`${m.id}_pvalue`] ?? '—'),
    ])];
    lines.push(values.join(','));
  });

  return lines.join('\n');
}

export function ModelComparison() {
  const { modelHistory, selectedModelIds, removeFromHistory } = useModelStore();

  const selectedModels = useMemo(
    () => modelHistory.filter((m) => selectedModelIds.includes(m.id)),
    [modelHistory, selectedModelIds],
  );

  const compatibility = useMemo(
    () => validateComparisonCompatibility(selectedModels),
    [selectedModels],
  );

  if (selectedModels.length < 2) {
    return (
      <Card size="small" title="模型对比">
        <Empty description="请在运行历史中选择至少 2 个模型进行对比。" />
      </Card>
    );
  }

  const { glanceRows, tidyRows } = buildComparisonTable(selectedModels);

  const glanceColumns = [
    { title: '指标', dataIndex: 'metricLabel', key: 'metricLabel' },
    ...selectedModels.map((m) => ({
      title: m.label,
      dataIndex: m.id,
      key: m.id,
      render: (v: any) => {
        if (typeof v === 'number') return Number(v).toFixed(4);
        return String(v ?? '—');
      },
    })),
  ];

  const tidyColumns = [
    { title: '参数', dataIndex: 'term', key: 'term' },
    ...selectedModels.flatMap((m) => [
      {
        title: `${m.label} 估计值`,
        dataIndex: `${m.id}_estimate`,
        key: `${m.id}_estimate`,
        render: (v: any) => (typeof v === 'number' ? Number(v).toFixed(4) : String(v ?? '—')),
      },
      {
        title: `${m.label} 标准误`,
        dataIndex: `${m.id}_se`,
        key: `${m.id}_se`,
        render: (v: any) => (typeof v === 'number' ? Number(v).toFixed(4) : String(v ?? '—')),
      },
      {
        title: `${m.label} p 值`,
        dataIndex: `${m.id}_pvalue`,
        key: `${m.id}_pvalue`,
        render: (v: any) => (typeof v === 'number' ? Number(v).toFixed(4) : String(v ?? '—')),
      },
    ]),
  ];

  const handleExportCSV = () => {
    try {
      const csv = buildComparisonCSV(selectedModels);
      const filename = generateExportFilename('csv_comparison', 'comparison', selectedModels[0]?.runId ?? '');
      downloadText(csv, filename, 'text/csv');
      message.success(`已导出 ${filename}`);
    } catch (e) {
      message.error('导出对比表失败');
    }
  };

  return (
    <Card
      size="small"
      title="模型对比"
      extra={
        <Button size="small" icon={<DownloadOutlined />} onClick={handleExportCSV}>
          导出 CSV
        </Button>
      }
    >
      {/* 已选模型标签 + 移除按钮 */}
      <div style={{ marginBottom: 12 }}>
        <Text strong>已选择 {selectedModels.length} 个模型：</Text>
        {selectedModels.map((m) => (
          <Tag
            key={m.id}
            color="blue"
            closable
            onClose={() => removeFromHistory(m.id)}
            style={{ marginLeft: 4 }}
          >
            {m.label} ({m.modelType})
          </Tag>
        ))}
      </div>

      {/* 兼容性检查结果 */}
      {compatibility.errors.length > 0 && (
        <Alert
          type="error"
          message="无法对比"
          description={compatibility.errors.map((e, i) => <div key={i}>{e}</div>)}
          showIcon
          style={{ marginBottom: 12 }}
        />
      )}
      {compatibility.warnings.length > 0 && (
        <Alert
          type="warning"
          message="对比注意事项"
          description={compatibility.warnings.map((w, i) => <div key={i}>{w}</div>)}
          showIcon
          style={{ marginBottom: 12 }}
        />
      )}

      {/* 仅当无严重错误时渲染对比表 */}
      {compatibility.compatible && (
        <>
          <Card size="small" title="模型摘要对比" style={{ marginBottom: 16 }}>
            <Table
              dataSource={glanceRows as Record<string, unknown>[]}
              columns={glanceColumns}
              pagination={false}
              size="small"
              rowKey="term"
              scroll={{ x: 'max-content' }}
            />
          </Card>

          <Card size="small" title="系数表对比">
            <Table
              dataSource={tidyRows}
              columns={tidyColumns}
              pagination={false}
              size="small"
              rowKey="term"
              scroll={{ x: 'max-content' }}
            />
          </Card>
        </>
      )}
    </Card>
  );
}
