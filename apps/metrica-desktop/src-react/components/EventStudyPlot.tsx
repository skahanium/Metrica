import { Card, Typography } from 'antd';
import ReactECharts from 'echarts-for-react';
import { useModelStore } from '../stores/modelStore';

export function EventStudyPlot() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult || lastResult.glance.model !== 'event_study') return null;

  const coefs = lastResult.period_coefficients || [];
  const ses = lastResult.period_stderrors || [];
  const labels = lastResult.period_labels || [];
  const pval = lastResult.pre_trend_pvalue;
  const supported = lastResult.parallel_trends_supported;

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
      <ReactECharts option={option} style={{ height: 350 }} />
    </Card>
  );
}
