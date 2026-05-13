import { Descriptions, Card, Table, Typography } from 'antd';
import type { ModelResult } from '../types/protocol';

const { Text } = Typography;

const METRIC_LABELS: Record<string, string> = {
  r2: 'R²',
  adj_r2: '调整 R²',
  sigma: '残差标准误',
  rss: 'RSS',
  tss: 'TSS',
  n_ids: '个体数',
  n_times: '时期数',
  // ANOVA 表指标
  model_ss: '模型 SS',
  model_df: '模型 df',
  model_ms: '模型 MS',
  resid_ss: '残差 SS',
  resid_df: '残差 df',
  resid_ms: '残差 MS',
  total_ss: '总 SS',
  total_df: '总 df',
  total_ms: '总 MS',
  // 整体检验指标
  f_stat: 'F 统计量',
  f_pvalue: 'F p 值',
  wald_stat: 'Wald 统计量',
  wald_pvalue: 'Wald p 值',
  wald_f: 'Wald F',
  lr_chi2: 'LR χ²',
  lr_pvalue: 'LR p 值',
  // 面板模型特有指标
  rho: 'ρ',
  sigma_u: 'σ_u',
  sigma_e: 'σ_e',
  r2_within: '组内 R²',
  r2_between: '组间 R²',
  r2_overall: '整体 R²',
};

function formatMetric(key: string, value: number): string {
  if (['r2', 'adj_r2', 'r2_within', 'r2_between', 'r2_overall', 'rho', 'pseudo_r2'].includes(key)) return value.toFixed(4);
  if (key === 'sigma' || key === 'sigma_u' || key === 'sigma_e') return value.toFixed(4);
  if (['rss', 'tss', 'model_ss', 'resid_ss', 'total_ss'].includes(key)) return value.toFixed(2);
  if (['n_ids', 'n_times', 'model_df', 'resid_df', 'total_df'].includes(key)) return String(Math.round(value));
  if (['f_stat', 'f_pvalue', 'wald_stat', 'wald_pvalue', 'wald_f', 'lr_chi2', 'lr_pvalue'].includes(key)) return value.toFixed(4);
  return value.toFixed(4);
}

interface GlanceTableProps {
  result?: ModelResult;
}

export function GlanceTable({ result }: GlanceTableProps) {
  if (!result?.glance) return null;

  const { glance } = result;
  const metrics = glance.metrics;

  // 检查是否有 ANOVA 表指标
  const hasAnova = metrics.model_ss !== undefined || metrics.total_ss !== undefined;
  
  // 检查是否有整体检验指标
  const hasOverallTest = metrics.f_stat !== undefined || metrics.wald_stat !== undefined || 
                         metrics.wald_f !== undefined || metrics.lr_chi2 !== undefined;
  
  // 检查是否有面板模型特有指标
  const hasPanelMetrics = metrics.rho !== undefined || metrics.sigma_u !== undefined || 
                          metrics.r2_within !== undefined;

  // ANOVA 表数据
  const anovaData = hasAnova ? [
    { source: '模型', ss: metrics.model_ss, df: metrics.model_df, ms: metrics.model_ms },
    { source: '残差', ss: metrics.resid_ss, df: metrics.resid_df, ms: metrics.resid_ms },
    { source: '总和', ss: metrics.total_ss, df: metrics.total_df, ms: metrics.total_ms },
  ] : [];

  const anovaColumns = [
    { title: '来源', dataIndex: 'source', key: 'source' },
    { title: 'SS', dataIndex: 'ss', key: 'ss', render: (v: number) => v?.toFixed(2) ?? '—' },
    { title: 'df', dataIndex: 'df', key: 'df', render: (v: number) => v != null ? String(Math.round(v)) : '—' },
    { title: 'MS', dataIndex: 'ms', key: 'ms', render: (v: number) => v?.toFixed(4) ?? '—' },
  ];

  // 整体检验信息
  const overallTest = hasOverallTest ? (
    <div style={{ marginBottom: 16 }}>
      <Text strong>整体检验</Text>
      <Descriptions bordered size="small" column={2} style={{ marginTop: 8 }}>
        {metrics.f_stat !== undefined && (
          <>
            <Descriptions.Item label="F 统计量">{formatMetric('f_stat', metrics.f_stat)}</Descriptions.Item>
            <Descriptions.Item label="F p 值">{formatMetric('f_pvalue', metrics.f_pvalue ?? 0)}</Descriptions.Item>
          </>
        )}
        {metrics.wald_stat !== undefined && (
          <>
            <Descriptions.Item label="Wald 统计量">{formatMetric('wald_stat', metrics.wald_stat)}</Descriptions.Item>
            <Descriptions.Item label="Wald p 值">{formatMetric('wald_pvalue', metrics.wald_pvalue ?? 0)}</Descriptions.Item>
          </>
        )}
        {metrics.wald_f !== undefined && (
          <>
            <Descriptions.Item label="Wald F">{formatMetric('wald_f', metrics.wald_f)}</Descriptions.Item>
            <Descriptions.Item label="Wald p 值">{formatMetric('wald_pvalue', metrics.wald_pvalue ?? 0)}</Descriptions.Item>
          </>
        )}
        {metrics.lr_chi2 !== undefined && (
          <>
            <Descriptions.Item label="LR χ²">{formatMetric('lr_chi2', metrics.lr_chi2)}</Descriptions.Item>
            <Descriptions.Item label="LR p 值">{formatMetric('lr_pvalue', metrics.lr_pvalue ?? 0)}</Descriptions.Item>
          </>
        )}
      </Descriptions>
    </div>
  ) : null;

  // 面板模型特有指标
  const panelMetrics = hasPanelMetrics ? (
    <div style={{ marginBottom: 16 }}>
      <Text strong>面板模型指标</Text>
      <Descriptions bordered size="small" column={3} style={{ marginTop: 8 }}>
        {metrics.rho !== undefined && (
          <Descriptions.Item label="ρ (个体效应占比)">{formatMetric('rho', metrics.rho)}</Descriptions.Item>
        )}
        {metrics.sigma_u !== undefined && (
          <Descriptions.Item label="σ_u (个体效应标准差)">{formatMetric('sigma_u', metrics.sigma_u)}</Descriptions.Item>
        )}
        {metrics.sigma_e !== undefined && (
          <Descriptions.Item label="σ_e (残差标准差)">{formatMetric('sigma_e', metrics.sigma_e)}</Descriptions.Item>
        )}
        {metrics.r2_within !== undefined && (
          <Descriptions.Item label="组内 R²">{formatMetric('r2_within', metrics.r2_within)}</Descriptions.Item>
        )}
        {metrics.r2_between !== undefined && (
          <Descriptions.Item label="组间 R²">{formatMetric('r2_between', metrics.r2_between)}</Descriptions.Item>
        )}
        {metrics.r2_overall !== undefined && (
          <Descriptions.Item label="整体 R²">{formatMetric('r2_overall', metrics.r2_overall)}</Descriptions.Item>
        )}
      </Descriptions>
    </div>
  ) : null;

  // 过滤出其他指标（排除 ANOVA 和整体检验指标）
  const otherMetrics = Object.entries(metrics).filter(([key]) => {
    const anovaKeys = ['model_ss', 'model_df', 'model_ms', 'resid_ss', 'resid_df', 'resid_ms', 'total_ss', 'total_df', 'total_ms'];
    const testKeys = ['f_stat', 'f_pvalue', 'wald_stat', 'wald_pvalue', 'wald_f', 'lr_chi2', 'lr_pvalue'];
    const panelKeys = ['rho', 'sigma_u', 'sigma_e', 'r2_within', 'r2_between', 'r2_overall'];
    return !anovaKeys.includes(key) && !testKeys.includes(key) && !panelKeys.includes(key);
  });

  return (
    <Card size="small">
      <Descriptions bordered size="small" column={3}>
        <Descriptions.Item label="模型">{glance.model.toUpperCase()}</Descriptions.Item>
        <Descriptions.Item label="样本量">{glance.nobs}</Descriptions.Item>
        <Descriptions.Item label="自由度">{glance.dof}</Descriptions.Item>
        {otherMetrics.map(([key, value]) => (
          <Descriptions.Item key={key} label={METRIC_LABELS[key] ?? key}>
            {formatMetric(key, value)}
          </Descriptions.Item>
        ))}
      </Descriptions>
      
      {hasAnova && (
        <div style={{ marginTop: 16 }}>
          <Text strong>ANOVA 表</Text>
          <Table
            bordered
            columns={anovaColumns}
            dataSource={anovaData}
            pagination={false}
            rowKey="source"
            size="small"
            style={{ marginTop: 8 }}
          />
        </div>
      )}
      
      {overallTest}
      {panelMetrics}
    </Card>
  );
}
