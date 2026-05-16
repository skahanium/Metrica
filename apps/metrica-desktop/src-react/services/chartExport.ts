/**
 * 事件研究等图表的 CLI 导出：依赖组件注册的 ECharts 实例，可注入 mock 以便单测。
 */

export type PlotImageFormat = 'svg' | 'png';

export type ChartDataUrlExporter = (runId: string, format: PlotImageFormat) => Promise<string>;

let testExporter: ChartDataUrlExporter | null = null;

/** 测试注入导出器（生产环境保持 null） */
export function setChartExportTestExporter(exporter: ChartDataUrlExporter | null): void {
  testExporter = exporter;
}

interface RegisteredChart {
  getDataURL: (opts: { type?: string; pixelRatio?: number; backgroundColor?: string }) => string | undefined;
}

const chartByRunId = new Map<string, RegisteredChart>();

export function registerChartForRun(runId: string, chart: RegisteredChart): () => void {
  chartByRunId.set(runId, chart);
  return () => {
    chartByRunId.delete(runId);
  };
}

export function unregisterChartForRun(runId: string): void {
  chartByRunId.delete(runId);
}

/**
 * 从已注册实例生成 data URL。
 * @returns data URL 或结构化错误（不静默成功）
 */
export async function exportRegisteredChartDataUrl(
  runId: string,
  format: PlotImageFormat,
): Promise<{ dataUrl: string } | { error: string }> {
  if (testExporter) {
    try {
      const dataUrl = await testExporter(runId, format);
      if (!dataUrl.startsWith('data:')) {
        return { error: '测试导出器返回了非法 data URL。' };
      }
      return { dataUrl };
    } catch (e) {
      return { error: (e as Error).message || '图表导出失败' };
    }
  }
  const chart = chartByRunId.get(runId);
  if (!chart) {
    return { error: '该 run 未注册可导出的图表实例（例如非事件研究模型）。' };
  }
  try {
    const dataUrl = chart.getDataURL({
      type: format,
      pixelRatio: format === 'png' ? 2 : 1,
      backgroundColor: '#ffffff',
    });
    if (!dataUrl || !dataUrl.startsWith('data:')) {
      return { error: 'ECharts 未返回有效的 data URL。' };
    }
    return { dataUrl };
  } catch (e) {
    return { error: (e as Error).message || '图表导出失败' };
  }
}
