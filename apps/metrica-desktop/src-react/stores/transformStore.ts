import { create } from 'zustand';
import type { DataOp, TransformResult } from '../types/protocol';

interface TransformState {
  operations: DataOp[];
  history: TransformResult[];
  lastTransformResult: TransformResult | null;
  isTransforming: boolean;
  addOperation: (op: DataOp) => void;
  removeOperation: (index: number) => void;
  clearOperations: () => void;
  clearHistory: () => void;
  setTransforming: (isTransforming: boolean) => void;
  setLastTransformResult: (result: TransformResult | null) => void;
  appendHistory: (results: TransformResult[]) => void;
}

export const useTransformStore = create<TransformState>((set) => ({
  operations: [],
  history: [],
  lastTransformResult: null,
  isTransforming: false,
  addOperation: (op) => set((state) => ({ operations: [...state.operations, op] })),
  removeOperation: (index) => set((state) => ({ operations: state.operations.filter((_, i) => i !== index) })),
  clearOperations: () => set({ operations: [] }),
  clearHistory: () => set({ history: [], lastTransformResult: null }),
  setTransforming: (isTransforming) => set({ isTransforming }),
  setLastTransformResult: (lastTransformResult) => set({ lastTransformResult }),
  appendHistory: (results) => set((state) => ({ history: [...state.history, ...results] })),
}));
