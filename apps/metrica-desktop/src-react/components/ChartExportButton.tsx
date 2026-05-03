import { Button, Dropdown, message } from 'antd';
import { DownloadOutlined } from '@ant-design/icons';
import { downloadDataUrl } from '../stores/exportStore';

interface ChartExportButtonProps {
  chartRef: React.RefObject<any>;
  filename?: string;
}

export function ChartExportButton({ chartRef, filename = 'chart' }: ChartExportButtonProps) {
  const handleExport = (format: 'svg' | 'png') => {
    if (!chartRef.current) {
      message.warning('图表未就绪');
      return;
    }

    const instance = chartRef.current.getEchartsInstance();
    if (!instance) {
      message.warning('图表实例未就绪');
      return;
    }

    try {
      let dataUrl: string;
      let ext: string;

      if (format === 'svg') {
        dataUrl = instance.getDataURL({
          type: 'svg',
          pixelRatio: 2,
          backgroundColor: '#fff',
        });
        ext = 'svg';
      } else {
        dataUrl = instance.getDataURL({
          type: 'png',
          pixelRatio: 3,
          backgroundColor: '#fff',
        });
        ext = 'png';
      }

      downloadDataUrl(dataUrl, `${filename}.${ext}`);
      message.success(`已导出 ${filename}.${ext}`);
    } catch (e) {
      message.error('图表导出失败');
      console.error('Chart export error:', e);
    }
  };

  return (
    <Dropdown
      menu={{
        items: [
          { key: 'svg', label: 'SVG 矢量图', onClick: () => handleExport('svg') },
          { key: 'png', label: 'PNG 高清图 (300 DPI)', onClick: () => handleExport('png') },
        ],
      }}
    >
      <Button
        size="small"
        icon={<DownloadOutlined />}
        style={{ position: 'absolute', top: 8, right: 8, zIndex: 10 }}
      >
        导出
      </Button>
    </Dropdown>
  );
}
