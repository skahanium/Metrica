import { Card, Typography } from 'antd';
import { useEffect, useRef, type ComponentRef } from 'react';
import ReactECharts from 'echarts-for-react';
import type { ModelResult } from '../types/protocol';
import { registerChartForRun } from '../services/chartExport';

interface EventStudyPlotProps {
  result: ModelResult;
  /** 有 runId 时注册图表实例，供 CLI `export plot` 使用 */
  runId?: string | null;
}

export function EventStudyPlot({ result, runId }: EventStudyPlotProps) {
  const chartRef = useRef<ComponentRef<typeof ReactECharts>>(null);

  useEffect(() => {
    if (!runId) return undefined;
    const inst = chartRef.current?.getEchartsInstance?.();
    if (!inst) return undefined;
    return registerChartForRun(runId, {
      getDataURL: (opts) => inst.getDataURL(opts as never),
    });
  }, [runId, result.glance?.model, result.period_coefficients?.length]);

  if (result.glance.model !== 'event_study') return null;

  const coefs = result.period_coefficients || [];
  const ses = result.period_stderrors || [];
  const labels = result.period_labels || [];
  const pval = result.pre_trend_pvalue;
  const supported = result.parallel_trends_supported;

  const lower = coefs.map((c, i) => c - 1.96 * (ses[i] || 0));
  const upper = coefs.map((c, i) => c + 1.96 * (ses[i] || 0));

  const option = {
    tooltip: { trigger: 'axis' },
    xAxis: {
      type: 'category',
      data: labels,
      name: '相对时期',
      axisLabel: { rotate: 45 },
    },
    yAxis: {
      type: 'value',
      name: '系数',
      axisLine: { lineStyle: { color: '#999' } },
    },
    series: [
      {
        name: '系数',
        type: 'line',
        data: coefs,
        symbol: 'circle',
        symbolSize: 8,
        lineStyle: { color: '#1890ff' },
        itemStyle: { color: '#1890ff' },
        markLine: {
          silent: true,
          data: [{ xAxis: '-1', label: { formatter: '基准期' }, lineStyle: { color: '#faad14', type: 'dashed' } }],
        },
      },
      {
        name: '95% CI',
        type: 'line',
        data: upper,
        symbol: 'none',
        lineStyle: { color: 'transparent' },
        areaStyle: { color: 'rgba(24,144,255,0.1)' },
      },
      {
        name: '95% CI 下界',
        type: 'line',
        data: lower,
        symbol: 'none',
        lineStyle: { color: '#1890ff', type: 'dashed', width: 0.5 },
      },
      {
        name: '95% CI 上界',
        type: 'line',
        data: upper,
        symbol: 'none',
        lineStyle: { color: '#1890ff', type: 'dashed', width: 0.5 },
      },
      {
        name: '置信区间',
        type: 'line',
        symbol: 'none',
        lineStyle: { color: 'transparent' },
        areaStyle: { color: 'rgba(24,144,255,0.15)' },
        data: upper,
        stack: 'confidence-band',
      },
      {
        name: '置信区间底',
        type: 'line',
        symbol: 'none',
        lineStyle: { color: 'transparent' },
        areaStyle: { color: 'rgba(255,255,255,0)' },
        data: lower,
        stack: 'confidence-band',
      },
    ],
    grid: { left: 60, right: 20, top: 40, bottom: 60 },
  };

  return (
    <Card size="small" title="事件研究" style={{ marginBottom: 16 }}>
      <Typography.Paragraph>
        事前趋势联合 F 检验 p = {pval?.toFixed(4)}。
        {supported
          ? ' 未拒绝平行趋势假设。'
          : ' 拒绝平行趋势假设，处理效应估计可能偏误。'}
      </Typography.Paragraph>
      <ReactECharts ref={chartRef} option={option} style={{ height: 350 }} />
    </Card>
  );
}
