import { create } from 'zustand';
import type { DatasetSummary } from '../types/protocol';

interface DatasetState {
  filePath: string;
  summary: DatasetSummary | null;
  setFilePath: (p: string) => void;
  setSummary: (s: DatasetSummary | null) => void;
}

export const useDatasetStore = create<DatasetState>((set) => ({
  filePath: '',
  summary: null,
  setFilePath: (filePath) => set({ filePath }),
  setSummary: (summary) => set({ summary }),
}));
