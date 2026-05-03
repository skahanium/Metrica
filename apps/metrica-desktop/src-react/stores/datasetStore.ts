import { create } from 'zustand';
import type { DatasetSummary } from '../types/protocol';

interface DatasetState {
  sourcePath: string;
  activePath: string;
  summary: DatasetSummary | null;
  isDerived: () => boolean;
  setFilePath: (p: string) => void;
  setSourceAndActivePath: (sourcePath: string, activePath: string) => void;
  setActivePath: (p: string) => void;
  setSummary: (s: DatasetSummary | null) => void;
  resetDerived: () => void;
}

export const useDatasetStore = create<DatasetState>((set, get) => ({
  sourcePath: '',
  activePath: '',
  summary: null,
  isDerived: () => get().sourcePath !== get().activePath,
  setFilePath: (filePath) => set({ sourcePath: filePath, activePath: filePath }),
  setSourceAndActivePath: (sourcePath, activePath) => set({ sourcePath, activePath }),
  setActivePath: (activePath) => set({ activePath }),
  setSummary: (summary) => set({ summary }),
  resetDerived: () => set((state) => ({ activePath: state.sourcePath })),
}));
