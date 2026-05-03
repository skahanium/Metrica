import { create } from 'zustand';

export interface ExportHistoryItem {
  runId: string;
  format: string;
  exportedAt: string;
  content: string;
}

interface ExportState {
  isExporting: boolean;
  exportHistory: ExportHistoryItem[];
  setIsExporting: (isExporting: boolean) => void;
  addExportHistory: (item: ExportHistoryItem) => void;
  clearExportHistory: () => void;
}

export const useExportStore = create<ExportState>((set) => ({
  isExporting: false,
  exportHistory: [],
  setIsExporting: (isExporting) => set({ isExporting }),
  addExportHistory: (item) => set((state) => ({
    exportHistory: [item, ...state.exportHistory].slice(0, 50), // 保留最近 50 条
  })),
  clearExportHistory: () => set({ exportHistory: [] }),
}));

/**
 * 下载文本内容为文件
 */
export function downloadText(content: string, filename: string, mimeType: string = 'text/plain') {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/**
 * 下载 Data URL 内容为文件（用于图表等直接生成 data URL 的场景）。
 */
export function downloadDataUrl(dataUrl: string, filename: string) {
  const a = document.createElement('a');
  a.href = dataUrl;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

/**
 * 生成导出文件名
 */
export function generateExportFilename(
  format: string,
  modelType: string = 'model',
  runId: string = '',
): string {
  const timestamp = new Date().toISOString().slice(0, 19).replace(/[:-]/g, '');
  const shortRunId = runId.slice(0, 8);
  const ext = format.startsWith('csv') ? 'csv' : 'md';
  return `metrica_${modelType}_${shortRunId}_${timestamp}.${ext}`;
}
