import { Button, Card, Space, Typography, message } from 'antd';
import {
  FileTextOutlined,
  TableOutlined,
} from '@ant-design/icons';
import { useModelStore } from '../stores/modelStore';
import { useProjectStore } from '../stores/projectStore';
import { useExportStore, downloadText, generateExportFilename } from '../stores/exportStore';
import { exportReport } from '../services/runtimeClient';

const { Text } = Typography;

export function ExportPanel() {
  const lastResult = useModelStore((s) => s.lastResult);
  const runHistory = useProjectStore((s) => s.runHistory);
  const { isExporting, setIsExporting, addExportHistory } = useExportStore();

  const latestFitRun = runHistory.find(
    (run) => run.action === 'fit_model' && run.status === 'success',
  );

  const handleExport = async (format: 'markdown' | 'csv_tidy' | 'csv_glance' | 'csv_diagnostics') => {
    if (!latestFitRun) {
      message.warning('暂无可导出的模型结果');
      return;
    }

    setIsExporting(true);
    try {
      const result = await exportReport({
        runId: latestFitRun.run_id,
        format,
      });

      const modelType = lastResult?.glance?.model || 'model';
      const filename = generateExportFilename(format, modelType, latestFitRun.run_id);
      const mimeType = format.startsWith('csv') ? 'text/csv' : 'text/markdown';

      downloadText(result.content, filename, mimeType);

      addExportHistory({
        runId: latestFitRun.run_id,
        format,
        exportedAt: new Date().toISOString(),
        content: result.content,
      });

      message.success(`已导出 ${filename}`);
    } catch (e) {
      message.error(e instanceof Error ? e.message : '导出失败');
    } finally {
      setIsExporting(false);
    }
  };

  if (!lastResult) {
    return (
      <Card size="small" title="导出报告">
        <Text type="secondary">请先运行模型后再导出。</Text>
      </Card>
    );
  }

  return (
    <Card size="small" title="导出报告">
      <Space direction="vertical" style={{ width: '100%' }} size={12}>
        <Text type="secondary">选择导出格式：</Text>
        <Space wrap>
          <Button
            icon={<FileTextOutlined />}
            loading={isExporting}
            onClick={() => handleExport('markdown')}
          >
            Markdown 报告
          </Button>
          <Button
            icon={<TableOutlined />}
            loading={isExporting}
            onClick={() => handleExport('csv_tidy')}
          >
            CSV 系数表
          </Button>
          <Button
            icon={<TableOutlined />}
            loading={isExporting}
            onClick={() => handleExport('csv_glance')}
          >
            CSV 摘要指标
          </Button>
          <Button
            icon={<TableOutlined />}
            loading={isExporting}
            onClick={() => handleExport('csv_diagnostics')}
          >
            CSV 诊断结果
          </Button>
        </Space>
        {latestFitRun && (
          <Text type="secondary" style={{ fontSize: 12 }}>
            将导出运行 {latestFitRun.run_id.slice(0, 8)} 的结果
          </Text>
        )}
      </Space>
    </Card>
  );
}
