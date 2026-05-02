import { create } from 'zustand';
import type { DatasetSummary } from '../types/protocol';

interface DatasetState {
  sourcePath: string;
  activePath: string;
  summary: DatasetSummary | null;
  isDerived: boolean;
  setFilePath: (p: string) => void;
  setActivePath: (p: string, isDerived?: boolean) => void;
  setSummary: (s: DatasetSummary | null) => void;
  resetDerived: () => void;
}

export const useDatasetStore = create<DatasetState>((set) => ({
  sourcePath: '',
  activePath: '',
  summary: null,
  isDerived: false,
  setFilePath: (filePath) => set({ sourcePath: filePath, activePath: filePath, isDerived: false }),
  setActivePath: (activePath, isDerived = false) => set({ activePath, isDerived }),
  setSummary: (summary) => set({ summary }),
  resetDerived: () => set((state) => ({ activePath: state.sourcePath, isDerived: false })),
}));
