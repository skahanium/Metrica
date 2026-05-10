import { create } from 'zustand';
import type { DataOp, TransformResult } from '../types/protocol';

export interface TransformHistoryItem {
  id: string;
  command: string;
  source: 'cli' | 'ui';
  datasetPath: string;
  result: TransformResult;
  createdAt: string;
}

interface TransformState {
  operations: DataOp[];
  history: TransformResult[];
  resultItems: TransformHistoryItem[];
  lastTransformResult: TransformResult | null;
  isTransforming: boolean;
  addOperation: (op: DataOp) => void;
  removeOperation: (index: number) => void;
  clearOperations: () => void;
  clearHistory: () => void;
  setTransforming: (isTransforming: boolean) => void;
  setLastTransformResult: (result: TransformResult | null) => void;
  appendHistory: (results: TransformResult[]) => void;
  addResultItem: (item: TransformHistoryItem) => void;
}

export const useTransformStore = create<TransformState>((set) => ({
  operations: [],
  history: [],
  resultItems: [],
  lastTransformResult: null,
  isTransforming: false,
  addOperation: (op) => set((state) => ({ operations: [...state.operations, op] })),
  removeOperation: (index) => set((state) => ({ operations: state.operations.filter((_, i) => i !== index) })),
  clearOperations: () => set({ operations: [] }),
  clearHistory: () => set({ history: [], resultItems: [], lastTransformResult: null }),
  setTransforming: (isTransforming) => set({ isTransforming }),
  setLastTransformResult: (lastTransformResult) => set({ lastTransformResult }),
  appendHistory: (results) => set((state) => ({ history: [...state.history, ...results] })),
  addResultItem: (item) => set((state) => ({
    resultItems: [item, ...state.resultItems.filter((existing) => existing.id !== item.id)].slice(0, 20),
  })),
}));
