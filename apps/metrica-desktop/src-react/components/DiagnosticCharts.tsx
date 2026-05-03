import { useRef } from 'react';
import ReactECharts from 'echarts-for-react';
import { Card, Empty } from 'antd';
import { useModelStore } from '../stores/modelStore';
import { ChartExportButton } from './ChartExportButton';

export function DiagnosticCharts() {
  const lastResult = useModelStore((s) => s.lastResult);
  const histogramRef = useRef<any>(null);
  const qqRef = useRef<any>(null);
  const scatterRef = useRef<any>(null);

  if (!lastResult?.augment_preview?.length) return <Empty description="无增强数据，无法生成诊断图表。请在运行时开启 return_augment。" />;

  const residuals = lastResult.augment_preview.map((r) => r.residual);
  const fitted = lastResult.augment_preview.map((r) => r.fitted);

  const histogramOption = {
    title: { text: '残差分布', left: 'center' },
    xAxis: { name: '残差' },
    yAxis: { name: '频数' },
    series: [{
      type: 'histogram',
      data: residuals,
      itemStyle: { color: '#1677ff' },
    }],
    tooltip: { trigger: 'axis' },
  };

  const qqOption = {
    title: { text: '残差 Q-Q 图', left: 'center' },
    xAxis: { name: '理论分位数' },
    yAxis: { name: '样本分位数' },
    series: [{
      type: 'scatter',
      data: residuals
        .slice()
        .sort((a, b) => a - b)
        .map((v, i) => [v, (i + 0.5) / residuals.length]),
      itemStyle: { color: '#1677ff' },
    }],
    tooltip: { trigger: 'item' },
  };

  const scatterOption = {
    title: { text: '残差 vs 拟合值', left: 'center' },
    xAxis: { name: '拟合值' },
    yAxis: { name: '残差' },
    series: [{
      type: 'scatter',
      data: fitted.map((f, i) => [f, residuals[i]]),
      itemStyle: { color: '#1677ff' },
    }],
    tooltip: { trigger: 'item' },
    markLine: {
      silent: true,
      data: [{ yAxis: 0 }],
    },
  };

  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))', gap: 16, marginTop: 16 }}>
      <Card size="small" style={{ position: 'relative' }}>
        <ChartExportButton chartRef={histogramRef} filename="residual_histogram" />
        <ReactECharts ref={histogramRef} option={histogramOption} opts={{ renderer: 'svg' }} style={{ height: 300 }} />
      </Card>
      <Card size="small" style={{ position: 'relative' }}>
        <ChartExportButton chartRef={qqRef} filename="residual_qq" />
        <ReactECharts ref={qqRef} option={qqOption} opts={{ renderer: 'svg' }} style={{ height: 300 }} />
      </Card>
      <Card size="small" style={{ position: 'relative' }}>
        <ChartExportButton chartRef={scatterRef} filename="residual_vs_fitted" />
        <ReactECharts ref={scatterRef} option={scatterOption} opts={{ renderer: 'svg' }} style={{ height: 300 }} />
      </Card>
    </div>
  );
}
