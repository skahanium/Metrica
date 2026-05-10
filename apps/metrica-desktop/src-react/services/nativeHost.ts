export interface PickCsvResult {
  path: string | null;
  cancelled: boolean;
}

interface NativeResponse {
  path?: string | null;
  cancelled?: boolean;
  error?: string;
}

export async function pickCsvFile(): Promise<PickCsvResult> {
  let response: Response;
  try {
    response = await fetch('metrica://localhost/__native__/pick_csv');
  } catch {
    throw new Error('当前宿主不支持选择本地 CSV 文件');
  }

  const payload = await response.json() as NativeResponse;
  if (!response.ok) {
    throw new Error(payload.error || '当前宿主不支持选择本地 CSV 文件');
  }
  if (payload.error) {
    throw new Error(payload.error);
  }

  return {
    path: payload.path ?? null,
    cancelled: payload.cancelled ?? false,
  };
}
