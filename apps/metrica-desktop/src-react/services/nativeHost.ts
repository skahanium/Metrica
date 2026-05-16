export interface PickCsvResult {
  path: string | null;
  cancelled: boolean;
}

interface NativeResponse {
  path?: string | null;
  cancelled?: boolean;
  error?: string;
}

async function fetchNative(path: string): Promise<PickCsvResult> {
  let response: Response;
  try {
    response = await fetch(`metrica://localhost${path}`);
  } catch {
    throw new Error('当前宿主不支持本地文件对话框');
  }

  const payload = await response.json() as NativeResponse;
  if (!response.ok) {
    throw new Error(payload.error || '当前宿主不支持本地文件对话框');
  }
  if (payload.error) {
    throw new Error(payload.error);
  }

  return {
    path: payload.path ?? null,
    cancelled: payload.cancelled ?? false,
  };
}

export async function pickCsvFile(): Promise<PickCsvResult> {
  return fetchNative('/__native__/pick_csv');
}

/** 打开项目：选择项目根目录或 `.metrica/project.json` */
export async function pickProjectOpenPath(): Promise<PickCsvResult> {
  return fetchNative('/__native__/pick_project_open');
}

/** 保存项目：选择目标路径（书签式 `.metrica` / `.json` 或目录） */
export async function pickProjectSavePath(): Promise<PickCsvResult> {
  return fetchNative('/__native__/pick_project_save');
}

/**
 * 导出目标路径（报告 / CSV / 图表文件）。
 * @param suggestedFilename 建议文件名，如 `export.md`
 */
export async function pickExportSavePath(suggestedFilename: string): Promise<PickCsvResult> {
  const q = encodeURIComponent(suggestedFilename);
  return fetchNative(`/__native__/pick_export_save?filename=${q}`);
}
